package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import com.google.android.material.textfield.TextInputEditText
import org.json.JSONObject

/** Real JNI access operations through native controls, only in an isolated emulator. */
internal fun Instrumentation.checkDashboardCodeUI(): String {
    check(targetContext.packageName.endsWith(".validation"))
    check(android.os.Build.MODEL.contains("sdk_gphone")||android.os.Build.FINGERPRINT.contains("generic"))
    ReceiverPreferences.setEnabled(targetContext, false)
    val root = "${targetContext.filesDir}/receiver"
    fun access(code: String? = null): JSONObject = NativeBridge.request(JSONObject().put("op", "dashboard_access").put("root", root).put("code", code)) as JSONObject
    fun views(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {views(v.getChildAt(it))} else emptyList()
    val original = access().getString("code")
    uiAutomation.executeShellCommand("input keyevent 224").close()
    uiAutomation.executeShellCommand("wm dismiss-keyguard").close()
    val activity = startActivitySync(Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    var sheet:DuckSheet?=null
    var confirmation:DuckConfirmation?=null
    try {
        runOnMainSync {sheet=DashboardAccessUI(activity).code()}
        waitForIdleSync();Thread.sleep(400)
        runOnMainSync {
            val form=checkNotNull(sheet)
            views(form.body).filterIsInstance<TextInputEditText>().single().setText("0123456789")
            form.footer.getChildAt(0).performClick()
        }
        var saved=false
        repeat(50) {if(!saved) {saved=access().getString("code")=="0123456789";Thread.sleep(100)}}
        check(saved) {"custom_dashboard_code_not_saved"}
        Thread.sleep(400)
        runOnMainSync {confirmation=DashboardAccessUI(activity).revoke();confirmation!!.confirm.performClick()}
        Thread.sleep(600);waitForIdleSync()
        check(!confirmation!!.isShowing) {"revoke_did_not_complete"}
        check(access().getString("code")=="0123456789") {"revoke_changed_access_code"}
        runOnMainSync {confirmation=DashboardAccessUI(activity).reset();confirmation!!.confirm.performClick()}
        var changed=false
        repeat(50) {if(!changed) {val next=access().getString("code");changed=next!="0123456789"&&next.matches(Regex("[0-9]{10}"));Thread.sleep(100)}}
        check(changed) {"reset_did_not_change_access_code"}
        check(receiverProblem(ReceiverSnapshot(error="receiver_port_in_use"))?.message==R.string.recovery_port)
        return "PASS: real native access-code save, login revoke preserves code, random reset; original code restored; specific port-conflict recovery"
    } finally {access(original);runOnMainSync {sheet?.dismiss();confirmation?.dismiss();activity.finish()}}
}
