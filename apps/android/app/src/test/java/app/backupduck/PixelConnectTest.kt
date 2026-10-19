package app.backupduck

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PixelConnectTest {
    private fun peer(id: String, seen: Long, enabled: Boolean = true, kind: String? = "iPhone") = DevicePeer(id, "Device $id", kind, seen, enabled)

    @Test fun theCodeShowsOnceTheReceiverIsReady() {
        assertEquals(CodePhase.CODE, codePhase("ready", null, hasCode = true, waitedMs = 0))
        assertEquals(CodePhase.GETTING_READY, codePhase("ready", null, hasCode = false, waitedMs = 1_000))
        assertEquals(CodePhase.GETTING_READY, codePhase("starting", null, hasCode = false, waitedMs = 5_000))
    }

    @Test fun startingFailsOnAnErrorOrAfterAMinute() {
        assertEquals(CodePhase.FAILED, codePhase("waiting", "wifi_required", hasCode = false, waitedMs = 1_000))
        assertEquals(CodePhase.FAILED, codePhase("starting", null, hasCode = false, waitedMs = CODE_READY_TIMEOUT_MS + 1))
        // A ready receiver with its code wins over a slow start.
        assertEquals(CodePhase.CODE, codePhase("ready", null, hasCode = true, waitedMs = CODE_READY_TIMEOUT_MS + 1))
    }

    @Test fun onlyADeviceNotSeenBeforeCountsAsConnected() {
        val before = setOf("a", "b")
        assertNull(newlyConnected(before, listOf(peer("a", 200), peer("b", 300))))
        assertEquals("c", newlyConnected(before, listOf(peer("a", 200), peer("c", 100)))?.id)
        assertEquals("a", newlyConnected(emptySet(), listOf(peer("a", 1)))?.id)
    }

    @Test fun devicesAreGroupedNewestFirstWithStoppedApart() {
        val groups = deviceGroups(listOf(peer("old", 100), peer("stopped", 500, enabled = false), peer("new", 900), peer("new", 300)))
        assertEquals(listOf("new", "old"), groups.sending.map { it.id })
        assertEquals(900L, groups.sending.first().lastSeenSec)
        assertEquals(listOf("stopped"), groups.stopped.map { it.id })
        assertTrue(deviceGroups(emptyList()).let { it.sending.isEmpty() && it.stopped.isEmpty() })
    }

    @Test fun computersAndPhonesGetTheirMark() {
        assertTrue(peer("m", 1, kind = "Mac").computer)
        assertFalse(peer("i", 1, kind = "iPad").computer)
        assertFalse(peer("u", 1, kind = null).computer)
    }

    @Test fun onlyAMacCodeIsAccepted() {
        assertEquals(MacScan.CANCELLED, macScan(null))
        assertEquals(MacScan.UNREADABLE, macScan("https://example.com"))
        assertEquals(MacScan.UNREADABLE, macScan("{\"version\":2,\"receiver_id\":\"x\"}"))
        assertEquals(MacScan.CODE, macScan("{\"kind\":\"backupduck_desktop_pairing\",\"connection\":{}}"))
        assertEquals(MacScan.UNREADABLE, macScan("\"backupduck_desktop_pairing\"" + " ".repeat(40_000)))
    }
}
