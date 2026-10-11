package app.backupduck

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/** Short system templates; no fixed-height/custom RemoteViews or fake progress. */
internal object ReceiverNotifications {
    data class Content(val title: String, val body: String)

    fun content(context: Context, state: ReceiverSnapshot): Content {
        val (title, body) = when {
            state.thermalHeld -> R.string.notification_cooling to R.string.notification_cooling_body
            ReceiverPreferences.paused(context) -> R.string.notification_paused to R.string.notification_paused_body
            state.phase == "starting" -> R.string.notification_starting to R.string.notification_starting_body
            state.phase == "waiting" -> R.string.notification_recovering to R.string.notification_recovering_body
            state.phase != "ready" -> R.string.notification_stopped to R.string.receiver_resume_notice
            state.error in listOf("processing_low_space", "low_space", "capacity") ->
                R.string.notification_space to R.string.notification_space_body
            state.recent.any { it.receipt == "receiving" } ->
                R.string.notification_receiving to R.string.notification_receiving_body
            state.processingName != null || state.received > state.published + state.failed ->
                R.string.notification_saving to R.string.notification_saving_body
            state.failed > 0 -> R.string.notification_attention to R.string.notification_attention_body
            else -> R.string.notification_ready to R.string.notification_ready_body
        }
        return Content(context.getString(title), context.getString(body))
    }

    fun build(context: Context, state: ReceiverSnapshot): Notification {
        val content = content(context, state)
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(context, "receiver")
            .setContentTitle(content.title)
            .setContentText(content.body)
            // Expanded shade gets precisely this short text, rather than an
            // indeterminate progress area or an application-sized surface.
            .setStyle(NotificationCompat.BigTextStyle().bigText(content.body))
            .setSmallIcon(R.drawable.ic_notification_duck)
            .setContentIntent(open)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setShowWhen(false).setOnlyAlertOnce(true).setOngoing(true)
            .build()
    }

    fun resume(context: Context): Notification {
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(context, "receiver")
            .setSmallIcon(R.drawable.ic_notification_duck)
            .setContentTitle(context.getString(R.string.notification_stopped))
            .setContentText(context.getString(R.string.receiver_resume_notice))
            .setContentIntent(open).setAutoCancel(true).build()
    }
}
