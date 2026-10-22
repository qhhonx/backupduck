package app.backupduck

import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.os.Bundle
import android.provider.Settings
import android.text.format.DateFormat
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.text.format.Formatter
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.google.android.material.R as M
import com.google.android.material.materialswitch.MaterialSwitch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * What uses the Pixel's space, from the device's own readings. [photos] are the
 * gallery files from BackupDuck (including pending saves), [copies] its own copies
 * of received files; [other] is the rest of the used space. Unknown parts stay null.
 */
internal data class StorageParts(val total: Long?, val free: Long?, val photos: Long?, val copies: Long?) {
    val other: Long? get() = if (total == null || free == null || photos == null || copies == null) null else (total - free - photos - copies).coerceAtLeast(0)
}

/** Logical bytes of receiver-managed originals, excluding gallery copies and app overhead. */
private class ReceiverCopyStorage(private val data: JSONObject) {
    private fun bytes(name: String): Long? = if (data.isNull(name)) null else data.getLong(name)
    val own = bytes("own_copy_bytes")
    val converted = bytes("converted_original_bytes")
    val pending = bytes("pending_bytes")
    val other = bytes("other_original_bytes")
    // This overlaps the categories above; it is never added to used space.
    val reclaimable = bytes("reclaimable_bytes")
    val free = bytes("free_bytes")
}

/**
 * Storage (design/flows.md § How the Pixel keeps space free; P7): how much is
 * free, what uses the space, the two automatic ways to keep space free with
 * their consequences, and freeing space in Google Photos now. A page opened from
 * Settings and the hub; replaces the current Storage tab at migration step 6.
 */
