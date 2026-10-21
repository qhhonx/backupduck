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

class ExperimentsActivity:BackupDuckActivity() {
    override fun onCreate(savedInstanceState:Bundle?) {
        delegate.localNightMode=getSharedPreferences("appearance",MODE_PRIVATE).getInt("mode",AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        nativeDetailPage(R.string.experiments_title) {panel ->
            panel.addView(duckParagraph(getString(R.string.duck_experiments_intro)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(20)})
            val group=duckGroup(panel)
            duckSetting(group,getString(R.string.cleanup_title),getString(R.string.duck_experiments_cleanup_note)) {startActivity(Intent(this,PhotosProbeActivity::class.java))}
            panel.addView(duckParagraph(getString(R.string.experiment_compatibility)))
        }
        FeatureDiscovery(this).acknowledge(FeatureDiscovery.PHOTOS_CLEANUP)
    }
}
class PhotosProbeActivity:BackupDuckActivity() {
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
    private var permissionNote:TextView?=null
    private var accountNote:TextView?=null
    private var automaticNote:TextView?=null
    private var thresholdText:String?=null
    private var restoringToggle=false
    private var reportPage:DuckPage?=null
    private val export=registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.CreateDocument("text/plain")) {uri ->
        if(uri!=null) lifecycleScope.launch {
            val page=reportPage?.takeIf {it.isShowing}
            page?.state?.putString("result", "busy")
            page?.body?.let {it.removeAllViews();duckNotice(it,getString(R.string.duck_exporting_report))}
            val ok=withContext(Dispatchers.IO) {runCatching {
                val snapshot=PhotosProbeService.state.value
                val report="BackupDuck Google Photos diagnostics\nversion=${photosVersion()}\nobservation=${snapshot.observation}\nseen=${snapshot.seen.sorted().joinToString(",")}\ncleanup_enabled=${cleanup.enabled}\ncleanup_pending=${cleanup.pending}\ncleanup_result=${cleanup.reason}\naccount_bound=${cleanup.account.isNotEmpty()}\ncloud_backup_verified=false\n"
                checkNotNull(contentResolver.openOutputStream(uri,"wt")).use {it.write(report.toByteArray())}
            }.isSuccess}
            page?.state?.putString("result", if(ok) "success" else "failure")
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
            statePanel=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL}
            if(route!="cleanup")panel.addView(statePanel)
            when(route) {
                "diagnostics"->diagnosticsContent(panel)
                "bind"->bindingContent(panel)
                "progress"->progressContent(panel)
                else->cleanupContent(panel)
            }
        }
        lifecycleScope.launch {repeatOnLifecycle(Lifecycle.State.STARTED) {PhotosProbeService.state.collect(::render)}}
    }
    override fun onPostResume() {
        super.onPostResume()
        // Launch the external app after our own resume has finished. Starting it
        // during onCreate can let this Activity resume over Google Photos.
        window.decorView.post {
            if (!isFinishing && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
                && intent.getBooleanExtra("start_flow",false)) {
                intent.removeExtra("start_flow")
                if(!PhotosProbeService.clean(bind=route=="bind",returnRoute=route))showUnavailable()
            }
        }
    }
    private fun cleanupContent(panel:LinearLayout) {
        panel.addView(duckParagraph(getString(R.string.cleanup_description)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(20)})
        val setup=duckGroup(panel,getString(R.string.experiment_setup))
        val permission=duckSetting(setup,getString(R.string.experiment_permission),getString(R.string.experiment_permission_off)) {consent(true,true) {openPermissions()}}
        permissionNote=(permission.parent as LinearLayout).getChildAt(1) as TextView
        bind=duckSetting(setup,getString(R.string.experiment_account),getString(R.string.experiment_account_off)) {consent(true) {openFlow(if(cleanup.pending) "progress" else "bind")}}
        accountNote=(bind!!.parent as LinearLayout).getChildAt(1) as TextView
        val toggle=duckSwitch(cleanup.enabled) {value ->
            if(!restoringToggle&&value!=cleanup.enabled) {
                if(value) {restoreToggle();consent(true) {cleanup.enabled=true;restoreToggle()}}
                else {cleanup.enabled=false;PhotosProbeService.stop()}
            }
        };automatic=toggle
        val autoGroup=duckGroup(panel,getString(R.string.experiment_auto))
        val autoTitle=duckSetting(autoGroup,getString(R.string.cleanup_automatic),getString(R.string.experiment_auto_setup),toggle)
        automaticNote=(autoTitle.parent as LinearLayout).getChildAt(1) as TextView
        panel.addView(statePanel)
        clean=duckButton(getString(R.string.cleanup_now),true) {consent(true) {openFlow("progress")}}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2))}
        stop=duckButton(getString(R.string.cleanup_stop)) {PhotosProbeService.stop()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        reviewed=duckButton(getString(R.string.cleanup_reviewed)) {review()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        duckSection(panel,getString(R.string.experiment_troubleshoot))
        panel.addView(duckParagraph(getString(R.string.experiment_troubleshoot_note)))
        panel.addView(duckButton(getString(R.string.photos_diagnostics_title)) {startActivity(Intent(this,PhotosProbeActivity::class.java).putExtra("diagnostics",true))},LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16);bottomMargin=dp(16)})
        lifecycleScope.launch {
            val reserve=withContext(Dispatchers.IO) {runCatching {(NativeBridge.request(org.json.JSONObject().put("op","receiver_settings").put("root","$filesDir/receiver")) as org.json.JSONObject).getJSONObject("settings").getLong("min_free_bytes")}.getOrNull()}
            thresholdText=if(reserve==null)getString(R.string.cleanup_threshold_unavailable) else getString(R.string.cleanup_threshold,android.text.format.Formatter.formatFileSize(this@PhotosProbeActivity,cleanup.trigger(reserve)))
            render(PhotosProbeService.state.value)
        }
    }
    private fun diagnosticsContent(panel:LinearLayout) {
        panel.addView(duckParagraph(getString(R.string.experiment_probe_intro)))
        panel.addView(duckParagraph(getString(R.string.photos_probe_steps)),LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(12);bottomMargin=dp(20)})
        val group=duckGroup(panel)
        duckSetting(group,getString(R.string.photos_probe_version,photosVersion()),control=duckText("",13))
        evidence=duckSetting(group,getString(R.string.photos_probe_no_evidence),control=duckText("",13))
        panel.addView(duckButton(getString(R.string.photos_probe_permission)) {consent(false,true) {openPermissions()}},LinearLayout.LayoutParams(-1,-2))
        start=duckButton(getString(R.string.photos_probe_start),true) {consent(false) {begin()}}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        stop=duckButton(getString(R.string.photos_probe_stop)) {PhotosProbeService.stop()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        panel.addView(duckButton(getString(R.string.photos_probe_export)) {exportReport()},LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})
    }
    private fun bindingContent(panel:LinearLayout) {
        panel.addView(duckParagraph(getString(R.string.experiment_bind_intro)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(20)})
        panel.addView(duckButton(getString(R.string.receiver_open_photos)) {openPhotos()},LinearLayout.LayoutParams(-1,-2))
        start=duckButton(getString(R.string.cleanup_bind),true) {
            if(!PhotosProbeService.clean(bind=true,returnRoute="bind")) showUnavailable()
        }.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        stop=duckButton(getString(R.string.cleanup_stop)) {PhotosProbeService.stop()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
    }
    private fun progressContent(panel:LinearLayout) {
        start=duckButton(getString(if(cleanup.pending)R.string.cleanup_check_pending else R.string.cleanup_now),true) {
            if(!PhotosProbeService.clean(returnRoute="progress"))showUnavailable()
        }.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2))}
        stop=duckButton(getString(R.string.cleanup_stop)) {PhotosProbeService.stop()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        reviewed=duckButton(getString(R.string.cleanup_reviewed)) {review()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
    }
    private fun openFlow(value:String) {startActivity(Intent(this,PhotosProbeActivity::class.java).putExtra("route",value).putExtra("start_flow",true))}
    private fun restoreToggle() {restoringToggle=true;automatic?.isChecked=cleanup.enabled;restoringToggle=false}
    private fun review() {
        duckConfirm(R.string.cleanup_reviewed,R.string.cleanup_reviewed_help,R.string.cleanup_reviewed,notice=R.string.duck_cleanup_no_changes) {dialog ->cleanup.reviewed();dialog.dismiss();render(PhotosProbeService.state.value)}
    }
    private fun consent(clean:Boolean,force:Boolean=false,action:()->Unit) {
        val key=if(clean)"cleanup_disclosure_v2" else "disclosure_v1"
        if(!force&&prefs.getBoolean(key,false)) {action();return}
        duckConfirm(if(clean)R.string.cleanup_title else R.string.photos_probe_disclosure_title,if(clean)R.string.cleanup_disclosure else R.string.photos_probe_disclosure,R.string.photos_probe_consent) {dialog ->
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
    private fun exportReport() { createReportPage().show() }
    internal override fun restorePage(route: String, state: Bundle): PageDestination =
        if (route == "probe-report") createReportPage(state) else super.restorePage(route, state)
    private fun createReportPage(restored: Bundle = Bundle()): DuckPage {
        val page=DuckPage(this,getString(R.string.photos_probe_export), "probe-report");reportPage=page
        page.state.putAll(restored)
        page.body.addView(duckParagraph(getString(R.string.duck_report_probe)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(20)})
        page.body.addView(duckButton(getString(R.string.duck_choose_location),true) {launchReport()},LinearLayout.LayoutParams(-1,-2))
        if (restored.containsKey("result")) {
            page.body.removeAllViews()
            if (restored.getString("result") == "success") duckNotice(page.body,getString(R.string.duck_export_report_success))
            else { duckProblem(page.body,getString(R.string.duck_export_report_failure));page.body.addView(duckButton(getString(R.string.duck_retry)) {launchReport()}) }
        }
        return page
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
        val setupStatus=route=="cleanup"&&!state.running&&!cleanup.pending&&(!state.connected||result in setOf("ready","bound","reviewed"))
        val visibleMessage=if(setupStatus)"" else message
        if(visibleMessage!=lastStatus) {
            lastStatus=visibleMessage;statePanel.removeAllViews()
            if(visibleMessage.isNotEmpty()) {
                if(result in setOf("account_changed","unavailable","expired","interrupted","disconnected","manual_review_required"))duckProblem(statePanel,message) else duckNotice(statePanel,message)
            }
        }
        val idle=state.connected&&!state.running
        start?.isEnabled=idle&&(route!="progress"||cleanup.account.isNotEmpty())
        (bind?.parent?.parent as? View)?.isEnabled=idle
        permissionNote?.text=getString(if(state.connected)R.string.experiment_permission_on else R.string.experiment_permission_off)
        val accountChanged=result=="account_changed"||cleanup.reason=="account_changed"
        val accountReady=cleanup.account.isNotEmpty()&&!accountChanged
        accountNote?.text=getString(when {accountChanged->R.string.experiment_account_changed;cleanup.pending&&accountReady->R.string.experiment_account_pending;accountReady->R.string.experiment_account_on;else->R.string.experiment_account_off})
        automaticNote?.text=if(state.connected&&accountReady)thresholdText ?: getString(R.string.history_loading) else getString(R.string.experiment_auto_setup)
        clean?.text=getString(if(cleanup.pending)R.string.cleanup_check_pending else R.string.cleanup_now)
        clean?.visibility=if(accountReady||cleanup.pending)View.VISIBLE else View.GONE
        clean?.isEnabled=idle&&accountReady
        automatic?.isEnabled=idle&&accountReady;restoreToggle()
        stop?.visibility=if(state.running)View.VISIBLE else View.GONE
        reviewed?.visibility=if(cleanup.pending&&!state.running)View.VISIBLE else View.GONE
        evidence?.text=if(state.seen.isEmpty())getString(R.string.photos_probe_no_evidence) else listOf("account_entry" to R.string.photos_probe_seen_account,"cleanup_entry" to R.string.photos_probe_seen_entry,"confirmation" to R.string.photos_probe_seen_confirmation,"nothing_to_free" to R.string.photos_probe_seen_empty,"releasing" to R.string.photos_probe_seen_progress,"completed" to R.string.photos_probe_seen_completed).filter {it.first in state.seen}.joinToString(" · ") {getString(it.second)}
    }
}
