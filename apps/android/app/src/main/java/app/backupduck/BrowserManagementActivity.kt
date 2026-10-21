package app.backupduck

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatDelegate
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** A2/A4/A5: saved preferences on a page; short edits and confirmations in basic dialogs. */
class BrowserManagementActivity:BackupDuckActivity() {
    override fun onCreate(savedInstanceState:Bundle?) {
        delegate.localNightMode=getSharedPreferences("appearance",MODE_PRIVATE).getInt("mode",AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        // Production credentials stay protected; catalog credentials are synthetic.
        val review=packageName.endsWith(".validation")
        if(!review&&!packageName.endsWith(".catalog")) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        nativeDetailPage(R.string.dashboard_section) {panel ->
            var url:String?=null
            var loading=false
            var generation=0
            lateinit var retry:com.google.android.material.button.MaterialButton
            val feedback=duckParagraph("").apply {
                visibility=View.GONE
                accessibilityLiveRegion=View.ACCESSIBILITY_LIVE_REGION_POLITE
            }
            fun message(text:String) {feedback.text=text;feedback.visibility=if(text.isEmpty())View.GONE else View.VISIBLE}
            val group=lookGroup(panel)
            lateinit var startup:BrowserStartupUI
            lateinit var enabled:com.google.android.material.materialswitch.MaterialSwitch
            enabled=lookSwitchRow(group,null,getString(R.string.duck_browser_enable),getString(R.string.duck_browser_disable_note),ReceiverDashboardSettings.enabled(this)) {checked ->
                val previous=ReceiverDashboardSettings.enabled(this)
                enabled.isEnabled=false;message("")
                lifecycleScope.launch {
                    val result=withContext(Dispatchers.IO) {runCatching {
                        if(ReceiverState.snapshot.value.phase=="ready") NativeBridge.request(JSONObject().put("op",if(checked) "start_dashboard" else "stop_dashboard"))
                    }}
                    if(result.isSuccess) ReceiverDashboardSettings.setEnabled(this@BrowserManagementActivity,checked)
                    else {enabled.restore(previous);message(getString(R.string.dashboard_unavailable))}
                    enabled.isEnabled=true;startup.refresh()
                }
            }.toggle
            val address=lookRow(group,null,getString(R.string.duck_management_address),getString(R.string.help_address_loading)).apply {setTextIsSelectable(true)}
            lateinit var code:android.widget.TextView
            val copy=lookButton(getString(R.string.duck_copy_management_address),LookButton.TEXT) {
                url?.let {
                    (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("BackupDuck",it))
                    message(getString(R.string.duck_address_copied))
                }
            }.apply {isEnabled=false}
            fun clearInfo() {
                generation++;url=null;address.setSupporting("—");code.setSupporting("—");copy.isEnabled=false;retry.visibility=View.GONE
            }
            fun loadInfo() {
                if(loading)return
                loading=true;retry.visibility=View.GONE
                if(feedback.text.toString()==getString(R.string.dashboard_unavailable))message("")
                val ticket=++generation
                address.setSupporting(getString(R.string.help_address_loading));copy.isEnabled=false
                lifecycleScope.launch {
                    val result=withContext(Dispatchers.IO) {runCatching {NativeBridge.request(JSONObject().put("op","dashboard_info")) as JSONObject}}
                    loading=false
                    if(ticket!=generation) {
                        if(startup.ready)loadInfo()
                        return@launch
                    }
                    result.onSuccess {
                        url=it.getString("url");address.setSupporting(url)
                        code.setSupporting(if(review) "••••••••••" else it.getString("code"));copy.isEnabled=true
                    }.onFailure {
                        clearInfo();message(getString(R.string.dashboard_unavailable));retry.visibility=View.VISIBLE
                    }
                }
            }
            val access=DashboardAccessUI(this,changed={message(it);if(startup.ready)loadInfo()})
            code=lookRow(group,null,getString(R.string.duck_access_code),"—") {access.code()}
            lookRow(group,null,getString(R.string.dashboard_reset_code)) {access.reset()}
            lookRow(group,null,getString(R.string.dashboard_revoke),getString(R.string.duck_browser_revoke_summary)) {access.revoke()}
            panel.addView(copy,LinearLayout.LayoutParams(-2,-2))
            panel.addView(feedback,LinearLayout.LayoutParams(-1,-2))
            retry=lookButton(getString(R.string.duck_retry),LookButton.TEXT) {loadInfo()}.apply {visibility=View.GONE}
            panel.addView(retry,LinearLayout.LayoutParams(-2,-2))
            panel.addView(duckParagraph(getString(R.string.duck_browser_network_note)),LinearLayout.LayoutParams(-1,-2).apply {
                topMargin=token(R.dimen.duck_space_small)
            })
            startup=BrowserStartupUI(this,panel,changed={ready ->
                enabled.restore(ReceiverDashboardSettings.enabled(this))
                if(ready)loadInfo() else clearInfo()
            })
        }
    }
}
