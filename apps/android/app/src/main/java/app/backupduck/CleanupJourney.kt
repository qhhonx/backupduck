package app.backupduck

import android.os.Bundle
import android.text.format.DateFormat
import android.text.format.Formatter
import android.view.View
import android.widget.LinearLayout
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.progressindicator.LinearProgressIndicator
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import com.google.android.material.R as M

/** Shared ordinary-user actions over the existing durable preferences and bounded service. */
internal class CleanupJourney(private val activity: MainActivity, private val page: PageDestination,
    private val changed: () -> Unit) {
    private val facts get() = PhotosCleanup(activity)
    private val operations get() = ReceiverEnvironment.cleanupOperations
    private var sheet: LookSheet? = null
    private var sheetKind = ""
    private var finishingSheet = false
    /// The system connects the accessibility service a moment after it is
    /// turned on; returning from Settings can be quicker than that.
    private var awaitingService = false
    private val observation = activity.lifecycleScope.launch {
        activity.lifecycle.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
            operations.state.collect { if (page.isShowing) refresh() }
        }
    }
    val running get() = operations.state.value.let { it.running && it.mode != "probe" }
    val pending get() = facts.pending
    val status: CleanupStatus get() = activity.currentCleanupStatus()
    fun text(): String = activity.cleanupStatusText(status)
    fun action(): Pair<Int, () -> Unit>? = when (status) {
        CleanupStatus.RUNNING, CleanupStatus.BINDING -> R.string.auto_cleanup_stop to ::stop
        CleanupStatus.REVIEW -> if (page.state.getBoolean("cleanup-reviewed-return")) R.string.auto_cleanup_reviewed to ::reviewed
            else R.string.auto_cleanup_open_photos to ::openPhotos
        CleanupStatus.ACCOUNT -> R.string.auto_cleanup_confirm to { confirm(!facts.enabled) }
        CleanupStatus.ACCESS, CleanupStatus.WAITING_ACCESS -> R.string.auto_cleanup_turn_on to ::enable
        CleanupStatus.UNAVAILABLE -> R.string.auto_cleanup_open_photos to ::openPhotos
        CleanupStatus.FAILED, CleanupStatus.STOPPED -> R.string.auto_cleanup_retry to { if (facts.enabled) run() else enable() }
        else -> null
    }
    fun lastResult(): String = with(activity) {
        if (facts.lastResult == "nothing_to_free" || facts.reason == "nothing_to_free") return getString(R.string.auto_cleanup_nothing)
        val time = facts.lastCompletedAt ?: return getString(R.string.auto_cleanup_no_result)
        val locale = resources.configuration.locales[0]
        val date = java.text.SimpleDateFormat(DateFormat.getBestDateTimePattern(locale, "MMMd"), locale).format(java.util.Date(time))
        facts.lastFreedBytes?.let { return getString(R.string.storage_cleanup_last_freed, Formatter.formatShortFileSize(this, it), date) }
        getString(R.string.auto_cleanup_result_unknown, date)
    }
    fun resumed() {
        if (page.state.getBoolean("cleanup-opened-photos")) {
            page.state.remove("cleanup-opened-photos")
            page.state.putBoolean("cleanup-reviewed-return", true)
        }
        // Both automatic and manual returns re-check accessibility access before
        // advancing. The durable access step is consumed before binding starts.
        when (facts.accessRecovery.resumed(ReceiverEnvironment.cleanupAccess(activity))) {
            CleanupAccessNext.BIND -> startBinding()
            CleanupAccessNext.ACCESS_REQUIRED -> { facts.enableAfterBinding = false; facts.report("access_required") }
            CleanupAccessNext.NONE -> Unit
        }
        refresh()
    }
    fun refresh() {
        if (facts.journey == "binding" && !running && !awaitingService) {
            if (facts.reason == "bound" && facts.account.isNotEmpty() && ReceiverEnvironment.cleanupAccess(activity)) {
                if (facts.enableAfterBinding) facts.enabled = true
            } else if (facts.reason in setOf("ready", "idle")) facts.report("interrupted")
            facts.journey = ""; facts.enableAfterBinding = false
        }
        val kind = if (facts.journey == "access") "access" else if (facts.journey == "binding" && running) "binding" else ""
        if (sheetKind != "consent" && kind != sheetKind) {
            closeSheet()
            if (kind.isNotEmpty() && page.fragment?.isResumed == true) progress(kind)
        }
        changed()
    }
    fun setEnabled(on: Boolean) {
        if (on) enable() else {
            facts.enabled = false; facts.enableAfterBinding = false; facts.journey = ""
            operations.stop(); closeSheet(); refresh()
        }
    }
    fun enable() {
        if (sheet?.isShowing == true) return
        facts.enabled = false
        page.state.putBoolean("cleanup-consent", true)
        sheetKind = "consent"
        sheet = activity.lookConsentSheet(activity.getString(R.string.storage_cleanup_consent_title), listOf(
            activity.getString(R.string.storage_cleanup_consent_action), activity.getString(R.string.storage_cleanup_consent_photos),
            activity.getString(R.string.storage_cleanup_consent_access)), activity.getString(R.string.auto_cleanup_consent_check),
            activity.getString(R.string.onb_later), activity.getString(R.string.storage_cleanup_go_settings)) {
            // Dismiss callbacks can arrive after the positive action. Retire the
            // consent owner before showing progress so it cannot clear the new sheet.
            closeSheet()
            page.state.remove("cleanup-consent")
            activity.getSharedPreferences("photos_probe", 0).edit().putBoolean("cleanup_disclosure_v2", true).apply()
            facts.enableAfterBinding = true
            facts.accessRecovery.waiting(page.route, System.currentTimeMillis())
            facts.report("access_required")
            refresh()
            runCatching { operations.access(activity, ::resumed) }.onFailure {
                facts.journey = ""; facts.enableAfterBinding = false; facts.report("access_required"); refresh()
            }
        }.also { consent ->
            consent.setOnDismissListener {
                page.state.remove("cleanup-consent")
                if (sheet === consent) {
                    sheet = null; sheetKind = ""
                    if (facts.journey.isEmpty()) { facts.report("setup_cancelled"); changed() }
                }
            }
            consent.show()
        }
    }
    fun confirm(enableAfter: Boolean = false) {
        if (running) return
        if (facts.pending) { openPhotos(); return }
        if (!activity.getSharedPreferences("photos_probe", 0).getBoolean("cleanup_disclosure_v2", false) ||
            !ReceiverEnvironment.cleanupAccess(activity)) { enable(); return }
        facts.enableAfterBinding = enableAfter
        if (enableAfter) facts.enabled = false
        startBinding()
    }
    private fun startBinding() {
        if (running || awaitingService) return
        facts.journey = "binding"; facts.report("ready")
        if (!operations.state.value.connected) {
            awaitingService = true
            activity.lifecycleScope.launch {
                val connected = withTimeoutOrNull(10_000) { operations.state.first { it.connected } } != null
                awaitingService = false
                if (!connected || !operations.start(activity, true, page.route)) {
                    facts.journey = ""; facts.enableAfterBinding = false; facts.report("disconnected")
                }
                refresh()
            }
            refresh(); return
        }
        if (!operations.start(activity, true, page.route)) {
            facts.journey = ""; facts.enableAfterBinding = false; facts.report("disconnected")
        }
        refresh()
    }
    fun run() {
        if (running) return
        if (!activity.getSharedPreferences("photos_probe", 0).getBoolean("cleanup_disclosure_v2", false)) { enable(); return }
        if (!ReceiverEnvironment.cleanupAccess(activity)) { facts.report("access_required"); refresh(); return }
        if (facts.account.isEmpty()) { facts.report("account_unavailable"); refresh(); return }
        if (!operations.start(activity, false, page.route)) facts.report("disconnected")
        refresh()
    }
    fun stop() {
        facts.journey = ""; facts.enableAfterBinding = false
        operations.stop(); facts.report(if (facts.pending) "pending" else "stopped")
        facts.cooldown(15 * 60_000); closeSheet(); refresh()
    }
    fun openPhotos() {
        page.state.putBoolean("cleanup-opened-photos", true)
        runCatching { operations.photos(activity, ::resumed) }.onFailure {
            page.state.remove("cleanup-opened-photos"); facts.report("unavailable"); changed()
        }
    }
    fun reviewed() {
        MaterialAlertDialogBuilder(activity).setTitle(R.string.auto_cleanup_reviewed)
            .setMessage(R.string.auto_cleanup_reviewed_note).setNegativeButton(R.string.onb_later, null)
            .setPositiveButton(R.string.auto_cleanup_reviewed) { _, _ ->
                facts.reviewed(); page.state.remove("cleanup-reviewed-return"); page.state.remove("cleanup-opened-photos"); changed()
            }.show()
    }
    private fun progress(kind: String) {
        sheetKind = kind
        sheet = LookSheet(activity).also { progress ->
            val inset = activity.token(R.dimen.duck_space_medium)
            progress.body.setPadding(inset, 0, inset, inset)
            progress.body.addView(activity.lookText(activity.getString(if (kind == "access") R.string.auto_cleanup_waiting_access else R.string.auto_cleanup_binding), M.style.TextAppearance_Material3_TitleLarge))
            progress.body.addView(LinearProgressIndicator(activity).apply { isIndeterminate = true }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = inset })
            progress.body.addView(activity.lookText(activity.getString(if (kind == "access") R.string.auto_cleanup_access_return else R.string.auto_cleanup_binding_note), M.style.TextAppearance_Material3_BodyMedium, secondary = true), LinearLayout.LayoutParams(-1,-2).apply { topMargin = inset })
            if (kind == "access") progress.body.addView(activity.lookText(activity.getString(R.string.cleanup_access_return_note),
                M.style.TextAppearance_Material3_BodyMedium, secondary = true),
                LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.token(R.dimen.duck_space_small) })
            progress.body.addView(activity.lookButton(activity.getString(R.string.auto_cleanup_stop), LookButton.TEXT) { stop() })
            progress.setOnDismissListener {
                if (!finishingSheet) {
                    facts.journey = ""; facts.enableAfterBinding = false; operations.stop(); facts.report("stopped"); changed()
                }
                sheet = null; sheetKind = ""
            }
            progress.show()
        }
    }
    private fun closeSheet() {
        finishingSheet = true
        sheet?.setOnDismissListener(null)
        sheet?.dismiss(); sheet = null; sheetKind = ""; finishingSheet = false
    }
    fun close() {
        observation.cancel()
        val restoringAccess = facts.journey == "access" && !activity.isFinishing && page.fragment?.isRemoving != true
        if (!activity.isChangingConfigurations && !restoringAccess && facts.journey.isNotEmpty()) {
            facts.journey = ""; facts.enableAfterBinding = false; operations.stop(); facts.report("interrupted")
        }
        closeSheet()
    }
}
