package app.backupduck

import org.junit.Assert.assertEquals
import org.junit.Test

class ReceiverHubStateTest {
    private fun state(snapshot: ReceiverSnapshot = ReceiverSnapshot(phase = "ready"), enabled: Boolean = true, paused: Boolean = false,
        pending: Boolean = false, senders: Boolean = true, saved: Int = 0) = receiverHubState(enabled, paused, pending, snapshot, senders, saved)

    @Test fun oneStatePerSituationInPriorityOrder() {
        assertEquals(ReceiverHubState.STOPPED, state(enabled = false, paused = true))
        assertEquals(ReceiverHubState.STARTING, state(pending = true))
        assertEquals(ReceiverHubState.PAUSED, state(ReceiverSnapshot(phase = "waiting", error = "low_space"), paused = true))
        assertEquals(ReceiverHubState.SPACE_FULL, state(ReceiverSnapshot(phase = "waiting", error = "processing_low_space", thermalHeld = true)))
        assertEquals(ReceiverHubState.TOO_HOT, state(ReceiverSnapshot(phase = "ready", thermalHeld = true)))
        assertEquals(ReceiverHubState.NO_WIFI, state(ReceiverSnapshot(phase = "waiting", error = "wifi_required")))
        assertEquals(ReceiverHubState.TROUBLE, state(ReceiverSnapshot(phase = "waiting", error = "receiver_port_in_use")))
        assertEquals(ReceiverHubState.NO_DEVICE, state(senders = false))
    }

    @Test fun receivingUntilEveryItemSettles() {
        assertEquals(ReceiverHubState.RECEIVING, state(ReceiverSnapshot(phase = "ready", total = 10, published = 8, failed = 1)))
        assertEquals(ReceiverHubState.CAUGHT_UP, state(ReceiverSnapshot(phase = "ready", total = 10, published = 9, failed = 1)))
        assertEquals(ReceiverHubState.CAUGHT_UP, state(saved = 4))
        assertEquals(ReceiverHubState.WAITING, state())
    }
}
