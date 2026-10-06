package app.backupduck

import android.os.Bundle
import android.view.View
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** RC.3 browser controls presented through the complete Android v1.2 flow. */
class BrowserManagementActivity:AppCompatActivity() {
    override fun onCreate(savedInstanceState:Bundle?) {
        delegate.localNightMode=getSharedPreferences("appearance",MODE_PRIVATE).getInt("mode",AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        val access=DashboardAccessUI(this)
        nativeDetailPage(R.string.dashboard_section) {panel ->
            panel.addView(duckText(getString(R.string.duck_browser_intro),13,true),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(16)})
            val group=duckGroup(panel)
            var applying=false
            val enabled=duckSwitch(ReceiverDashboardSettings.enabled(this)) {}
            duckSetting(group,getString(R.string.duck_browser_enable),getString(R.string.duck_browser_disable_note),enabled)
            duckSetting(group,getString(R.string.duck_browser_access),getString(R.string.duck_browser_access_note),action={access.access {
                applying=true;enabled.isChecked=ReceiverDashboardSettings.enabled(this);applying=false
            }})
            duckSetting(group,getString(R.string.dashboard_manage_code),getString(R.string.duck_code_persistence),action={access.code()})
            duckSetting(group,getString(R.string.dashboard_revoke),getString(R.string.duck_browser_revoke_summary),action={access.revoke()})
            val failure=duckFailure(panel,getString(R.string.dashboard_unavailable))
            lateinit var startup:BrowserStartupUI
            enabled.setOnCheckedChangeListener {_,checked ->
                if(!applying) {
                    val previous=ReceiverDashboardSettings.enabled(this)
                    enabled.isEnabled=false;failure.visibility=View.GONE
                    lifecycleScope.launch {
                        val result=withContext(Dispatchers.IO) {runCatching {
                            if(ReceiverState.snapshot.value.phase=="ready") NativeBridge.request(JSONObject().put("op",if(checked) "start_dashboard" else "stop_dashboard"))
                        }}
                        applying=true
                        if(result.isSuccess) ReceiverDashboardSettings.setEnabled(this@BrowserManagementActivity,checked) else {enabled.isChecked=previous;failure.visibility=View.VISIBLE}
                        applying=false;enabled.isEnabled=true;startup.refresh()
                    }
                }
            }
            val trusted=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL}
            duckNotice(trusted,getString(R.string.duck_browser_trusted),getString(R.string.duck_browser_http))
            panel.addView(trusted)
            startup=BrowserStartupUI(this,panel,changed={ready ->
                trusted.visibility=if(ReceiverState.snapshot.value.phase=="idle"||ready||(ReceiverState.snapshot.value.phase=="ready"&&!ReceiverDashboardSettings.enabled(this))) View.VISIBLE else View.GONE
                applying=true;enabled.isChecked=ReceiverDashboardSettings.enabled(this);applying=false
            })
        }
    }
}
