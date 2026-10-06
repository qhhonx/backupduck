package app.backupduck

import android.Manifest
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.view.WindowManager
import android.widget.*
import androidx.activity.OnBackPressedCallback
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.navigation.NavigationBarView
import com.google.android.material.materialswitch.MaterialSwitch
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.*
import org.json.JSONObject

class MainActivity : AppCompatActivity() {
    private lateinit var pairingUI:PairingUI

    private val history: HistoryModel by viewModels()
    private val recentHistory = HistoryModel()
    private var lastRecentRefresh = 0L
    private val receiverRoot get() = "$filesDir/receiver"
    private var selectedPage = 1
    private lateinit var navigation: BottomNavigationView
    internal lateinit var receiverHome: ReceiverHome
        private set
    private lateinit var storagePage: StoragePage
    private lateinit var historyPage: HistoryPage
    private lateinit var devicePanels: DevicePanels

    private val scanner = registerForActivityResult(ScanContract()) { result ->
        pairingUI.scanned(result.contents)
    }
    private val originalArchive = registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/zip")) { uri ->
        if (uri != null) exportOriginals(uri)
    }
    private val exportLogs = registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) lifecycleScope.launch {
            reportBusy()
            val result = withContext(Dispatchers.IO) { runCatching {
                val data = NativeBridge.request(JSONObject().put("op", "receiver_logs").put("root", receiverRoot)).toString().toByteArray(Charsets.UTF_8)
                checkNotNull(contentResolver.openOutputStream(uri, "wt")).use { it.write(data) }
            } }
            reportResult(result.isSuccess)
        }
    }
    private val exportGalleryReceipts = registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) lifecycleScope.launch {
            reportBusy()
            val result = withContext(Dispatchers.IO) { runCatching {
                val bytes = GalleryReceiptExport.create(this@MainActivity, receiverRoot).toString().toByteArray(Charsets.UTF_8)
                checkNotNull(contentResolver.openOutputStream(uri, "wt")).use { it.write(bytes) }
            } }
            reportResult(result.isSuccess)
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        if(Build.VERSION.SDK_INT<33) getSharedPreferences("appearance",MODE_PRIVATE).getString("language",null)?.let {
            AppCompatDelegate.setApplicationLocales(androidx.core.os.LocaleListCompat.forLanguageTags(it))
        }
        super.onCreate(savedInstanceState)
        RelayMaintenance.schedule(this)
        devicePanels = DevicePanels(this) {if(::receiverHome.isInitialized) receiverHome.render(ReceiverState.snapshot.value,devicePanels.name,false)}
        pairingUI=PairingUI(this,::beginReceiving) {
            scanner.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setPrompt(getString(R.string.receiver_scan_prompt)).setBeepEnabled(false).setBarcodeImageEnabled(false).setOrientationLocked(false))
        }
        selectedPage = savedInstanceState?.getInt("page", 1) ?: 1
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(getColor(R.color.duck_surface)) }
        val toolbar = MaterialToolbar(this).apply {
            title = getString(R.string.nav_receive); setTitleTextAppearance(this@MainActivity,R.style.DuckToolbarTitle)
            setBackgroundColor(getColor(R.color.duck_surface)); contentInsetStartWithNavigation=dp(16)
            menu.add(0,100,0,R.string.receiver_help_title).apply {
                setIcon(R.drawable.ic_info)
                iconTintList=android.content.res.ColorStateList.valueOf(getColor(R.color.duck_text_secondary))
                setShowAsAction(android.view.MenuItem.SHOW_AS_ACTION_ALWAYS)
            }
            setOnMenuItemClickListener { if(selectedPage==2) historyPage.showFilters() else openHelp();true }
        }
        root.addView(toolbar, LinearLayout.LayoutParams(-1, dp(56)))
        root.addView(duckRule())
        val host = FrameLayout(this)
        root.addView(host, LinearLayout.LayoutParams(-1, 0, 1f))
        historyPage = HistoryPage(this, history, receiverRoot)
        storagePage = StoragePage(this, receiverRoot, export = {
            showArchiveIntro {originalArchive.launch("BackupDuck-originals-${System.currentTimeMillis()}.zip")}
        }, totals = { counts ->
            receiverHome.totals(counts.getInt("published"),counts.getInt("total"),counts.optInt("failed"))
            historyPage.totals(counts.getInt("total"),counts.getInt("published"))
        })
        val pages = listOf(receiverPage(), historyPage, storagePage.view, settingsPage())
        pages.forEach { host.addView(it, FrameLayout.LayoutParams(-1, -1)) }
        val titles = listOf(R.string.nav_receive, R.string.nav_transfers, R.string.nav_storage, R.string.nav_settings)
        val icons = listOf(R.drawable.ic_receiver, R.drawable.ic_transfers, R.drawable.ic_storage, R.drawable.ic_settings)
        navigation = BottomNavigationView(this).apply {
            id = R.id.main_navigation
            labelVisibilityMode = NavigationBarView.LABEL_VISIBILITY_LABELED
            isItemHorizontalTranslationEnabled = false
            setBackgroundColor(getColor(R.color.duck_subtle)); elevation=0f
            itemIconSize=dp(22)
            itemActiveIndicatorColor=android.content.res.ColorStateList.valueOf(getColor(R.color.duck_action_background))
            itemActiveIndicatorWidth=dp(56);itemActiveIndicatorHeight=dp(32)
            itemPaddingTop=dp(8);itemPaddingBottom=dp(12)
            titles.forEachIndexed { index, title -> menu.add(0, index + 1, index, title).setIcon(icons[index]) }
            setOnItemSelectedListener { item ->
                selectedPage = item.itemId
                toolbar.setTitle(titles[selectedPage - 1])
                toolbar.menu.findItem(100).apply { isVisible=selectedPage<=2;setIcon(if(selectedPage==2) R.drawable.ic_more else R.drawable.ic_info) }
                pages.forEachIndexed { index, page -> page.visibility = if (index + 1 == selectedPage) View.VISIBLE else View.GONE }
                if (selectedPage == 3) storagePage.refresh(force = true)
                true
            }
        }
        root.addView(duckRule())
        root.addView(navigation, LinearLayout.LayoutParams(-1, if(resources.configuration.fontScale>1.3f) -2 else dp(80)))
        setContentView(root)
        navigation.selectedItemId = selectedPage
        handleDestination(intent)
        storagePage.refresh(force = true, includeDetails = selectedPage == 3)
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (selectedPage != 1) navigation.selectedItemId = 1 else finish()
            }
        })
        lifecycleScope.launch {
            if (history.state.value.items.isEmpty()) history.select(receiverRoot)
            recentHistory.select(receiverRoot)
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch { history.state.collect { historyPage.render(it) } }
                launch { ReceiverState.snapshot.collect(::renderReceiver) }
                launch { recentHistory.state.collect { state ->
                    receiverHome.history(state)
                } }
                launch {
                    while (isActive) {
                        devicePanels.refresh()
                        renderReceiver(ReceiverState.snapshot.value)
                        if (selectedPage == 1 && SystemClock.elapsedRealtime() - lastRecentRefresh > 8_000) {
                            lastRecentRefresh = SystemClock.elapsedRealtime()
                            recentHistory.refreshVisible(receiverRoot, 0)
                        }
                        if (selectedPage == 2) history.refreshVisible(receiverRoot, historyPage.firstVisible())
                        if (selectedPage == 3) storagePage.refresh()
                        delay(2_000)
                    }
                }
            }
        }
    }
    override fun onNewIntent(next:Intent) {super.onNewIntent(next);setIntent(next);handleDestination(next)}
    private fun handleDestination(next:Intent) {
        when(next.getStringExtra("destination")) {
            "receive"->navigation.selectedItemId=1
            "transfers"->navigation.selectedItemId=2
            "storage"->navigation.selectedItemId=3
            "settings"->navigation.selectedItemId=4
        }
        when(next.getStringExtra("surface")) {
            "pairing"->choosePairing()
            "storage-limits"->showStorageControls(StorageSection.LIMITS) {storagePage.refresh(force=true)}
            "retention"->storagePage.showRetention()
            "archive"->showArchiveIntro {originalArchive.launch("BackupDuck-originals-${System.currentTimeMillis()}.zip")}
            "report"->showReportExport(false)
        }
        next.removeExtra("surface");next.removeExtra("destination")
    }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putInt("page", selectedPage)
        super.onSaveInstanceState(outState)
    }
    override fun onStart() {
        super.onStart()
        if (ReceiverPreferences.enabled(this)) startReceiverService()
        val updates = AppUpdates.preferences(this)
        val now = System.currentTimeMillis()
        if (!packageName.endsWith(".validation") && updates.getBoolean("automatic", true) && now - updates.getLong("checked", 0) > 86_400_000L) {
            updates.edit().putLong("checked", now).apply()
            lifecycleScope.launch {
                val next = withContext(Dispatchers.IO) { runCatching { AppUpdates.latest(this@MainActivity) }.getOrNull() }
                if (next != null && !isFinishing && lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                    duckAcknowledge(getString(R.string.updates_available,next.version)).setAction(R.string.updates_title) {startActivity(Intent(this@MainActivity,UpdatesActivity::class.java))}
                }
            }
        }
    }
    private fun receiverPage(): View {
        receiverHome=ReceiverHome(this,::choosePairing,{pairingUI.iphone()},{pairingUI.mac()},
            {navigation.selectedItemId=2},::pauseReceiving) {
            receiverProblem(ReceiverState.snapshot.value)?.let { problem -> when(problem.recovery) {
                ReceiverRecovery.NETWORK -> runCatching { startActivity(Intent(android.provider.Settings.ACTION_WIFI_SETTINGS)) }.onFailure { openHelp(ReceiverHelpTopic.CONNECTION) }
                ReceiverRecovery.STORAGE -> navigation.selectedItemId=3
                ReceiverRecovery.RESUME -> beginReceiving()
                ReceiverRecovery.CONNECTION_HELP -> openHelp(ReceiverHelpTopic.CONNECTION)
                ReceiverRecovery.DIAGNOSTICS_HELP -> openHelp(ReceiverHelpTopic.RECOVERY)
            } } ?: openSettings()
        }
        return receiverHome.view
    }
    private fun choosePairing() {pairingUI.choose()}
    private fun pauseReceiving() {
        lifecycleScope.launch {
            val paused=ReceiverPreferences.paused(this@MainActivity)
            val result=withContext(Dispatchers.IO) {runCatching {
                ReceiverPreferences.setPaused(this@MainActivity,!paused)
                try {ReceiverHolds.sync(this@MainActivity)} catch(error:Exception) {ReceiverPreferences.setPaused(this@MainActivity,paused);throw error}
            }}
            renderReceiver(ReceiverState.snapshot.value)
            if(result.isFailure) showActionFailure(R.string.settings_failed,::pauseReceiving)
        }
    }
    private fun settingsPage(): View = scrollPage { panel ->
        panel.setPadding(dp(16),dp(8),dp(16),dp(24))
        panel.addView(duckText(getString(R.string.duck_settings_intro),13,true),LinearLayout.LayoutParams(-1,-2).apply { bottomMargin=dp(24) })
        val receive=duckGroup(panel,getString(R.string.duck_receive_settings))
        duckSetting(receive,getString(R.string.duck_restore),getString(if(Build.VERSION.SDK_INT>=35) R.string.receiver_restore_note_modern else R.string.duck_restore_note),
            duckSwitch(ReceiverPreferences.restore(this)) { ReceiverPreferences.setRestore(this,it) })
        val thermal=duckText("",13,true)
        fun thermalValue() {thermal.text=if(ReceiverThermalSettings.enabled(this)) "${ReceiverThermalSettings.threshold(this)} °C" else getString(R.string.duck_off)}
        thermalValue()
        duckSetting(receive,getString(R.string.duck_thermal),getString(R.string.duck_thermal_note),thermal) {showThermalSettings {thermalValue()}}
        val conversion=duckText("",13,true)
        fun conversionValue() {conversion.text=getString(if(MotionConversionSettings.enabled(this)) R.string.duck_on else R.string.duck_off)}
        conversionValue()
        duckSetting(receive,getString(R.string.duck_conversion),getString(R.string.duck_conversion_note),conversion) {showConversionSettings {conversionValue()}}
        val browser=duckGroup(panel,getString(R.string.duck_browser))
        duckSetting(browser,getString(R.string.dashboard_section),getString(R.string.duck_access_note),
            action={startActivity(Intent(this,BrowserManagementActivity::class.java))})
        val device=duckGroup(panel,getString(R.string.duck_device_appearance))
        devicePanels.compactSettings(device)
        val appearanceValue=duckText(getString(when(delegate.localNightMode) { AppCompatDelegate.MODE_NIGHT_YES -> R.string.appearance_dark;AppCompatDelegate.MODE_NIGHT_NO -> R.string.appearance_light;else -> R.string.appearance_system }),13,true)
        duckSetting(device,getString(R.string.settings_appearance),control=appearanceValue) {
            val modes=listOf(AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM,AppCompatDelegate.MODE_NIGHT_NO,AppCompatDelegate.MODE_NIGHT_YES)
            val labels=listOf(R.string.appearance_system,R.string.appearance_light,R.string.appearance_dark)
            val sheet=DuckSheet(this,getString(R.string.settings_appearance))
            val choices=duckGroup(sheet.body)
            labels.forEachIndexed { i,label -> duckSetting(choices,getString(label),control=if(delegate.localNightMode==modes[i]) duckPill(getString(R.string.duck_selected),R.color.duck_action,R.color.duck_action_background) else duckText("",13)) {
                sheet.dismiss();getSharedPreferences("appearance",MODE_PRIVATE).edit().putInt("mode",modes[i]).apply();delegate.localNightMode=modes[i]
            } };sheet.show()
        }
        val language=if(Build.VERSION.SDK_INT>=33) getSystemService(android.app.LocaleManager::class.java).applicationLocales.toLanguageTags() else AppCompatDelegate.getApplicationLocales().toLanguageTags()
        duckSetting(device,getString(R.string.duck_language),control=duckText(if(language.startsWith("zh")) "简体中文" else if(language.startsWith("en")) "English" else getString(R.string.appearance_system),13,true)) {
            val sheet=DuckSheet(this,getString(R.string.duck_language))
            val choices=duckGroup(sheet.body)
            listOf("" to getString(R.string.appearance_system),"zh-CN" to "简体中文","en" to "English").forEach { (tag,label) -> duckSetting(choices,label,control=if(language.equals(tag,true))duckPill(getString(R.string.duck_selected),R.color.duck_action,R.color.duck_action_background) else duckText("",13)) {
                sheet.dismiss();getSharedPreferences("appearance",MODE_PRIVATE).edit().putString("language",tag).apply();AppCompatDelegate.setApplicationLocales(androidx.core.os.LocaleListCompat.forLanguageTags(tag))
            } };sheet.show()
        }
        val help=duckGroup(panel,getString(R.string.duck_help_about))
        duckSetting(help,getString(R.string.receiver_help_title),action={openHelp()})
        duckSetting(help,getString(R.string.updates_title),getString(R.string.settings_version,packageManager.getPackageInfo(packageName,0).versionName ?: ""),action={startActivity(Intent(this,UpdatesActivity::class.java))})
        duckSetting(help,getString(R.string.settings_diagnostics),action=::showDiagnostics)
        duckSetting(help,"备份鸭 / BackupDuck",getString(R.string.duck_brand_note),duckPill(packageManager.getPackageInfo(packageName,0).versionName ?: ""))
    }
    internal fun showDiagnostics() {
        val page=DuckPage(this,getString(R.string.settings_diagnostics))
        val group=duckGroup(page.body)
        duckSetting(group,getString(R.string.device_known_senders)) {devicePanels.showPeers()}
        duckSetting(group,getString(R.string.logs_retention_settings)) {showStorageControls(StorageSection.LOGS) {}}
        duckSetting(group,getString(R.string.logs_export)) {showReportExport(false)}
        duckSetting(group,getString(R.string.gallery_receipts_export)) {showReportExport(true)}
        duckSetting(group,getString(R.string.experiments_title),getString(R.string.experiments_description)) {startActivity(Intent(this,ExperimentsActivity::class.java))}
        duckSetting(group,getString(R.string.receiver_stop),getString(R.string.duck_stop_summary)) {
            duckConfirm(R.string.receiver_stop,R.string.duck_stop_service_intro,R.string.receiver_stop,true,notice=R.string.duck_reset_unchanged) {dialog ->
                ReceiverPreferences.setEnabled(this,false);stopService(Intent(this,ReceiverService::class.java));dialog.dismiss();page.dismiss();renderReceiver(ReceiverState.snapshot.value)
            }
        }
        page.show()
    }
    private var reportPage:DuckPage?=null
    private var reportGallery=false
    private fun showReportExport(gallery:Boolean) {
        val page=DuckPage(this,getString(R.string.duck_export_title));reportPage=page;reportGallery=gallery
        val group=duckGroup(page.body)
        duckSetting(group,getString(if(gallery) R.string.gallery_receipts_export else R.string.logs_export),getString(if(gallery) R.string.duck_report_gallery else R.string.duck_report_logs),duckText("",13))
        duckNotice(page.body,getString(R.string.duck_export_report_note))
        page.body.addView(duckButton(getString(R.string.duck_choose_location),true) {
            if(gallery) exportGalleryReceipts.launch("BackupDuck-gallery-receipts.json") else exportLogs.launch("BackupDuck-diagnostics.json")
        },LinearLayout.LayoutParams(-1,-2));page.show()
    }
    private fun reportBusy() {reportPage?.takeIf {it.isShowing}?.body?.let {it.removeAllViews();duckNotice(it,getString(R.string.duck_exporting_report))}}
    private fun reportResult(success:Boolean) {
        val page=reportPage?.takeIf {it.isShowing} ?: return
        page.body.removeAllViews()
        if(success) {duckNotice(page.body,getString(R.string.duck_export_report_success));duckAcknowledge(getString(R.string.duck_export_report_success),page.body)}
        else {
            duckProblem(page.body,getString(R.string.duck_export_report_failure))
            page.body.addView(duckButton(getString(R.string.duck_retry)) {
                if(reportGallery)exportGalleryReceipts.launch("BackupDuck-gallery-receipts.json") else exportLogs.launch("BackupDuck-diagnostics.json")
            },LinearLayout.LayoutParams(-1,-2))
        }
    }
    internal fun showActionFailure(message:Int,retry:()->Unit) {
        val sheet=DuckSheet(this,getString(R.string.duck_operation_failed));duckProblem(sheet.body,getString(message))
        sheet.body.addView(duckButton(getString(R.string.duck_retry)) {sheet.dismiss();retry()});sheet.show()
    }
    internal val receiverDeviceName get()=devicePanels.name ?: Build.MODEL
    internal fun openConnection() {navigation.selectedItemId=1;choosePairing()}
    internal fun openTransfers(failed:Boolean=false) {
        navigation.selectedItemId=2
        if(failed) lifecycleScope.launch {history.select(receiverRoot,filter="failed")}
    }
    internal fun openSettings() { navigation.selectedItemId = 4 }
    private fun showDashboardAccess() {DashboardAccessUI(this).access()}
    private fun openHelp(topic: ReceiverHelpTopic? = null) {
        startActivity(Intent(this, ReceiverHelpActivity::class.java).apply { topic?.let { putExtra("topic", it.key) } })
    }
    private fun beginReceiving() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        val wasEnabled = ReceiverPreferences.enabled(this)
        ReceiverPreferences.setEnabled(this, true)
        if (!wasEnabled || ReceiverState.snapshot.value.phase != "ready")
            ReceiverState.mutable.value = ReceiverState.snapshot.value.copy(phase = "starting", error = null)
        startReceiverService()
    }
    private fun startReceiverService() {
        runCatching { startForegroundService(Intent(this, ReceiverService::class.java)) }.onFailure {
            ReceiverState.mutable.value = ReceiverState.snapshot.value.copy(phase = "waiting", error = "foreground_start_blocked")
        }
    }
    private fun renderReceiver(state:ReceiverSnapshot) {
        receiverHome.render(state,devicePanels.name,false)
        historyPage.renderActivity(state)
        if(::pairingUI.isInitialized)pairingUI.update(state)
    }
    internal fun openPhotos() {
        val launch = packageManager.getLaunchIntentForPackage("com.google.android.apps.photos")
        if (launch != null) {
            try { startActivity(launch); return }
            catch (_: android.content.ActivityNotFoundException) { /* Removed since lookup. */ }
        }
        showActionFailure(R.string.receiver_photos_missing,::openPhotos)
    }
}