internal class StorageScreen(private val activity: MainActivity, private val root: String, private val openPhotos: () -> Unit,
    restored: Bundle = Bundle(), private val changed: () -> Unit) {
    val page = LookPage(activity, activity.getString(R.string.pref_storage), "storage")
    private val free = activity.lookText(activity.getString(R.string.storage_free_amount, "—"), R.style.TextAppearance_BackupDuck_Display)
    private val capacity = activity.lookText(activity.getString(R.string.storage_free_of, "—"), M.style.TextAppearance_Material3_BodyLarge, secondary = true)
    private val bar = UsageBar(activity)
    private val legend = FlowRow(activity, activity.token(R.dimen.duck_space_small))
    private lateinit var copySection: LinearLayout
    private lateinit var copyRows: LinearLayout
    private lateinit var reclaimableNote: TextView
    private lateinit var cleanup: MaterialSwitch
    private lateinit var cleanupSupport: TextView
    private lateinit var smartSupport: TextView
    private lateinit var cleanupGroup: LinearLayout
    private var consentSheet: LookSheet? = null
    private lateinit var relay: MaterialSwitch
    private lateinit var relaySupport: TextView
    private val failure = activity.duckError(activity.getString(R.string.storage_save_failed))
    private var observation: Job? = null
    private var load: Job? = null
    private var relayOn: Boolean? = null

    init { with(activity) {
        page.state.putAll(restored)
        val body = page.body
        val summary = lookCard(body)
        val amount = LinearLayout(this).apply { gravity = Gravity.BOTTOM }
        amount.addView(free)
        amount.addView(capacity, LinearLayout.LayoutParams(-2, -2).apply { marginStart = token(R.dimen.duck_space_x_small); bottomMargin = dp(4) })
        summary.addView(amount)
        summary.addView(bar, LinearLayout.LayoutParams(-1, dp(10)).apply { topMargin = token(R.dimen.duck_space_small) })
        summary.addView(legend, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_small) })
        legend(null)

        lookSection(body, getString(R.string.storage_automatic))
        cleanupGroup = lookGroup(body)
        smartSupport = lookRow(cleanupGroup, R.drawable.ic_storage, getString(R.string.storage_smart), getString(R.string.history_loading),
            trailing = android.widget.ImageView(this).apply {
                setImageResource(R.drawable.ic_chevron)
                imageTintList = android.content.res.ColorStateList.valueOf(getColor(R.color.duck_role_secondary_text))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }) {
            runCatching {
                startActivity(Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.Settings\$AutomaticStorageManagerSettingsActivity")))
            }.recoverCatching { startActivity(Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS)) }
                .onFailure { smartSupport.setSupporting(getString(R.string.storage_smart_unavailable)) }
        }
        val cleanupRow = lookSwitchRow(cleanupGroup, R.drawable.ic_bolt, getString(R.string.storage_cleanup),
            getString(R.string.storage_cleanup_note), PhotosCleanup(this).enabled, getString(R.string.onb_space_experiment)) { on ->
            if (on) { cleanup.restore(false); showCleanupConsent() }
            else {
                page.state.remove("cleanup-awaiting-access")
                PhotosCleanup(this).enabled = false; PhotosProbeService.stop(); refreshCleanup(); changed()
            }
        }
        cleanup = cleanupRow.toggle; cleanupSupport = cleanupRow.supporting
        body.addView(lookText(getString(R.string.storage_cleanup_footnote), M.style.TextAppearance_Material3_BodyMedium, secondary = true),
            LinearLayout.LayoutParams(-1, -2).apply {
                topMargin = token(R.dimen.duck_space_small)
                marginStart = token(R.dimen.duck_space_medium); marginEnd = token(R.dimen.duck_space_medium)
            })

        copySection = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        body.addView(copySection, LinearLayout.LayoutParams(-1, -2))
        lookSection(copySection, getString(R.string.storage_copies_on_pixel))
        copyRows = lookGroup(copySection)
        reclaimableNote = lookText("", M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply { visibility = View.GONE }
        copySection.addView(reclaimableNote, LinearLayout.LayoutParams(-1, -2).apply {
            topMargin = token(R.dimen.duck_space_small)
            marginStart = token(R.dimen.duck_space_medium); marginEnd = token(R.dimen.duck_space_medium)
        })
        val copyNote = lookText(getString(R.string.storage_copies_scope), M.style.TextAppearance_Material3_BodyMedium, secondary = true)
        copySection.addView(copyNote, LinearLayout.LayoutParams(-1, -2).apply {
            topMargin = token(R.dimen.duck_space_small)
            marginStart = token(R.dimen.duck_space_medium); marginEnd = token(R.dimen.duck_space_medium)
        })
        renderCopies(null)

        val group = lookGroup(body)
        val relayRow = lookSwitchRow(group, null, getString(R.string.storage_relay), getString(R.string.storage_relay_note), false, changed = ::saveRelay)
        relay = relayRow.toggle; relaySupport = relayRow.supporting
        relay.isEnabled = false
        body.addView(failure, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_x_small); marginStart = token(R.dimen.duck_space_medium) })

        lookSection(body, getString(R.string.storage_now))
        val now = lookCard(body)
        now.addView(lookText(getString(R.string.storage_free_up_note), M.style.TextAppearance_Material3_BodyMedium, secondary = true))
        now.addView(lookButton(getString(R.string.rhub_free_up), LookButton.TONAL, action = openPhotos), LinearLayout.LayoutParams(-2, -2).apply { topMargin = token(R.dimen.duck_space_small) })
        page.resumed = {
            FeatureDiscovery(this).acknowledge(FeatureDiscovery.PHOTOS_CLEANUP)
            if (page.state.getBoolean("cleanup-awaiting-access")) {
                page.state.remove("cleanup-awaiting-access")
                if (ReceiverEnvironment.cleanupAccess(this)) PhotosCleanup(this).enabled = true
            }
            refreshCleanup(); reload(); changed()
            if (page.state.getBoolean("cleanup-consent")) showCleanupConsent()
        }
        page.setOnDismissListener { load?.cancel(); observation?.cancel(); consentSheet?.dismiss() }
        observation = lifecycleScope.launch {
            page.activity.lifecycle.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                PhotosProbeService.state.collect { if (page.isShowing) refreshCleanup() }
            }
        }
    } }

    fun show() { page.show(); reload() }
    val isShowing: Boolean get() = page.isShowing
    fun dismiss() = page.dismiss()

    fun focusCleanup() {
        page.root.post {
            page.root.findViewById<androidx.core.widget.NestedScrollView>(R.id.destination_scroll)?.smoothScrollTo(0, cleanupGroup.top)
            cleanup.requestFocus()
        }
    }

    fun showCleanupConsent() = with(activity) {
        if (consentSheet?.isShowing == true) return@with
        page.state.putBoolean("cleanup-consent", true)
        val sheet = lookConsentSheet(getString(R.string.storage_cleanup_consent_title), listOf(
            getString(R.string.storage_cleanup_consent_action), getString(R.string.storage_cleanup_consent_photos),
            getString(R.string.storage_cleanup_consent_access)), getString(R.string.storage_cleanup_consent_experiment),
            getString(R.string.onb_later), getString(R.string.storage_cleanup_go_settings)) {
            runCatching {
                // Existing disclosure key is shared with the technical setup pages.
                getSharedPreferences("photos_probe", Context.MODE_PRIVATE).edit().putBoolean("cleanup_disclosure_v2", true).apply()
                page.state.putBoolean("cleanup-awaiting-access", true)
                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            }.onFailure {
                page.state.remove("cleanup-awaiting-access")
                cleanupSupport.setSupporting(getString(R.string.storage_cleanup_settings_failed))
            }
        }
        consentSheet = sheet
        sheet.setOnDismissListener { page.state.remove("cleanup-consent"); consentSheet = null; cleanup.requestFocus() }
        sheet.show()
    }

    private fun refreshCleanup() = with(activity) {
        smartSupport.setSupporting(getString(when (ReceiverEnvironment.smartStorage(this)) {
            true -> R.string.storage_smart_on; false -> R.string.storage_smart_off; null -> R.string.storage_smart_unknown
        }))
        val facts = PhotosCleanup(this)
        cleanup.restore(facts.enabled)
        val reason = facts.reason
        var recovery: (() -> Unit)? = null
        val subtitle = when {
            !facts.enabled -> getString(R.string.storage_cleanup_note)
            reason == "unrecognized" -> {
                recovery = openPhotos; getString(R.string.storage_cleanup_changed)
            }
            reason in setOf("manual_review_required", "pending", "return_home_failed") -> {
                recovery = openPhotos; getString(R.string.storage_cleanup_review)
            }
            reason == "expired" -> {
                recovery = openPhotos; getString(R.string.storage_cleanup_timeout)
            }
            reason == "account_changed" -> {
                recovery = { showDiagnostics() }; getString(R.string.storage_cleanup_account_changed)
            }
            facts.account.isEmpty() -> {
                recovery = { showDiagnostics() }; getString(R.string.storage_cleanup_account)
            }
            !ReceiverEnvironment.cleanupAccess(this) -> {
                recovery = { showCleanupConsent() }; getString(R.string.storage_cleanup_access_off)
            }
            facts.lastCompletedAt != null -> {
                val date = DateFormat.getBestDateTimePattern(resources.configuration.locales[0], "MMMd")
                    .let { java.text.SimpleDateFormat(it, resources.configuration.locales[0]).format(java.util.Date(facts.lastCompletedAt!!)) }
                facts.lastFreedBytes?.let { getString(R.string.storage_cleanup_last_freed, size(it), date) }
                    ?: getString(R.string.storage_cleanup_last_completed, date)
            }
            else -> getString(R.string.storage_cleanup_never)
        }
        cleanupSupport.setSupporting(subtitle)
        cleanupSupport.isClickable = recovery != null; cleanupSupport.isFocusable = recovery != null
        cleanupSupport.setOnClickListener(recovery?.let { run -> View.OnClickListener { run() } })
    }

    private fun reload() {
        load?.cancel()
        load = activity.lifecycleScope.launch {
            val storage = withContext(Dispatchers.IO) { runCatching { ReceiverEnvironment.deviceStorage(activity) }.getOrNull() }
            val settings = withContext(Dispatchers.IO) { runCatching { NativeBridge.request(JSONObject().put("op", "receiver_settings").put("root", root)) as JSONObject } }
            settings.onSuccess { data ->
                relayOn = data.getJSONObject("settings").optBoolean("receiver_relay", false)
                relay.restore(relayOn == true); relay.isEnabled = true; relaySupport.setText(R.string.storage_relay_note)
            }.onFailure { relay.isEnabled = false; relaySupport.setText(R.string.storage_relay_unavailable) }
            val copies = withContext(Dispatchers.IO) { runCatching {
                ReceiverCopyStorage(NativeBridge.request(JSONObject().put("op", "receiver_storage_breakdown").put("root", root)) as JSONObject)
            }.getOrNull() }
            val photos = withContext(Dispatchers.IO) { runCatching {
                ReceiverEnvironment.galleryUsage(activity).let { if (it.unknownSizes > 0) null else it.readyBytes + it.pendingBytes }
            }.getOrNull() }
            if (!page.isShowing) return@launch
            // A missing receiver root has no free-space reading; the host can still measure this device.
            val available = copies?.free ?: storage?.freeBytes
            free.text = activity.getString(R.string.storage_free_amount, amount(available))
            capacity.text = activity.getString(R.string.storage_free_of, amount(storage?.totalBytes))
            val parts = StorageParts(storage?.totalBytes, available, photos, copies?.own)
            bar.render(parts); legend(parts)
            renderCopies(copies)
        }
    }

    private fun renderCopies(copies: ReceiverCopyStorage?) = with(activity) {
        // Rebuild this bounded, read-only group so hidden rows leave no separators.
        copyRows.removeAllViews()
        val amounts = listOf(copies?.converted, copies?.pending, copies?.other)
        listOf(R.string.storage_copies_converted, R.string.storage_copies_pending,
            R.string.storage_copies_other).forEachIndexed { index, label ->
            val bytes = amounts[index]
            if (bytes != 0L) lookRow(copyRows, null, getString(label), copySupporting(index, bytes))
        }
        // Unknown readings retain their placeholders; only measured zeroes are omitted.
        copySection.visibility = if (copyRows.childCount == 0) View.GONE else View.VISIBLE
        reclaimableNote.setSupporting(copies?.reclaimable?.takeIf { it > 0 }?.let {
            getString(R.string.storage_copies_reclaimable, amount(it))
        })
    }

    /** A legend entry per part; "—" until it is read, never a guess (I3 Opening). */
    private fun legend(parts: StorageParts?) = with(activity) {
        legend.removeAllViews()
        fun entry(color: Int, label: Int, bytes: Long?) = legend.addView(lookText(getString(label, bytes?.let(::size) ?: "—"), M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply {
            setCompoundDrawablesRelativeWithIntrinsicBounds(GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(color); setSize(dp(8), dp(8)) }, null, null, null)
            compoundDrawablePadding = token(R.dimen.duck_space_x_small); gravity = Gravity.CENTER_VERTICAL
        })
        entry(getColor(R.color.duck_role_accent), R.string.storage_part_photos, parts?.photos)
        entry(getColor(R.color.duck_m3_tertiary), R.string.storage_part_copies, parts?.copies)
        entry(getColor(R.color.duck_m3_outline), R.string.storage_part_other, parts?.other)
    }

    private fun saveRelay(on: Boolean) {
        relay.isEnabled = false; failure.visibility = View.GONE
        activity.lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) { runCatching {
                // Photos already saved count too: freeing space is the point of the switch.
                NativeBridge.request(JSONObject().put("op", "set_receiver_relay").put("root", root).put("enabled", on).put("include_history", true))
            } }
            relay.isEnabled = true
            if (result.isSuccess) {
                relayOn = on
                RelayMaintenance.cancelAutomatic(); if (on) RelayMaintenance.schedule(activity)
                reload()
            } else { relay.restore(relayOn == true); failure.visibility = View.VISIBLE }
        }
    }

    private fun copySupporting(index: Int, bytes: Long?): String = amount(bytes) +
        if (index == 0) "\n" + activity.getString(R.string.storage_copies_converted_note) else ""

    private fun size(bytes: Long) = Formatter.formatShortFileSize(activity, bytes)
    private fun amount(bytes: Long?) = bytes?.let(::size) ?: "—"
}

