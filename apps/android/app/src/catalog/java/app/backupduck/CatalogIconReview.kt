package app.backupduck

import android.content.res.ColorStateList
import android.view.Gravity
import android.widget.ImageView
import android.widget.LinearLayout
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.R as M

/** Opt-in native specimens; no receiver operation or production entry point. */
internal object CatalogIconReview {
    var pending: String? = null
    @Volatile var fault: String? = null

    /** Fixed synthetic failures exercise the shared glyph in its actual task context. */
    fun install() {
        val original = NativeBridge.transport
        NativeBridge.transport = { request ->
            val query = org.json.JSONObject(request)
            val fail = when (fault) {
                "photos" -> query.optString("op") in setOf("receiver_history", "receiver_history_latest")
                "devices" -> query.optString("op") == "device_status"
                "rename" -> query.optString("op") == "device_status" && query.has("name")
                "storage" -> query.optString("op") == "set_receiver_relay"
                "sender" -> query.optString("op") == "set_sender_enabled"
                "retry" -> query.optString("op") == "retry_processing"
                else -> false
            }
            if (fail) org.json.JSONObject().put("ok", false).put("error", "catalog_icon_failure").toString()
            else original(request)
        }
    }

    fun attach(activity: MainActivity) {
        val review = pending ?: return
        pending = null
        activity.window.decorView.post {
            if (activity.isFinishing) return@post
            when (review) {
                "failure" -> activity.duckConfirm(R.string.duck_operation_failed,
                    R.string.devices_stop_note, R.string.duck_retry) { it.dismiss() }
                    .showFailure(R.string.devices_save_failed)
                "sheet-failure" -> activity.showActionFailure(R.string.duck_access_change_failed) {}
                "rename" -> DevicePanels(activity).rename()
                "vectors" -> vectors(activity)
            }
        }
    }

    private fun vectors(activity: MainActivity) = with(activity) {
        val body = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val inset = token(R.dimen.duck_space_large)
            setPadding(inset, 0, inset, 0)
        }
        body.addView(lookText("Default / accent override", M.style.TextAppearance_Material3_BodyMedium))
        for ((name, icon) in listOf("ic_alert" to R.drawable.ic_alert, "ic_check" to R.drawable.ic_check,
            "ic_cloud" to R.drawable.ic_cloud, "ic_more" to R.drawable.ic_more, "ic_plus" to R.drawable.ic_plus,
            "ic_qr" to R.drawable.ic_qr, "ic_scan" to R.drawable.ic_scan)) {
            val row = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
            row.addView(lookText(name, M.style.TextAppearance_Material3_BodyLarge), LinearLayout.LayoutParams(0, -2, 1f))
            for (override in listOf(false, true)) {
                row.addView(ImageView(this).apply {
                    contentDescription = "$name ${if (override) "accent" else "default"}"
                    setImageResource(icon)
                    if (override) imageTintList = ColorStateList.valueOf(getColor(R.color.duck_role_accent))
                }, LinearLayout.LayoutParams(dp(24), dp(24)).apply { marginStart = token(R.dimen.duck_space_large) })
            }
            body.addView(row, LinearLayout.LayoutParams(-1, dp(48)))
        }
        MaterialAlertDialogBuilder(this).setTitle("Vector colours").setView(body)
            .setPositiveButton(android.R.string.ok, null).show()
    }
}
