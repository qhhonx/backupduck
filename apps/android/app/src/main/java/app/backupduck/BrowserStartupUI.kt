package app.backupduck

import android.content.Intent
import android.view.View
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Shared asynchronous startup feedback for the page and its access sheet. */
internal class BrowserStartupUI(
    private val activity:AppCompatActivity,
    parent:LinearLayout,
    private val states:StateFlow<ReceiverSnapshot> = ReceiverState.snapshot,
    private val startReceiver:()->Unit = {
        ReceiverPreferences.setEnabled(activity,true)
        activity.startForegroundService(Intent(activity,ReceiverService::class.java))
    },
    private val request:suspend ()->Unit = {
        withContext(Dispatchers.IO) {NativeBridge.request(JSONObject().put("op","start_dashboard"))};Unit
    },
    private val changed:(Boolean)->Unit = {}
) {
    val view=LinearLayout(activity).apply {orientation=LinearLayout.VERTICAL}
    private val idle=LinearLayout(activity).apply {orientation=LinearLayout.VERTICAL}
    private val starting=LinearLayout(activity).apply {orientation=LinearLayout.VERTICAL}
    private val failed=LinearLayout(activity).apply {orientation=LinearLayout.VERTICAL}
    private val failureMessages=mutableMapOf<Int,View>()
    private var failure:String?=null
    private var verifying=false
    var ready=false; private set
    private val observer:kotlinx.coroutines.Job
    init {
        activity.duckNotice(idle,activity.getString(R.string.dashboard_start_receiver))
        idle.addView(activity.duckButton(activity.getString(R.string.receiver_start),true) {begin()},LinearLayout.LayoutParams(-1,-2))
        activity.duckNotice(starting,activity.getString(R.string.duck_browser_starting))
        listOf(R.string.duck_start_port_busy,R.string.duck_start_network_failed,R.string.dashboard_unavailable).forEach {
            failureMessages[it]=activity.duckFailure(failed,activity.getString(it))
        }
        failed.addView(activity.duckButton(activity.getString(R.string.duck_retry)) {begin()},LinearLayout.LayoutParams(-2,-2))
        view.addView(idle);view.addView(starting);view.addView(failed);parent.addView(view)
        render("idle")
        observer=activity.lifecycleScope.launch {
            kotlinx.coroutines.yield()
            states.map {it.phase to it.error}.distinctUntilChanged().collect {(phase,error)->
                when {
                    phase=="ready" -> verify()
                    phase=="waiting" -> {ready=false;failure=error?:"operation_failed";render("failed");changed(ready)}
                    phase=="starting" -> {ready=false;render(if(failure!=null) "failed" else "starting")}
                    else -> {ready=false;failure=null;render("idle");changed(ready)}
                }
            }
        }
    }
    fun begin() {
        if(verifying)return
        failure=null;ready=false
        ReceiverDashboardSettings.setEnabled(activity,true)
        render("starting") // The click has feedback before the asynchronous service responds.
        if(states.value.phase=="ready") verify()
        else runCatching {startReceiver()}.onFailure {failure="operation_failed";render("failed")}
    }
    fun refresh() {if(states.value.phase=="ready")verify()}
    fun close() {observer.cancel()}
    private fun verify() {
        if(verifying)return
        if(!ReceiverDashboardSettings.enabled(activity)) {ready=false;render("ready");changed(ready);return}
        verifying=true;render("starting")
        activity.lifecycleScope.launch {
            val result=runCatching {request()}
            verifying=false
            if(states.value.phase!="ready")return@launch
            if(!ReceiverDashboardSettings.enabled(activity)) {ready=false;render("ready");changed(ready);return@launch}
            result.onSuccess {failure=null;ready=true;render("ready")}
                .onFailure {failure="dashboard_unavailable";ready=false;render("failed")}
            changed(ready)
        }
    }
    private fun render(state:String) {
        view.visibility=if(state=="ready")View.GONE else View.VISIBLE
        idle.visibility=if(state=="idle")View.VISIBLE else View.GONE
        starting.visibility=if(state=="starting")View.VISIBLE else View.GONE
        failed.visibility=if(state=="failed")View.VISIBLE else View.GONE
        val message=when(failure) {
            "receiver_port_in_use" -> R.string.duck_start_port_busy
            "receiver_interface_unavailable","wifi_required","receiver_address_changed" -> R.string.duck_start_network_failed
            else -> R.string.dashboard_unavailable
        }
        failureMessages.forEach {(id,v)->v.visibility=if(id==message)View.VISIBLE else View.GONE}
    }
}
