package app.backupduck

import org.junit.Assert.*
import org.junit.Test

class ReceiverNotificationRouteTest {
    private fun presentation(state: ReceiverSnapshot, paused: Boolean = false) = receiverNotificationState(state, paused)

    @Test fun failedPhotosOpenNeedsYou() {
        val state = presentation(ReceiverSnapshot(phase = "ready", received = 8, published = 6, failed = 2))
        assertEquals(ReceiverNotificationState.ATTENTION, state)
        assertEquals(R.string.notification_attention, state.title)
        assertEquals(R.string.notification_attention_body, state.body)
        assertEquals(ReceiverNotificationRoute.NEEDS_YOU, state.route)
    }

    @Test fun everySpaceProblemOpensStorage() {
        listOf("processing_low_space", "low_space", "capacity").forEach { error ->
            val state = presentation(ReceiverSnapshot(phase = "ready", error = error, failed = 2))
            assertEquals(ReceiverNotificationState.SPACE, state)
            assertEquals(ReceiverNotificationRoute.STORAGE, state.route)
        }
    }

    @Test fun foregroundTransferAndSavingOpenReceive() {
        val recent = RecentTransfer("id", "photo.jpg", "photo", 100, 40, "receiving", "pending")
        val receiving = presentation(ReceiverSnapshot(phase = "ready", recent = listOf(recent), failed = 1))
        assertEquals(ReceiverNotificationState.RECEIVING, receiving)
        assertEquals(ReceiverNotificationRoute.RECEIVE, receiving.route)
        listOf(ReceiverSnapshot(phase = "ready", processingName = "photo.jpg", failed = 1),
            ReceiverSnapshot(phase = "ready", received = 2, published = 0, failed = 1)).forEach {
            val saving = presentation(it)
            assertEquals(ReceiverNotificationState.SAVING, saving)
            assertEquals(ReceiverNotificationRoute.RECEIVE, saving.route)
        }
    }

    @Test fun lifecycleAndConnectionProblemsOpenReceive() {
        listOf("idle", "starting", "waiting", "error", "ready").forEach { phase ->
            assertEquals(ReceiverNotificationRoute.RECEIVE,
                presentation(ReceiverSnapshot(phase = phase, error = "wifi_required")).route)
        }
        assertEquals(ReceiverNotificationRoute.RECEIVE, ReceiverNotificationState.STOPPED.route)
        assertEquals(ReceiverNotificationRoute.RECEIVE, presentation(ReceiverSnapshot(thermalHeld = true)).route)
        assertEquals(ReceiverNotificationRoute.RECEIVE, presentation(ReceiverSnapshot(), paused = true).route)
    }

    @Test fun destinationKeepsExistingContentPriority() {
        val state = ReceiverSnapshot(phase = "ready", failed = 3, error = "capacity")
        assertEquals(ReceiverNotificationState.COOLING, presentation(state.copy(thermalHeld = true), paused = true))
        assertEquals(ReceiverNotificationState.PAUSED, presentation(state, paused = true))
        assertEquals(ReceiverNotificationState.STARTING, presentation(state.copy(phase = "starting")))
        assertEquals(ReceiverNotificationState.RECOVERING, presentation(state.copy(phase = "waiting")))
        assertEquals(ReceiverNotificationState.STOPPED, presentation(state.copy(phase = "idle")))
        assertEquals(ReceiverNotificationState.SPACE, presentation(state))
        assertEquals(ReceiverNotificationState.READY, presentation(ReceiverSnapshot(phase = "ready")))
    }

    @Test fun intentValuesRoundTripAndUnknownValuesDoNotNavigate() {
        ReceiverNotificationRoute.entries.forEach { assertEquals(it, ReceiverNotificationRoute.parse(it.value)) }
        assertNull(ReceiverNotificationRoute.parse(null))
        assertNull(ReceiverNotificationRoute.parse(""))
        assertNull(ReceiverNotificationRoute.parse("future-destination"))
    }
}
