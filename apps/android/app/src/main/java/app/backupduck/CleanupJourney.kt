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
import kotlinx.coroutines.launch
import com.google.android.material.R as M

/** Shared ordinary-user actions over the existing durable preferences and bounded service. */
internal class CleanupJourney(private val activity: MainActivity, private val page: PageDestination,
    private val changed: () -> Unit) {
    private val facts get() = PhotosCleanup(activity)
    private val operations get() = ReceiverEnvironment.cleanupOperations
    private var sheet: LookSheet? = null
    private var sheetKind = ""
    private var finishingSheet = false
    private val observation = activity.lifecycleScope.launch {
        activity.lifecycle.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
            operations.state.collect { if (page.isShowing) refresh() }
        }
    }
    val running get() = operations.state.value.let { it.running && it.mode != "probe" }
    val pending get() = facts.pending
    val status: CleanupStatus get() {
        val live = operations.state.value
        val reason = if (!live.running || live.mode == "probe") facts.reason else live.observation
        return cleanupStatus(facts.enabled, facts.account.isNotEmpty(), ReceiverEnvironment.cleanupAccess(activity),
            facts.pending, live.running, live.mode, reason, facts.journey)
    }
    fun text(): String = activity.getString(when (status) {
        CleanupStatus.IDLE -> R.string.auto_cleanup_idle
        CleanupStatus.RUNNING -> R.string.auto_cleanup_running
        CleanupStatus.BINDING -> R.string.auto_cleanup_binding
        CleanupStatus.REVIEW -> R.string.auto_cleanup_review
        CleanupStatus.ACCOUNT -> R.string.auto_cleanup_account
        CleanupStatus.ACCESS -> R.string.auto_cleanup_access
        CleanupStatus.LOCKED -> R.string.auto_cleanup_locked
        CleanupStatus.UNAVAILABLE -> R.string.auto_cleanup_unavailable
        CleanupStatus.STOPPED -> if (facts.enabled) R.string.auto_cleanup_stopped else R.string.auto_cleanup_setup_stopped
        CleanupStatus.FAILED -> R.string.auto_cleanup_failed
        CleanupStatus.WAITING_ACCESS -> R.string.auto_cleanup_waiting_access
    })
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
        if (facts.journey == "access") {
            if (ReceiverEnvironment.cleanupAccess(activity)) startBinding()
            else { facts.journey = ""; facts.enableAfterBinding = false; facts.report("access_required") }
        }
        refresh()
    }
    fun refresh() {
        if (facts.journey == "binding" && !running) {
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
            activity.getSharedPreferences("photos_probe", 0).edit().putBoolean("cleanup_disclosure_v2", true).apply()
            facts.enableAfterBinding = true; facts.journey = "access"; facts.report("access_required")
            refresh()
            runCatching { operations.access(activity, ::resumed) }.onFailure {
                facts.journey = ""; facts.enableAfterBinding = false; facts.report("access_required"); refresh()
            }
        }.also { consent ->
            consent.setOnDismissListener {
                page.state.remove("cleanup-consent"); sheet = null; sheetKind = ""
                // The positive action runs after dismissal and replaces this cancelled state.
                if (facts.journey.isEmpty()) { facts.report("setup_cancelled"); changed() }
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
        if (running) return
        facts.journey = "binding"; facts.report("ready")
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
        finishingSheet = true; sheet?.dismiss(); sheet = null; sheetKind = ""; finishingSheet = false
    }
    fun close() {
        observation.cancel()
        if (!activity.isChangingConfigurations && facts.journey.isNotEmpty()) {
            facts.journey = ""; facts.enableAfterBinding = false; operations.stop(); facts.report("interrupted")
        }
        closeSheet()
    }
}
