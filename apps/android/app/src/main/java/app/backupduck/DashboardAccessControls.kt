package app.backupduck

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.text.InputType
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Native credential edits share the existing atomic browser-access operation. */
internal class DashboardAccessUI(private val activity:AppCompatActivity,
    private val changed:(String)->Unit={},
    private val request:suspend (JSONObject)->JSONObject = {withContext(Dispatchers.IO) {NativeBridge.request(it) as JSONObject}}) {
    private val root get()="${activity.filesDir}/receiver"
    fun code():DuckEditDialog = with(activity) {
        val dialog = DuckEditDialog(this, getString(R.string.dashboard_manage_code), getString(R.string.duck_new_access_code), numeric = true, maxLength = 10)
        val review=packageName.endsWith(".catalog")||packageName.endsWith(".validation")
        val field=dialog.field.box
        val edit=dialog.field.input.apply {
            inputType=InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
            transformationMethod=AlwaysMaskedPassword()
        }
        dialog.body.addView(duckParagraph(getString(R.string.browser_change_note)))
        dialog.body.addView(duckParagraph(getString(R.string.browser_preserved_note)))
        val problem=duckFailure(dialog.body,getString(R.string.duck_code_save_failed))
        val reset=duckLink(getString(R.string.duck_reset_random_code)) {
            dialog.hide()
            var changed=false
            reset(onSuccess={changed=true;dialog.dismiss()}).setOnDismissListener {
                if(!changed&&!isFinishing&&!isDestroyed) dialog.show()
            }
        }
        dialog.body.addView(reset)
        var saving=false
        dialog.show()
        if(!review) dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        dialog.save.setOnClickListener {
            if(!saving) {
                val value=edit.text?.toString().orEmpty();field.error=null
                if(!value.matches(Regex("[0-9]{10}"))) {field.error=getString(R.string.dashboard_custom_hint);edit.requestFocus()}
                else {
                    saving=true;dialog.busy(true);reset.isEnabled=false;problem.visibility=View.GONE
                    lifecycleScope.launch {
                        val result=runCatching {request(JSONObject().put("op","dashboard_access").put("root",root).put("code",value))}
                        saving=false;dialog.busy(false);reset.isEnabled=true
                        if(!dialog.isShowing)return@launch
                        result.onSuccess {dialog.dismiss();changed(getString(R.string.browser_code_changed))}
                            .onFailure {problem.visibility=View.VISIBLE}
                    }
                }
            }
        }
        dialog
    }
    fun reset(onSuccess:()->Unit={}) = with(activity) {duckConfirm(R.string.dashboard_reset_question,R.string.browser_reset_note,R.string.dashboard_reset_code,true,notice=R.string.browser_preserved_note,busyNotice=R.string.duck_resetting) {dialog->change(dialog,reset=true,onSuccess=onSuccess)}}
    fun revoke() = with(activity) {duckConfirm(R.string.dashboard_revoke_question,R.string.browser_signout_note,R.string.dashboard_revoke,true,notice=R.string.browser_preserved_note,busyNotice=R.string.duck_revoking) {dialog->change(dialog,revoke=true)}}
    private fun change(dialog:DuckConfirmation,reset:Boolean=false,revoke:Boolean=false,onSuccess:()->Unit={}) = with(activity) {
        dialog.busy(true)
        lifecycleScope.launch {
            val result=runCatching {request(JSONObject().put("op","dashboard_access").put("root",root).put("reset",reset).put("revoke",revoke))}
            dialog.busy(false)
            if(!dialog.isShowing)return@launch
            result.onSuccess {onSuccess();dialog.dismiss();changed(getString(if(revoke)R.string.browser_signed_out else R.string.browser_code_changed))}
                .onFailure {dialog.showFailure()}
        }
    }

}
internal fun MainActivity.manageDashboardCode() {DashboardAccessUI(this).code()}
internal fun MainActivity.revokeDashboardLogins() {DashboardAccessUI(this).revoke()}

/** PasswordTransformationMethod normally echoes the last digit briefly; review screenshots must never do that. */
internal class AlwaysMaskedPassword:android.text.method.PasswordTransformationMethod() {
    override fun getTransformation(source:CharSequence,view:View):CharSequence = object:CharSequence {
        override val length get()=source.length
        override fun get(index:Int):Char='•'
        override fun subSequence(startIndex:Int,endIndex:Int):CharSequence="•".repeat(endIndex-startIndex)
        override fun toString()="•".repeat(length)
    }
}
