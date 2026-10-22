package app.backupduck

import android.content.Context
import android.content.DialogInterface
import android.view.View
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AlertDialog
import com.google.android.material.dialog.MaterialAlertDialogBuilder

/** Failures stay in their source; only their glyph carries the state color. */
internal fun Context.duckError(message:String):View = duckMessageRow(getString(R.string.duck_operation_failed), message,
    R.drawable.ic_alert, R.color.duck_state_failure, R.color.duck_role_primary_text).apply {
    visibility = View.GONE
    setPadding(dp(12),dp(12),dp(12),dp(12))
    accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
}
internal fun Context.duckFailure(parent:LinearLayout,message:String):View = duckError(message).also {
    parent.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(12);bottomMargin=dp(12)})
}

/** Material owns the title, message, frame and trailing Text actions. */
internal class DuckConfirmation(private val activity:AppCompatActivity,title:Int,message:Int,positive:Int,danger:Boolean=false,
    notice:Int?=null,private val busyNotice:Int?=null,messageText:String?=null,confirmed:(DuckConfirmation)->Unit) : DialogInterface {
    private val explanation = listOfNotNull(messageText ?: activity.getString(message), notice?.let(activity::getString)).joinToString("\n\n")
    private val dialog = MaterialAlertDialogBuilder(activity)
        .setTitle(title).setMessage(explanation)
        .setNegativeButton(R.string.device_cancel, null)
        .setPositiveButton(positive, null).create().also { activity.trackNotificationWindow(it) }
    val confirm get() = dialog.getButton(AlertDialog.BUTTON_POSITIVE)
    val window get() = dialog.window
    val isShowing get() = dialog.isShowing
    private val idleLabel = activity.getString(positive)
    init { dialog.setOnShowListener {
        dialog.findViewById<android.widget.TextView>(android.R.id.message)?.balanceLines()
        confirm.setOnClickListener { confirmed(this) }
    } }
    fun show() = dialog.show()
    override fun dismiss() = dialog.dismiss()
    override fun cancel() = dialog.cancel()
    fun setOnDismissListener(listener: DialogInterface.OnDismissListener?) = dialog.setOnDismissListener(listener)
    fun busy(value:Boolean) {
        confirm.isEnabled = !value
        dialog.getButton(AlertDialog.BUTTON_NEGATIVE).isEnabled = !value
        dialog.setCancelable(!value)
        dialog.setMessage(if(value && busyNotice != null) activity.getString(busyNotice) else explanation)
        confirm.text = idleLabel
    }
    fun showFailure(message:Int=R.string.duck_access_change_failed) {
        dialog.setMessage(explanation + "\n\n" + activity.getString(message))
        dialog.setIcon(R.drawable.ic_alert)
    }
}
internal fun AppCompatActivity.duckConfirm(title:Int,message:Int,positive:Int,danger:Boolean=false,notice:Int?=null,busyNotice:Int?=null,messageText:String?=null,
    confirmed:(DuckConfirmation)->Unit):DuckConfirmation = DuckConfirmation(this,title,message,positive,danger,notice,busyNotice,messageText,confirmed).also {it.show()}

/** A one-value edit keeps validation and asynchronous failures inside a native dialog. */
internal class DuckEditDialog(context: Context, title: String, label: String, value: String = "", numeric: Boolean = false, maxLength: Int? = null) : DialogInterface {
    val field = DuckField(context, label, value, numeric, maxLength)
    val body = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        val padding = context.token(R.dimen.duck_space_large)
        setPadding(padding, context.token(R.dimen.duck_space_small), padding, 0)
        addView(field.view, LinearLayout.LayoutParams(-1, -2))
    }
    private val dialog = MaterialAlertDialogBuilder(context).setTitle(title).setView(body)
        .setNegativeButton(R.string.device_cancel, null).setPositiveButton(R.string.device_save, null).create()
        .also { context.trackNotificationWindow(it) }
    val save get() = dialog.getButton(AlertDialog.BUTTON_POSITIVE)
    val cancel get() = dialog.getButton(AlertDialog.BUTTON_NEGATIVE)
    val window get() = dialog.window
    val isShowing get() = dialog.isShowing
    fun show() = dialog.show()
    fun hide() = dialog.hide()
    override fun dismiss() = dialog.dismiss()
    override fun cancel() = dialog.cancel()
    fun setOnDismissListener(listener: DialogInterface.OnDismissListener?) = dialog.setOnDismissListener(listener)
    fun busy(value: Boolean) {
        save.isEnabled = !value; cancel.isEnabled = !value; field.input.isEnabled = !value
        dialog.setCancelable(!value)
    }
}
