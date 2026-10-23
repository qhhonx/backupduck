package app.backupduck

/** One projection for Storage and the ordinary cleanup page; operation ownership stays in the service. */
internal enum class CleanupStatus { IDLE, RUNNING, REVIEW, ACCOUNT, ACCESS, LOCKED, UNAVAILABLE, STOPPED, FAILED, WAITING_ACCESS, BINDING }
internal fun cleanupStatus(enabled: Boolean, account: Boolean, access: Boolean, pending: Boolean,
    running: Boolean, mode: String, reason: String, journey: String = ""): CleanupStatus = when {
    journey == "access" -> CleanupStatus.WAITING_ACCESS
    running && mode == "bind" -> CleanupStatus.BINDING
    running && mode == "cleanup" -> CleanupStatus.RUNNING
    pending || reason in setOf("pending", "unrecognized", "manual_review_required", "return_home_failed", "expired") -> CleanupStatus.REVIEW
    reason in setOf("locked", "unlock_failed") -> CleanupStatus.LOCKED
    reason == "unavailable" -> CleanupStatus.UNAVAILABLE
    reason in setOf("account_changed", "account_unavailable") -> CleanupStatus.ACCOUNT
    reason in setOf("access_required", "disconnected") || (enabled && !access) -> CleanupStatus.ACCESS
    reason in setOf("stopped", "interrupted", "setup_cancelled") -> CleanupStatus.STOPPED
    reason !in setOf("idle", "ready", "bound", "reviewed", "completed", "nothing_to_free") -> CleanupStatus.FAILED
    enabled && !account -> CleanupStatus.ACCOUNT
    else -> CleanupStatus.IDLE
}

/** Required recovery is independent of whether the feature introduction was seen. */
internal val CleanupStatus.needsAttention: Boolean get() = this in setOf(
    CleanupStatus.ACCOUNT, CleanupStatus.ACCESS, CleanupStatus.REVIEW, CleanupStatus.FAILED, CleanupStatus.UNAVAILABLE)
