package app.backupduck

import android.content.Context
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
import com.google.android.material.R as M
import com.google.android.material.materialswitch.MaterialSwitch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * What uses the Pixel's space, from the device's own readings. [photos] are the
 * files BackupDuck saved to the Pixel's Photos, [copies] BackupDuck's own copies
 * of received files; [other] is the rest of the used space. Unknown parts stay null.
 */
internal data class StorageParts(val total: Long, val free: Long, val photos: Long?, val copies: Long?) {
    val other: Long? get() = if (photos == null || copies == null) null else (total - free - photos - copies).coerceAtLeast(0)
}

/**
 * Storage (design/flows.md § How the Pixel keeps space free; P7): how much is
 * free, what uses the space, the two automatic ways to keep space free with
 * their consequences, and freeing space in Google Photos now. A page opened from
 * Settings and the hub; replaces the current Storage tab at migration step 6.
 */
internal class StorageScreen(private val activity: MainActivity, private val root: String, private val openPhotos: () -> Unit,
    private val openCleanup: () -> Unit, private val changed: () -> Unit) {
    private val page = LookPage(activity, activity.getString(R.string.pref_storage))
    private val free = activity.lookText("—", R.style.TextAppearance_BackupDuck_Display)
    private val capacity = activity.lookText("", M.style.TextAppearance_Material3_BodyLarge, secondary = true)
    private val bar = UsageBar(activity)
    private val legend = FlowRow(activity, activity.token(R.dimen.duck_space_small))
    private lateinit var cleanup: MaterialSwitch
    private lateinit var relay: MaterialSwitch
    private lateinit var relaySupport: TextView
    private val failure = activity.duckError(activity.getString(R.string.storage_save_failed))
    private var load: Job? = null
    private var relayOn: Boolean? = null

    init { with(activity) {
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
        val group = lookGroup(body)
        cleanup = lookSwitchRow(group, null, getString(R.string.storage_cleanup), getString(R.string.storage_cleanup_note), PhotosCleanup(this).enabled) { on ->
            if (on) { cleanup.restore(false); openCleanup() }  // Consent and the Google Photos account are set up there first.
            else { PhotosCleanup(this).enabled = false; PhotosProbeService.stop(); changed() }
        }.toggle
        val relayRow = lookSwitchRow(group, null, getString(R.string.storage_relay), getString(R.string.storage_relay_note), false, ::saveRelay)
        relay = relayRow.toggle; relaySupport = relayRow.supporting
        relay.isEnabled = false
        body.addView(failure, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_x_small); marginStart = token(R.dimen.duck_space_medium) })

        lookSection(body, getString(R.string.storage_now))
        val now = lookCard(body)
        now.addView(lookText(getString(R.string.storage_free_up_note), M.style.TextAppearance_Material3_BodyMedium, secondary = true))
        now.addView(lookButton(getString(R.string.rhub_free_up), LookButton.TONAL, action = openPhotos), LinearLayout.LayoutParams(-2, -2).apply { topMargin = token(R.dimen.duck_space_small) })
        page.resumed = { cleanup.restore(PhotosCleanup(this).enabled); changed() }
        page.setOnDismissListener { load?.cancel() }
    } }

    fun show() { page.show(); reload() }
    val isShowing: Boolean get() = page.isShowing
    fun dismiss() = page.dismiss()

    private fun reload() {
        load?.cancel()
        load = activity.lifecycleScope.launch {
            val storage = ReceiverEnvironment.deviceStorage(activity)
            free.text = size(storage.freeBytes)
            capacity.text = activity.getString(R.string.storage_free_of, size(storage.totalBytes))
            val settings = withContext(Dispatchers.IO) { runCatching { NativeBridge.request(JSONObject().put("op", "receiver_settings").put("root", root)) as JSONObject } }
            settings.onSuccess { data ->
                relayOn = data.getJSONObject("settings").optBoolean("receiver_relay", false)
                relay.restore(relayOn == true); relay.isEnabled = true; relaySupport.setText(R.string.storage_relay_note)
            }.onFailure { relay.isEnabled = false; relaySupport.setText(R.string.storage_relay_unavailable) }
            val copies = withContext(Dispatchers.IO) { runCatching {
                (NativeBridge.request(JSONObject().put("op", "receiver_storage_usage").put("root", root)) as JSONObject).let { it.getLong("ready_bytes") + it.getLong("partial_bytes") }
            }.getOrNull() }
            val photos = runCatching { ReceiverEnvironment.galleryUsage(activity).let { it.readyBytes + it.pendingBytes } }.getOrNull()
            if (!page.isShowing) return@launch
            val parts = StorageParts(storage.totalBytes, storage.freeBytes, photos, copies)
            bar.render(parts); legend(parts)
        }
    }

    /** A legend entry per part; "—" until it is read, never a guess (I3 Opening). */
    private fun legend(parts: StorageParts?) = with(activity) {
        legend.removeAllViews()
        fun entry(color: Int, label: Int, bytes: Long?) = legend.addView(lookText(getString(label, bytes?.let(::size) ?: "—"), M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply {
            setCompoundDrawablesRelativeWithIntrinsicBounds(GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(color); setSize(dp(8), dp(8)) }, null, null, null)
            compoundDrawablePadding = token(R.dimen.duck_space_x_small); gravity = Gravity.CENTER_VERTICAL
        })
        entry(getColor(R.color.duck_role_accent), R.string.storage_part_photos, parts?.photos)
        if ((parts?.copies ?: 0L) > 0) entry(getColor(R.color.duck_m3_tertiary), R.string.storage_part_copies, parts?.copies)
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

    private fun size(bytes: Long) = Formatter.formatShortFileSize(activity, bytes)
}

/** The used space as one rounded bar: BackupDuck's photos in Photos, its own copies and the rest; the track is free space. */
private class UsageBar(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var parts: StorageParts? = null
    init { importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO }
    fun render(value: StorageParts) { parts = value; invalidate() }
    override fun onDraw(canvas: Canvas) {
        val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
        canvas.save(); canvas.clipPath(Path().apply { addRoundRect(rect, height / 2f, height / 2f, Path.Direction.CW) })
        paint.color = context.getColor(R.color.duck_role_elevated_surface); canvas.drawRect(rect, paint)
        val value = parts
        if (value != null && value.total > 0) {
            var x = 0f
            listOf(value.photos to R.color.duck_role_accent, value.copies to R.color.duck_m3_tertiary, value.other to R.color.duck_m3_outline).forEach { (bytes, color) ->
                val end = (x + width * (bytes ?: 0L).toFloat() / value.total).coerceAtMost(width.toFloat())
                paint.color = context.getColor(color); canvas.drawRect(x, 0f, end, height.toFloat(), paint); x = end
            }
        }
        canvas.restore()
    }
}
