package app.backupduck

import android.app.Dialog
import android.content.Context
import android.content.ContextWrapper
import java.lang.ref.WeakReference

/** I6: a notification's destination must not remain covered by an older modal window. */
internal class ReceiverNotificationWindows {
    private val windows = mutableListOf<WeakReference<Dialog>>()

    fun track(dialog: Dialog) {
        windows.removeAll { it.get() == null }
        windows += WeakReference(dialog)
    }

    fun dismiss() {
        // Child dismissal can show its hidden parent; dismiss parents last.
        windows.mapNotNull { it.get() }.asReversed().forEach { it.dismiss() }
    }
}

internal fun Context.trackNotificationWindow(dialog: Dialog) {
    var owner = this
    while (owner is ContextWrapper) {
        if (owner is MainActivity) {
            owner.notificationWindows.track(dialog)
            return
        }
        val base = owner.baseContext
        if (base === owner) return
        owner = base
    }
}
