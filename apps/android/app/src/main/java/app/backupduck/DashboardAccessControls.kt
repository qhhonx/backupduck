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

/** One native implementation of the v1.2 browser flow, reusing RC.3 operations. */
internal class DashboardAccessUI(private val activity:AppCompatActivity,
    private val request:suspend (JSONObject)->JSONObject = {withContext(Dispatchers.IO) {NativeBridge.request(it) as JSONObject}}) {
    private val root get()="${activity.filesDir}/receiver"
    fun access(onDismiss:()->Unit={}):DuckSheet = with(activity) {
        val sheet=DuckSheet(this,getString(R.string.duck_browser_access))
        val review=packageName=="app.backupduck.validation"
        if(!review) sheet.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val address=duckParagraph(getString(R.string.history_loading)).apply {setTextIsSelectable(true)}
        val code=duckParagraph("")
        var secret=""
        var exposed=false
        fun renderCode() {code.text=if(exposed||!review) secret else if(secret.isEmpty()) "" else "••••••••••"}
        sheet.body.addView(duckParagraph(getString(R.string.duck_browser_access_intro)),LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(8);bottomMargin=dp(16)})
        val group=duckGroup(sheet.body)
        (group.parent as View).duckMargins(bottom=20)
        listOf(getString(R.string.duck_management_address) to address,getString(R.string.duck_access_code) to code).forEach {(title,value)->
            val row=LinearLayout(this).apply {gravity=android.view.Gravity.CENTER_VERTICAL;minimumHeight=dp(64);setPadding(dp(14),dp(12),dp(14),dp(12))}
            val words=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL}
            words.addView(duckText(title,16,bold=true).apply {minimumHeight=(16*resources.displayMetrics.scaledDensity*1.4f).toInt()})
            words.addView(value,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(4)})
            row.addView(words,LinearLayout.LayoutParams(0,-2,1f))
            if(review&&value===code) {
                val reveal=duckLink(getString(R.string.duck_reveal_code)) {}
                reveal.contentDescription=getString(R.string.duck_show_access_code)
                reveal.setOnClickListener {
                    exposed=!exposed
                    if(exposed) sheet.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    renderCode()
                    if(!exposed) sheet.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    reveal.setText(if(exposed) R.string.duck_mask_code else R.string.duck_reveal_code)
                    reveal.contentDescription=getString(if(exposed) R.string.duck_hide_access_code else R.string.duck_show_access_code)
                }
                row.addView(reveal,LinearLayout.LayoutParams(-2,dp(48)).apply {marginStart=dp(8)})
            }
            if(group.childCount>0) group.addView(duckRule());group.addView(row)
        }
        var url:String?=null
        var loading=false
        val copy=duckButton(getString(R.string.duck_copy_management_address),true) {
            url?.let {(getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("BackupDuck",it));duckAcknowledge(getString(R.string.duck_address_copied),sheet.body)}
        }
        copy.isEnabled=false
        sheet.body.addView(copy,LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(16)})
        duckNotice(sheet.body,getString(R.string.duck_code_private),getString(R.string.duck_code_pairing_independent)).duckMargins(bottom=16)
        val problem=duckFailure(sheet.body,getString(R.string.dashboard_unavailable))
        lateinit var retry:com.google.android.material.button.MaterialButton
        fun load() {
            if(loading||!sheet.isShowing)return
            loading=true;problem.visibility=View.GONE;copy.isEnabled=false;retry.visibility=View.GONE
            address.setText(R.string.history_loading);secret="";renderCode()
            lifecycleScope.launch {
                val result=runCatching {request(JSONObject().put("op","dashboard_info"))}
                loading=false
                if(!sheet.isShowing)return@launch
                result.onSuccess {info ->url=info.getString("url");address.text=url;secret=info.getString("code");renderCode();copy.visibility=View.VISIBLE;copy.isEnabled=true}
                    .onFailure {address.text="";problem.visibility=View.VISIBLE;retry.visibility=View.VISIBLE}
            }
        }
        retry=duckButton(getString(R.string.duck_retry)) {load()};sheet.body.addView(retry,LinearLayout.LayoutParams(-2,-2));retry.visibility=View.GONE
        val startup=BrowserStartupUI(activity,sheet.body,request={request(JSONObject().put("op","start_dashboard"));Unit},changed={ready ->
            if(ready) load() else {copy.isEnabled=false;retry.visibility=View.GONE;address.text="";secret="";url=null;renderCode()}
        })
        sheet.show()
        sheet.setOnDismissListener {startup.close();secret="";onDismiss()}
        sheet
    }
    fun code():DuckSheet = with(activity) {
        val sheet=DuckSheet(this,getString(R.string.dashboard_manage_code))
        val review=packageName=="app.backupduck.validation"
        if(!review) sheet.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        sheet.body.addView(duckParagraph(getString(R.string.dashboard_code_note)),LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(8);bottomMargin=dp(16)})
        val field=TextInputLayout(this).apply {
            isHintEnabled=false;boxBackgroundMode=TextInputLayout.BOX_BACKGROUND_OUTLINE
            setBoxCornerRadii(dp(8).toFloat(),dp(8).toFloat(),dp(8).toFloat(),dp(8).toFloat())
        }
        val edit=TextInputEditText(field.context).apply {
            id=View.generateViewId();textSize=16f;minimumHeight=dp(56);setPadding(dp(12),dp(12),dp(12),dp(12))
            contentDescription=getString(R.string.duck_new_access_code)
            inputType=InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
            filters=arrayOf(android.text.InputFilter.LengthFilter(10));isSingleLine=true
            transformationMethod=if(review) AlwaysMaskedPassword() else android.text.method.PasswordTransformationMethod.getInstance()
        };field.addView(edit)
        sheet.body.addView(duckParagraph(getString(R.string.duck_new_access_code)).apply {labelFor=edit.id},LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(8)})
        sheet.body.addView(field,LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(16)})
        val status=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL}
        sheet.body.addView(status,LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(18)})
        val note=duckNotice(status,getString(R.string.duck_code_tasks_unchanged)).duckMargins()
        val working=duckNotice(status,getString(R.string.duck_saving)).duckMargins().apply {visibility=View.GONE}
        val problem=duckFailure(status,getString(R.string.duck_code_save_failed)).duckMargins()
        val reset=duckButton(getString(R.string.duck_reset_random_code)) {
            // The prototype presents one modal at a time. Keep the draft while confirming.
            sheet.hide()
            var changed=false
            reset(onSuccess={changed=true;sheet.dismiss()}).setOnDismissListener {
                if(!changed&&!isFinishing&&!isDestroyed) sheet.show()
            }
        };sheet.body.addView(reset,LinearLayout.LayoutParams(-1,-2))
        var saving=false
        lateinit var save:com.google.android.material.button.MaterialButton
        save=sheet.addAction(getString(R.string.duck_save_access_code),true) {
            if(!saving) {
                val value=edit.text?.toString().orEmpty()
                field.error=null
                if(!value.matches(Regex("[0-9]{10}"))) {field.error=getString(R.string.dashboard_custom_hint);edit.requestFocus()}
                else {
                    saving=true;save.isEnabled=false;edit.isEnabled=false;reset.isEnabled=false;sheet.setCancelable(false)
                    save.setText(R.string.duck_saving);problem.visibility=View.GONE;note.visibility=View.GONE;working.visibility=View.VISIBLE
                    lifecycleScope.launch {
                        val result=runCatching {request(JSONObject().put("op","dashboard_access").put("root",root).put("code",value))}
                        saving=false;save.isEnabled=true;edit.isEnabled=true;reset.isEnabled=true;sheet.setCancelable(true);save.setText(R.string.duck_save_access_code)
                        if(!sheet.isShowing)return@launch
                        working.visibility=View.GONE
                        result.onSuccess {sheet.dismiss();duckAcknowledge(getString(R.string.dashboard_access_saved))}
                            .onFailure {problem.visibility=View.VISIBLE}
                    }
                }
            }
        }
        sheet.show();sheet
    }
    fun reset(onSuccess:()->Unit={}) = with(activity) {duckConfirm(R.string.dashboard_reset_code,R.string.dashboard_reset_note,R.string.dashboard_reset_code,notice=R.string.duck_reset_unchanged,busyNotice=R.string.duck_resetting) {dialog->change(dialog,reset=true,onSuccess=onSuccess)}}
    fun revoke() = with(activity) {duckConfirm(R.string.dashboard_revoke,R.string.dashboard_revoke_note,R.string.dashboard_revoke,true,notice=R.string.duck_revoke_sign_in,busyNotice=R.string.duck_revoking) {dialog->change(dialog,revoke=true)}}
    private fun change(dialog:DuckConfirmation,reset:Boolean=false,revoke:Boolean=false,onSuccess:()->Unit={}) = with(activity) {
        dialog.busy(true)
        lifecycleScope.launch {
            val result=runCatching {request(JSONObject().put("op","dashboard_access").put("root",root).put("reset",reset).put("revoke",revoke))}
            dialog.busy(false)
            if(!dialog.isShowing)return@launch
            result.onSuccess {onSuccess();dialog.dismiss();duckAcknowledge(getString(R.string.dashboard_access_saved))}
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
