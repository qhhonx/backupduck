package app.backupduck
import org.junit.Assert.assertEquals
import org.junit.Test
class CleanupPresentationTest {
    private fun state(reason: String, pending: Boolean = false, running: Boolean = false, mode: String = "cleanup",
        access: Boolean = true, enabled: Boolean = true, account: Boolean = true, journey: String = "") =
        cleanupStatus(enabled, account, access, pending, running, mode, reason, journey)
    @Test fun liveWorkOwnsTheRowAndProvidesStop() {
        listOf("opening", "waking", "unlocked", "finding_home", "opening_menu", "opening_cleanup", "checking_result", "confirming", "pending", "returning").forEach {
            assertEquals(it, CleanupStatus.RUNNING, state(it, pending = true, running = true))
            assertEquals(it, CleanupStatus.BINDING, state(it, running = true, mode = "bind"))
        }
    }
    @Test fun uncertainWorkCannotBeHiddenByDisabledPolicyOrMissingAccess() {
        listOf("pending", "unrecognized", "manual_review_required", "return_home_failed", "expired").forEach {
            assertEquals(it, CleanupStatus.REVIEW, state(it, enabled = false, access = false))
        }
        listOf("stopped", "interrupted", "disconnected", "operation_failed", "account_changed").forEach {
            assertEquals(it, CleanupStatus.REVIEW, state(it, pending = true))
        }
    }
    @Test fun accountAccessDeviceAndUnexpectedFailuresRemainActionable() {
        listOf("account_unavailable", "account_changed").forEach { assertEquals(CleanupStatus.ACCOUNT, state(it)) }
        listOf("locked", "unlock_failed").forEach { assertEquals(CleanupStatus.LOCKED, state(it)) }
        assertEquals(CleanupStatus.UNAVAILABLE, state("unavailable"))
        assertEquals(CleanupStatus.ACCESS, state("disconnected"))
        assertEquals(CleanupStatus.ACCESS, state("bound", access = false))
        assertEquals(CleanupStatus.ACCOUNT, state("ready", account = false))
        listOf("stopped", "interrupted", "setup_cancelled").forEach { assertEquals(CleanupStatus.STOPPED, state(it)) }
        listOf("operation_failed", "storage_io").forEach { assertEquals(CleanupStatus.FAILED, state(it)) }
    }
    @Test fun resultAndReviewAreCalmButProbeIsSeparate() {
        listOf("idle", "ready", "bound", "reviewed", "completed", "nothing_to_free").forEach { assertEquals(CleanupStatus.IDLE, state(it)) }
        assertEquals(CleanupStatus.IDLE, state("ready", running = true, mode = "probe"))
        assertEquals(CleanupStatus.IDLE, state("ready", account = false, enabled = false))
        assertEquals(CleanupStatus.WAITING_ACCESS, state("ready", journey = "access"))
    }
    @Test fun requiredRecoveryPropagatesUntilResolved() {
        listOf("account_changed", "account_unavailable", "access_required", "disconnected", "pending",
            "manual_review_required", "unrecognized", "return_home_failed", "expired", "operation_failed", "unavailable").forEach {
            assertEquals(it, true, state(it).needsAttention)
        }
        assertEquals(true, state("ready", account = false).needsAttention)
        assertEquals(true, state("ready", access = false).needsAttention)
        listOf("ready", "bound", "reviewed", "completed", "nothing_to_free", "setup_cancelled", "stopped").forEach {
            assertEquals(it, false, state(it).needsAttention)
        }
        assertEquals(false, state("opening", running = true).needsAttention)
        assertEquals(false, state("ready", enabled = false, account = false, access = false).needsAttention)
    }
}
