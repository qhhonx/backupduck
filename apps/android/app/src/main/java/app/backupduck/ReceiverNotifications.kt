package app.backupduck

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/** Short system templates; no fixed-height/custom RemoteViews or fake progress. */
internal object ReceiverNotifications {
    fun text(context: Context, state: ReceiverSnapshot): String = context.getString(when {
        state.thermalHeld -> R.string.receiver_thermal_paused
        ReceiverPreferences.paused(context) -> R.string.duck_reception_paused
        state.phase == "starting" -> R.string.receiver_starting
        state.phase == "waiting" -> R.string.receiver_waiting
        state.phase != "ready" -> R.string.duck_stopped
        state.error in listOf("processing_low_space", "low_space", "capacity") -> R.string.receiver_notification_space
        state.recent.any { it.receipt == "receiving" } -> R.string.receiver_notification
        state.processingName != null || state.received > state.published + state.failed -> R.string.receiver_notification_processing
        else -> R.string.duck_wait_receive
    })

    fun build(context: Context, state: ReceiverSnapshot): Notification {
        val text = text(context, state)
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(context, "receiver")
            .setContentTitle(context.getString(R.string.app_name))
            .setContentText(text)
            // Expanded shade gets precisely this short text, rather than an
            // indeterminate progress area or an application-sized surface.
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setSmallIcon(R.drawable.ic_receiver)
            .setContentIntent(open)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setShowWhen(false).setOnlyAlertOnce(true).setOngoing(true)
            .build()
    }
}
