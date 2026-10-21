package app.backupduck

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/** Short system templates; no fixed-height/custom RemoteViews or fake progress. */
internal object ReceiverNotifications {
    data class Content(val title: String, val body: String)

    fun content(context: Context, state: ReceiverSnapshot): Content =
        content(context, receiverNotificationState(state, ReceiverPreferences.paused(context)))

    private fun content(context: Context, state: ReceiverNotificationState) =
        Content(context.getString(state.title), context.getString(state.body))

    private fun open(context: Context, route: ReceiverNotificationRoute, requestCode: Int): PendingIntent =
        PendingIntent.getActivity(context, requestCode, Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(ReceiverNotificationRoute.EXTRA, route.value),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun build(context: Context, state: ReceiverSnapshot): Notification {
        val presentation = receiverNotificationState(state, ReceiverPreferences.paused(context))
        val content = content(context, presentation)
        val open = open(context, presentation.route, 1)
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
        val open = open(context, ReceiverNotificationRoute.RECEIVE, 2)
        return NotificationCompat.Builder(context, "receiver")
            .setSmallIcon(R.drawable.ic_notification_duck)
            .setContentTitle(context.getString(R.string.notification_stopped))
            .setContentText(context.getString(R.string.receiver_resume_notice))
            .setContentIntent(open).setAutoCancel(true).build()
    }
}
