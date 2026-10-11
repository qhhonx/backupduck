package app.backupduck

import org.junit.Assert.*
import org.junit.Test

class ReceiverStartupPresentationTest {
    @Test fun backgroundRetriesKeepRecoveryAndCountsUntilReady() {
        val failed = ReceiverSnapshot(phase = "waiting", error = "wifi_required",
            total = 18, received = 17, published = 16, manualPaused = true)
        var next = failed
        repeat(12) { next = next.startingIfRequested(false) }
        assertSame(failed, next)
        assertEquals("wifi_required", next.error)
        assertEquals(18, next.total)
        assertTrue(next.manualPaused)
        val requested = next.startingIfRequested(true)
        assertEquals("starting", requested.phase)
        assertNull(requested.error)
        assertEquals(17, requested.received)
        assertTrue(requested.manualPaused)
    }
}
