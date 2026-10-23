package app.backupduck

import android.content.Context

/** Shared projection for the hub, navigation marks, Storage and its detail page. */
internal fun Context.currentCleanupStatus(): CleanupStatus {
    val facts = PhotosCleanup(this)
    val live = ReceiverEnvironment.cleanupOperations.state.value
    val reason = if (!live.running || live.mode == "probe") facts.reason else live.observation
    return cleanupStatus(facts.enabled, facts.account.isNotEmpty(), ReceiverEnvironment.cleanupAccess(this),
        facts.pending, live.running, live.mode, reason, facts.journey)
}

internal fun Context.cleanupStatusText(status: CleanupStatus): String = getString(when (status) {
    CleanupStatus.IDLE -> R.string.auto_cleanup_idle
    CleanupStatus.RUNNING -> R.string.auto_cleanup_running
    CleanupStatus.BINDING -> R.string.auto_cleanup_binding
    CleanupStatus.REVIEW -> R.string.auto_cleanup_review
    CleanupStatus.ACCOUNT -> R.string.auto_cleanup_account
    CleanupStatus.ACCESS -> R.string.auto_cleanup_access
    CleanupStatus.LOCKED -> R.string.auto_cleanup_locked
    CleanupStatus.UNAVAILABLE -> R.string.auto_cleanup_unavailable
    CleanupStatus.STOPPED -> if (PhotosCleanup(this).enabled) R.string.auto_cleanup_stopped else R.string.auto_cleanup_setup_stopped
    CleanupStatus.FAILED -> R.string.auto_cleanup_failed
    CleanupStatus.WAITING_ACCESS -> R.string.auto_cleanup_waiting_access
})