/** The used space as one rounded bar: BackupDuck's photos in Photos, its own copies and the rest; the track is free space. */
private class UsageBar(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var parts: StorageParts? = null
    init { importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO; visibility = INVISIBLE }
    fun render(value: StorageParts) {
        parts = value
        visibility = if (value.total != null && value.total > 0 && value.other != null) VISIBLE else INVISIBLE
        invalidate()
    }
    override fun onDraw(canvas: Canvas) {
        val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
        canvas.save(); canvas.clipPath(Path().apply { addRoundRect(rect, height / 2f, height / 2f, Path.Direction.CW) })
        paint.color = context.getColor(R.color.duck_role_elevated_surface); canvas.drawRect(rect, paint)
        val value = parts
        // Without every reading, segments would make unknown space look free.
        if (value?.total != null && value.total > 0 && value.other != null) {
            var x = 0f
            listOf(value.photos to R.color.duck_role_accent, value.copies to R.color.duck_m3_tertiary, value.other to R.color.duck_m3_outline).forEach { (bytes, color) ->
                val end = (x + width * (bytes ?: 0L).toFloat() / value.total).coerceAtMost(width.toFloat())
                paint.color = context.getColor(color); canvas.drawRect(x, 0f, end, height.toFloat(), paint); x = end
            }
        }
        canvas.restore()
    }
}
