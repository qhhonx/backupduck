package app.backupduck

/** I6: the tap target follows the state actually described by the system template. */
internal enum class ReceiverNotificationRoute(val value: String) {
    RECEIVE("receive"), NEEDS_YOU("photos-needs-you"), STORAGE("storage");

    companion object {
        const val EXTRA = "notification_destination"
        fun parse(value: String?) = entries.firstOrNull { it.value == value }
    }
}

internal enum class ReceiverNotificationState(val title: Int, val body: Int,
    val route: ReceiverNotificationRoute = ReceiverNotificationRoute.RECEIVE) {
    COOLING(R.string.notification_cooling, R.string.notification_cooling_body),
    PAUSED(R.string.notification_paused, R.string.notification_paused_body),
    STARTING(R.string.notification_starting, R.string.notification_starting_body),
    RECOVERING(R.string.notification_recovering, R.string.notification_recovering_body),
    STOPPED(R.string.notification_stopped, R.string.receiver_resume_notice),
    SPACE(R.string.notification_space, R.string.notification_space_body, ReceiverNotificationRoute.STORAGE),
    RECEIVING(R.string.notification_receiving, R.string.notification_receiving_body),
    SAVING(R.string.notification_saving, R.string.notification_saving_body),
    ATTENTION(R.string.notification_attention, R.string.notification_attention_body, ReceiverNotificationRoute.NEEDS_YOU),
    READY(R.string.notification_ready, R.string.notification_ready_body)
}

/** Preserve notification content priority, including Android's ongoing service states. */
internal fun receiverNotificationState(state: ReceiverSnapshot, paused: Boolean): ReceiverNotificationState = when {
    state.thermalHeld -> ReceiverNotificationState.COOLING
    paused -> ReceiverNotificationState.PAUSED
    state.phase == "starting" -> ReceiverNotificationState.STARTING
    state.phase == "waiting" -> ReceiverNotificationState.RECOVERING
    state.phase != "ready" -> ReceiverNotificationState.STOPPED
    state.error in listOf("processing_low_space", "low_space", "capacity") -> ReceiverNotificationState.SPACE
    state.recent.any { it.receipt == "receiving" } -> ReceiverNotificationState.RECEIVING
    state.processingName != null || state.received > state.published + state.failed -> ReceiverNotificationState.SAVING
    state.failed > 0 -> ReceiverNotificationState.ATTENTION
    else -> ReceiverNotificationState.READY
}
