package app.backupduck

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.*

class ExperimentsActivity:AppCompatActivity() {
    override fun onCreate(savedInstanceState:Bundle?) {
        delegate.localNightMode=getSharedPreferences("appearance",MODE_PRIVATE).getInt("mode",AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        nativeDetailPage(R.string.experiments_title) {panel ->
            panel.addView(duckParagraph(getString(R.string.duck_experiments_intro)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(20)})
            val group=duckGroup(panel)
            duckSetting(group,getString(R.string.cleanup_title),getString(R.string.duck_experiments_cleanup_note)) {startActivity(Intent(this,PhotosProbeActivity::class.java))}
            duckSetting(group,getString(R.string.photos_diagnostics_title),getString(R.string.photos_probe_summary)) {startActivity(Intent(this,PhotosProbeActivity::class.java).putExtra("diagnostics",true))}
        }
    }
}
class PhotosProbeActivity:AppCompatActivity() {
    private val diagnostics get()=intent.getBooleanExtra("diagnostics",false)
    private val route get()=intent.getStringExtra("route") ?: if(diagnostics) "diagnostics" else "cleanup"
    private val cleanup get()=PhotosCleanup(this)
    private val prefs get()=getSharedPreferences("photos_probe",MODE_PRIVATE)
    private lateinit var statePanel:LinearLayout
    private var clean:Button?=null
    private var automatic:com.google.android.material.materialswitch.MaterialSwitch?=null
    private var start:Button?=null
    private var stop:Button?=null
    private var reviewed:Button?=null
    private var bind:TextView?=null
    private var evidence:TextView?=null
    private var restoringToggle=false
    private var reportPage:DuckPage?=null
    private val export=registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.CreateDocument("text/plain")) {uri ->
        if(uri!=null) lifecycleScope.launch {
            val page=reportPage?.takeIf {it.isShowing}
            page?.body?.let {it.removeAllViews();duckNotice(it,getString(R.string.duck_exporting_report))}
            val ok=withContext(Dispatchers.IO) {runCatching {
                val snapshot=PhotosProbeService.state.value
                val report="BackupDuck Google Photos diagnostics\nversion=${photosVersion()}\nobservation=${snapshot.observation}\nseen=${snapshot.seen.sorted().joinToString(",")}\ncleanup_enabled=${cleanup.enabled}\ncleanup_pending=${cleanup.pending}\ncleanup_result=${cleanup.reason}\naccount_bound=${cleanup.account.isNotEmpty()}\ncloud_backup_verified=false\n"
                checkNotNull(contentResolver.openOutputStream(uri,"wt")).use {it.write(report.toByteArray())}
            }.isSuccess}
            page?.body?.let {body ->
                body.removeAllViews()
                if(ok)duckNotice(body,getString(R.string.duck_export_report_success))
                else {duckProblem(body,getString(R.string.duck_export_report_failure));body.addView(duckButton(getString(R.string.duck_retry)) {launchReport()})}
            }
        }
    }
    override fun onCreate(savedInstanceState:Bundle?) {
        delegate.localNightMode=getSharedPreferences("appearance",MODE_PRIVATE).getInt("mode",AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        nativeDetailPage(when(route) {"diagnostics"->R.string.photos_diagnostics_title;"bind"->R.string.cleanup_bind;"progress"->R.string.cleanup_now;else->R.string.cleanup_title}) {panel ->
            statePanel=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL};panel.addView(statePanel)
            when(route) {
                "diagnostics"->diagnosticsContent(panel)
                "bind"->bindingContent(panel)
                "progress"->progressContent(panel)
                else->cleanupContent(panel)
            }
        }
        lifecycleScope.launch {repeatOnLifecycle(Lifecycle.State.STARTED) {PhotosProbeService.state.collect(::render)}}
        if(savedInstanceState==null&&intent.getBooleanExtra("start_flow",false)) {
            intent.removeExtra("start_flow")
            if(!PhotosProbeService.clean(bind=route=="bind"))showUnavailable()
        }
    }
    private fun cleanupContent(panel:LinearLayout) {
        val group=duckGroup(panel)
        duckSetting(group,getString(R.string.duck_cleanup_permission),getString(R.string.duck_cleanup_permission_note)) {consent(true,true) {openPermissions()}}
        bind=duckSetting(group,getString(R.string.duck_cleanup_bind_title),getString(R.string.duck_cleanup_fingerprint)) {consent(true) {openFlow("bind")}}
        val toggle=duckSwitch(cleanup.enabled) {value ->
            if(!restoringToggle&&value!=cleanup.enabled) {
                if(value) {restoreToggle();consent(true) {cleanup.enabled=true;restoreToggle()}}
                else {cleanup.enabled=false;PhotosProbeService.stop()}
            }
        };automatic=toggle
        duckSetting(group,getString(R.string.cleanup_automatic),getString(R.string.duck_cleanup_automatic_note),toggle)
        clean=duckButton(getString(R.string.cleanup_now),true) {consent(true) {openFlow("progress")}}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2))}
        reviewed=duckLink(getString(R.string.cleanup_reviewed)) {review()}.also {panel.addView(it)}
        panel.addView(duckLink(getString(R.string.photos_diagnostics_title)) {startActivity(Intent(this,PhotosProbeActivity::class.java).putExtra("diagnostics",true))})
        val threshold=duckParagraph(getString(R.string.history_loading));panel.addView(threshold)
        lifecycleScope.launch {
            val reserve=withContext(Dispatchers.IO) {runCatching {(NativeBridge.request(org.json.JSONObject().put("op","receiver_settings").put("root","$filesDir/receiver")) as org.json.JSONObject).getJSONObject("settings").getLong("min_free_bytes")}.getOrNull()}
            threshold.text=if(reserve==null)getString(R.string.cleanup_threshold_unavailable) else getString(R.string.cleanup_threshold,android.text.format.Formatter.formatFileSize(this@PhotosProbeActivity,cleanup.trigger(reserve)))
        }
    }
    private fun diagnosticsContent(panel:LinearLayout) {
        val group=duckGroup(panel)
        duckSetting(group,getString(R.string.photos_probe_version,photosVersion()),control=duckText("",13))
        evidence=duckSetting(group,getString(R.string.photos_probe_no_evidence),control=duckText("",13))
        panel.addView(duckButton(getString(R.string.photos_probe_permission)) {consent(false,true) {openPermissions()}},LinearLayout.LayoutParams(-1,-2))
        start=duckButton(getString(R.string.photos_probe_start),true) {consent(false) {begin()}}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        stop=duckButton(getString(R.string.photos_probe_stop)) {PhotosProbeService.stop()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        panel.addView(duckLink(getString(R.string.photos_probe_export)) {exportReport()})
        duckNotice(panel,getString(R.string.duck_cleanup_cloud_boundary))
    }
    private fun bindingContent(panel:LinearLayout) {
        duckNotice(panel,getString(R.string.duck_cleanup_bound_note))
        panel.addView(duckButton(getString(R.string.receiver_open_photos)) {openPhotos()},LinearLayout.LayoutParams(-1,-2))
        start=duckButton(getString(R.string.cleanup_bind),true) {
            if(!PhotosProbeService.clean(bind=true)) showUnavailable()
        }.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        stop=duckButton(getString(R.string.cleanup_stop)) {PhotosProbeService.stop()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
    }
    private fun progressContent(panel:LinearLayout) {
        start=duckButton(getString(if(cleanup.pending)R.string.cleanup_check_pending else R.string.cleanup_now),true) {
            if(!PhotosProbeService.clean())showUnavailable()
        }.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2))}
        stop=duckButton(getString(R.string.cleanup_stop)) {PhotosProbeService.stop()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        reviewed=duckButton(getString(R.string.cleanup_reviewed)) {review()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        duckNotice(panel,getString(R.string.duck_cleanup_cloud_boundary))
    }
    private fun openFlow(value:String) {startActivity(Intent(this,PhotosProbeActivity::class.java).putExtra("route",value).putExtra("start_flow",true))}
    private fun restoreToggle() {restoringToggle=true;automatic?.isChecked=cleanup.enabled;restoringToggle=false}
    private fun review() {
        duckConfirm(R.string.cleanup_reviewed,R.string.cleanup_reviewed_help,R.string.cleanup_reviewed,notice=R.string.duck_cleanup_no_changes) {dialog ->cleanup.reviewed();dialog.dismiss();render(PhotosProbeService.state.value)}
    }
    private fun consent(clean:Boolean,force:Boolean=false,action:()->Unit) {
        val key=if(clean)"cleanup_disclosure_v2" else "disclosure_v1"
        if(!force&&prefs.getBoolean(key,false)) {action();return}
        duckConfirm(if(clean)R.string.cleanup_title else R.string.photos_probe_disclosure_title,if(clean)R.string.cleanup_disclosure else R.string.photos_probe_disclosure,R.string.photos_probe_consent,notice=R.string.duck_cleanup_cloud_boundary) {dialog ->
            prefs.edit().putBoolean(key,true).apply();dialog.dismiss();action()
        }
    }
    private fun openPermissions() {runCatching {startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))}.onFailure {showUnavailable()}}
    private fun openPhotos() {val intent=packageManager.getLaunchIntentForPackage(PhotosProbeService.PHOTOS_PACKAGE);if(intent==null)showUnavailable() else runCatching {startActivity(intent)}.onFailure {showUnavailable()}}
    private fun begin() {
        val launch=packageManager.getLaunchIntentForPackage(PhotosProbeService.PHOTOS_PACKAGE)
        if(launch==null) {showUnavailable();return}
        if(!PhotosProbeService.begin()) {render(PhotosProbeService.state.value);return}
        runCatching {startActivity(launch)}.onFailure {PhotosProbeService.stop();showUnavailable()}
    }
    private fun showUnavailable() {statePanel.removeAllViews();duckProblem(statePanel,getString(R.string.photos_probe_unavailable))}
    @Suppress("DEPRECATION") private fun photosVersion():String=runCatching {packageManager.getPackageInfo(PhotosProbeService.PHOTOS_PACKAGE,0).versionName ?: "—"}.getOrDefault(getString(R.string.photos_probe_missing))
    private fun launchReport() {export.launch("BackupDuck-photos-check.txt")}
    private fun exportReport() {
        val page=DuckPage(this,getString(R.string.duck_export_title));reportPage=page
        val group=duckGroup(page.body);duckSetting(group,getString(R.string.photos_probe_export),getString(R.string.duck_report_probe),duckText("",13))
        duckNotice(page.body,getString(R.string.duck_export_report_note))
        page.body.addView(duckButton(getString(R.string.duck_choose_location),true) {launchReport()},LinearLayout.LayoutParams(-1,-2));page.show()
    }
    private var lastStatus:String?=null
    private fun render(state:PhotosProbeState) {
        val result=if(state.mode=="probe")cleanup.reason else state.observation
        val resource=resources.getIdentifier("cleanup_result_$result","string",packageName)
        val cleanupText=getString(when {
            !state.connected->R.string.photos_probe_disabled
            resource!=0->resource
            cleanup.account.isNotEmpty()->R.string.cleanup_result_bound
            else->R.string.cleanup_result_ready
        })
        val probeMessage=when {
            !state.connected->R.string.photos_probe_disabled
            state.mode!="probe"->R.string.photos_probe_ready
            state.running->R.string.photos_probe_running
            state.observation=="confirmation"->R.string.photos_probe_confirmation
            state.observation=="nothing_to_free"->R.string.photos_probe_nothing
            state.observation=="completed"->R.string.photos_probe_completed
            state.observation=="locked"->R.string.photos_probe_locked
            state.observation=="expired"->R.string.photos_probe_expired
            state.observation in setOf("unavailable","interrupted","disconnected")->R.string.photos_probe_unavailable
            state.observation=="stopped"->R.string.photos_probe_stopped
            else->R.string.photos_probe_ready
        }
        val message=if(diagnostics) {if(state.running&&state.mode=="probe")getString(probeMessage,state.secondsLeft) else getString(probeMessage)} else cleanupText
        if(message!=lastStatus) {
            lastStatus=message;statePanel.removeAllViews()
            if(result in setOf("account_changed","unavailable","expired","interrupted","disconnected"))duckProblem(statePanel,message) else duckNotice(statePanel,message)
        }
        val idle=state.connected&&!state.running
        start?.isEnabled=idle&&(route!="progress"||cleanup.account.isNotEmpty())
        bind?.parent?.let {(it as View).isEnabled=idle&&!cleanup.pending}
        clean?.text=getString(if(cleanup.pending)R.string.cleanup_check_pending else R.string.cleanup_now)
        clean?.isEnabled=idle&&cleanup.account.isNotEmpty()
        automatic?.isEnabled=idle&&cleanup.account.isNotEmpty();restoreToggle()
        stop?.visibility=if(state.running)View.VISIBLE else View.GONE
        reviewed?.visibility=if(cleanup.pending&&!state.running)View.VISIBLE else View.GONE
        evidence?.text=if(state.seen.isEmpty())getString(R.string.photos_probe_no_evidence) else listOf("account_entry" to R.string.photos_probe_seen_account,"cleanup_entry" to R.string.photos_probe_seen_entry,"confirmation" to R.string.photos_probe_seen_confirmation,"nothing_to_free" to R.string.photos_probe_seen_empty,"releasing" to R.string.photos_probe_seen_progress,"completed" to R.string.photos_probe_seen_completed).filter {it.first in state.seen}.joinToString(" · ") {getString(it.second)}
    }
}
