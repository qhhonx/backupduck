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
        startActivity(Intent(this,MainActivity::class.java).putExtra("destination","storage"))
        finish()
    }
}
class PhotosProbeActivity:BackupDuckActivity() {
    private val diagnostics get()=intent.getBooleanExtra("diagnostics",false)
    private val route get()=intent.getStringExtra("route") ?: if(diagnostics) "diagnostics" else "cleanup"
    private val cleanup get()=PhotosCleanup(this)
    private val operations get()=ReceiverEnvironment.cleanupOperations
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
            page?.let { renderProbeReport(it,"busy") }
            val ok=withContext(Dispatchers.IO) {runCatching {
                val snapshot=operations.state.value
                val report="BackupDuck Google Photos diagnostics\nversion=${photosVersion()}\nobservation=${snapshot.observation}\nseen=${snapshot.seen.sorted().joinToString(",")}\ncleanup_enabled=${cleanup.enabled}\ncleanup_pending=${cleanup.pending}\ncleanup_result=${cleanup.reason}\naccount_bound=${cleanup.account.isNotEmpty()}\ncloud_backup_verified=false\n"
                checkNotNull(contentResolver.openOutputStream(uri,"wt")).use {it.write(report.toByteArray())}
            }.isSuccess}
            page?.let {
                if(ok)it.state.putString("file",diagnosticFileName(uri,"BackupDuck-photos-check.txt"))
                renderProbeReport(it,if(ok)"success" else "failure")
            }
        }
    }
    override fun onCreate(savedInstanceState:Bundle?) {
        delegate.localNightMode=getSharedPreferences("appearance",MODE_PRIVATE).getInt("mode",AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        nativeDetailPage(when(route) {"diagnostics"->R.string.diag_probe;"bind"->R.string.diag_bind;"progress"->R.string.diag_progress;else->R.string.diag_setup}) {panel ->
            statePanel=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL}
            if(route!="cleanup")panel.addView(statePanel)
            when(route) {
                "diagnostics"->diagnosticsContent(panel)
                "bind"->bindingContent(panel)
                "progress"->progressContent(panel)
                else->cleanupContent(panel)
            }
        }
        if(savedInstanceState==null) ReceiverEnvironment.diagnosticInitialState?.getString("probe-report")?.let { phase ->
            window.decorView.post { val page=createReportPage(); page.show(); if(phase!="ready") {
                page.state.putString("file","BackupDuck-photos-check.txt");renderProbeReport(page,phase)
            } }
        }
        lifecycleScope.launch {repeatOnLifecycle(Lifecycle.State.STARTED) {operations.state.collect(::render)}}
    }
    override fun onPostResume() {
        super.onPostResume()
        // Launch the external app after our own resume has finished. Starting it
        // during onCreate can let this Activity resume over Google Photos.
        window.decorView.post {
            if (!isFinishing && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
                && intent.getBooleanExtra("start_flow",false)) {
                intent.removeExtra("start_flow")
                if(!operations.start(this, bind=route=="bind",route=route))showUnavailable()
            }
        }
    }
    private fun cleanupContent(panel:LinearLayout) {
        panel.addView(duckParagraph(getString(R.string.cleanup_description)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(20)})
        val setup=lookGroup(panel)
        permissionNote=lookRow(setup,R.drawable.ic_settings,getString(R.string.diag_access),getString(R.string.diag_access_off)) {consent(true,true) {openPermissions()}}
        bind=lookRow(setup,R.drawable.ic_check,getString(R.string.diag_bind),getString(R.string.diag_account_off)) {consent(true) {openFlow(if(cleanup.pending) "progress" else "bind")}}
        accountNote=bind
        panel.addView(statePanel)
        clean=duckButton(getString(R.string.cleanup_now),true) {consent(true) {openFlow("progress")}}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2))}
        stop=duckButton(getString(R.string.cleanup_stop)) {operations.stop()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        reviewed=duckButton(getString(R.string.cleanup_reviewed)) {review()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        duckSection(panel,getString(R.string.experiment_troubleshoot))
        panel.addView(duckParagraph(getString(R.string.experiment_troubleshoot_note)))
        panel.addView(duckButton(getString(R.string.photos_diagnostics_title)) {startActivity(Intent(this,PhotosProbeActivity::class.java).putExtra("diagnostics",true))},LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16);bottomMargin=dp(16)})

    }
    private fun diagnosticsContent(panel:LinearLayout) {
        panel.addView(duckParagraph(getString(R.string.diag_probe_note)))
        val group=lookGroup(panel)
        lookRow(group,R.drawable.ic_info,getString(R.string.diag_version),photosVersion())
        evidence=lookRow(group,R.drawable.ic_document,getString(R.string.diag_seen),getString(R.string.photos_probe_no_evidence))
        lookRow(group,R.drawable.ic_settings,getString(R.string.diag_access)) {consent(false,true) {openPermissions()}}
        panel.addView(duckParagraph(getString(R.string.photos_probe_steps)),LinearLayout.LayoutParams(-1,-2).apply {topMargin=token(R.dimen.duck_space_medium);bottomMargin=token(R.dimen.duck_space_medium)})
        start=lookButton(getString(R.string.photos_probe_start),LookButton.FILLED) {consent(false) {begin()}}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2))}
        stop=lookButton(getString(R.string.photos_probe_stop),LookButton.TONAL) {operations.stop()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2))}
        lookRow(lookGroup(panel),R.drawable.ic_document,getString(R.string.photos_probe_export),getString(R.string.duck_report_probe)) {exportReport()}
    }
    private fun bindingContent(panel:LinearLayout) {
        panel.addView(duckParagraph(getString(R.string.experiment_bind_intro)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(20)})
        panel.addView(duckButton(getString(R.string.receiver_open_photos)) {openPhotos()},LinearLayout.LayoutParams(-1,-2))
        start=duckButton(getString(R.string.cleanup_bind),true) {
            if(!operations.start(this, bind=true,route="bind")) showUnavailable()
        }.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        stop=duckButton(getString(R.string.cleanup_stop)) {operations.stop()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
    }
    private fun progressContent(panel:LinearLayout) {
        start=duckButton(getString(if(cleanup.pending)R.string.cleanup_check_pending else R.string.cleanup_now),true) {
            if(!operations.start(this, bind=false,route="progress"))showUnavailable()
        }.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2))}
        stop=duckButton(getString(R.string.cleanup_stop)) {operations.stop()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
        reviewed=duckButton(getString(R.string.cleanup_reviewed)) {review()}.also {panel.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16)})}
    }
    private fun openFlow(value:String) {startActivity(Intent(this,PhotosProbeActivity::class.java).putExtra("route",value).putExtra("start_flow",true))}
    private fun restoreToggle() {restoringToggle=true;automatic?.isChecked=cleanup.enabled;restoringToggle=false}
    private fun review() {
        duckConfirm(R.string.cleanup_reviewed,R.string.cleanup_reviewed_help,R.string.cleanup_reviewed,notice=R.string.duck_cleanup_no_changes) {dialog ->cleanup.reviewed();dialog.dismiss();render(operations.state.value)}
    }
    private fun consent(clean:Boolean,force:Boolean=false,action:()->Unit) {
        val key=if(clean)"cleanup_disclosure_v2" else "disclosure_v1"
        if(!force&&prefs.getBoolean(key,false)) {action();return}
        duckConfirm(if(clean)R.string.cleanup_title else R.string.photos_probe_disclosure_title,if(clean)R.string.cleanup_disclosure else R.string.photos_probe_disclosure,R.string.photos_probe_consent) {dialog ->
            prefs.edit().putBoolean(key,true).apply();dialog.dismiss();action()
        }
    }
    private fun openPermissions() {runCatching {operations.access(this) {render(operations.state.value)}}.onFailure {showUnavailable()}}
    private fun openPhotos() {runCatching {operations.photos(this) {render(operations.state.value)}}.onFailure {showUnavailable()}}
    private fun begin() {if(!operations.observe(this)) showUnavailable()}
    private fun showUnavailable() {statePanel.removeAllViews();duckProblem(statePanel,getString(R.string.photos_probe_unavailable))}
    private fun photosVersion():String=ReceiverEnvironment.photosVersion(this) ?: getString(R.string.photos_probe_missing)
    private fun launchReport() {runCatching {export.launch("BackupDuck-photos-check.txt")}.onFailure {reportPage?.let {renderProbeReport(it,"failure")} }}
    private fun exportReport() { createReportPage().show() }
    internal override fun restorePage(route: String, state: Bundle): PageDestination =
        if (route == "probe-report") createReportPage(state) else super.restorePage(route, state)
    private fun createReportPage(restored: Bundle = Bundle()): DuckPage {
        val page=DuckPage(this,getString(R.string.photos_probe_export), "probe-report");reportPage=page
        page.state.putAll(restored)
        page.body.addView(duckParagraph(getString(R.string.duck_report_probe)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(20)})
        page.body.addView(duckButton(getString(R.string.duck_choose_location),true) {launchReport()},LinearLayout.LayoutParams(-1,-2))
        if (restored.containsKey("result")) renderProbeReport(page,if(restored.getString("result")=="success")"success" else "failure")
        return page
    }
    private fun renderProbeReport(page: DuckPage, result: String) {
        page.state.putString("result",result);page.body.removeAllViews()
        when(result) {
            "busy" -> page.body.addView(duckParagraph(getString(R.string.diag_exporting)))
            "success" -> page.body.addView(duckParagraph(getString(R.string.diag_saved,page.state.getString("file") ?: "BackupDuck-photos-check.txt")))
            else -> { duckProblem(page.body,getString(R.string.duck_export_report_failure));page.body.addView(duckButton(getString(R.string.duck_retry)) {launchReport()}) }
        }
    }

    private var lastStatus:String?=null
    private fun render(state:PhotosProbeState) {
        val result=if(state.mode=="probe"||!state.running)cleanup.reason else state.observation
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
        val statusKey=if(visibleMessage.isEmpty()) "" else "$visibleMessage|${if(diagnostics)state.observation else result}"
        if(statusKey!=lastStatus) {
            lastStatus=statusKey;statePanel.removeAllViews()
            if(visibleMessage.isNotEmpty()) {
                statePanel.addView(lookText(message,com.google.android.material.R.style.TextAppearance_Material3_BodyLarge))
                statePanel.addView(lookText(if(diagnostics)state.observation else result,com.google.android.material.R.style.TextAppearance_Material3_LabelSmall,secondary=true).apply {typeface=android.graphics.Typeface.MONOSPACE})
            }
        }
        val idle=state.connected&&!state.running
        start?.isEnabled=idle&&(route!="progress"||cleanup.account.isNotEmpty())
        if(route=="progress")start?.text=getString(if(cleanup.pending)R.string.cleanup_check_pending else R.string.cleanup_now)
        (bind?.parent?.parent as? View)?.isEnabled=idle
        permissionNote?.setSupporting(getString(if(state.connected)R.string.diag_access_on else R.string.diag_access_off))
        val accountChanged=result=="account_changed"||cleanup.reason=="account_changed"
        val accountReady=cleanup.account.isNotEmpty()&&!accountChanged
        accountNote?.setSupporting(getString(when {accountChanged->R.string.diag_account_changed;cleanup.pending&&accountReady->R.string.diag_account_pending;accountReady->R.string.diag_account_on;else->R.string.diag_account_off}))
        automaticNote?.text=if(state.connected&&accountReady)thresholdText ?: getString(R.string.history_loading) else getString(R.string.experiment_auto_setup)
        clean?.text=getString(if(cleanup.pending)R.string.cleanup_check_pending else R.string.cleanup_now)
        clean?.visibility=if(accountReady||cleanup.pending)View.VISIBLE else View.GONE
        clean?.isEnabled=idle&&accountReady
        automatic?.isEnabled=idle&&accountReady;restoreToggle()
        stop?.visibility=if(state.running)View.VISIBLE else View.GONE
        reviewed?.visibility=if(cleanup.pending&&!state.running)View.VISIBLE else View.GONE
        evidence?.setSupporting(if(state.seen.isEmpty())getString(R.string.photos_probe_no_evidence) else listOf("account_entry" to R.string.photos_probe_seen_account,"cleanup_entry" to R.string.photos_probe_seen_entry,"confirmation" to R.string.photos_probe_seen_confirmation,"nothing_to_free" to R.string.photos_probe_seen_empty,"releasing" to R.string.photos_probe_seen_progress,"completed" to R.string.photos_probe_seen_completed).filter {it.first in state.seen}.joinToString(" · ") {getString(it.second).removePrefix("• ")})
    }
}
