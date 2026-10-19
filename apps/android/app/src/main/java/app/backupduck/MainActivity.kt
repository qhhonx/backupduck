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
    private val currentSettingValues=mutableListOf<Pair<TextView,()->String>>()
    private lateinit var pairingUI:PairingUI

    private val history: HistoryModel by viewModels()
    private val recentHistory = HistoryModel()
    /** Attention items for the proposed Received photos page; [history] holds its timeline. */
    private val attentionHistory = HistoryModel()
    private val receiverRoot get() = "$filesDir/receiver"
    private var selectedPage = 1
    private lateinit var navigation: BottomNavigationView
    private var experimentsDiscoveryDot: View? = null
    private var experimentsDiscoveryTitle: TextView? = null
    internal lateinit var receiverHome: ReceiverHomeSurface
        private set
    private lateinit var storagePage: StoragePage
    private lateinit var historyPage: HistoryPage
    private var receivedPhotos: ReceivedPhotosPage? = null
    private lateinit var titleBar: MaterialToolbar
    internal lateinit var devicePanels: DevicePanels
    private var proposedRefresh: (() -> Unit)? = null

    /** Set while the proposed connect flow waits for the camera; the legacy pairing sheet gets the result otherwise. */
    private var connectScan: ((String?) -> Unit)? = null
    private val scanner = registerForActivityResult(ScanContract()) { result ->
        connectScan?.let { connectScan = null; it(result.contents) } ?: pairingUI.scanned(result.contents)
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
        // The redesigned pages (design/visual-language.md) use the generated Material 3 scheme.
        if (look) {
            DuckLook.applyScheme(this)
            window.statusBarColor = getColor(R.color.duck_role_background)
            window.navigationBarColor = getColor(R.color.duck_m3_surface_container)
        }
        RelayMaintenance.schedule(this)
        devicePanels = DevicePanels(this) {
            if(::receiverHome.isInitialized) receiverHome.render(ReceiverState.snapshot.value,devicePanels.name,false)
            if(::historyPage.isInitialized) historyPage.render(history.state.value)
            receivedPhotos?.render(history.state.value)
            proposedRefresh?.invoke()
        }
        pairingUI=PairingUI(this,::beginReceiving) {
            scanner.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setPrompt(getString(R.string.receiver_scan_prompt)).setBeepEnabled(false).setBarcodeImageEnabled(false).setCaptureActivity(ReceiverScanActivity::class.java).setOrientationLocked(true))
        }
        selectedPage = savedInstanceState?.getInt("page", 1) ?: 1
        val canvas = getColor(if (look) R.color.duck_role_background else R.color.duck_surface)
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(canvas) }
        val toolbar = MaterialToolbar(this).apply {
            title = getString(R.string.nav_receive)
            // V2: the page title is Headline medium.
            if (look) { setTitleTextAppearance(this@MainActivity, com.google.android.material.R.style.TextAppearance_Material3_HeadlineMedium); setTitleTextColor(getColor(R.color.duck_role_primary_text)) }
            else setTitleTextAppearance(this@MainActivity,R.style.DuckToolbarTitle)
            setBackgroundColor(canvas); contentInsetStartWithNavigation=dp(16)
            menu.add(0,100,0,R.string.receiver_help_title).apply {
                isVisible=false
                setIcon(R.drawable.ic_info)
                iconTintList=android.content.res.ColorStateList.valueOf(getColor(R.color.duck_text_secondary))
                setShowAsAction(android.view.MenuItem.SHOW_AS_ACTION_ALWAYS)
            }
            setOnMenuItemClickListener {if(selectedPage==2&&receivedPhotos==null)historyPage.showFilters();true}
        }
        titleBar = toolbar
        root.addView(toolbar, LinearLayout.LayoutParams(-1, dp(if (look) 64 else 56)))
        if (!look) root.addView(duckRule())
        val host = FrameLayout(this)
        root.addView(host, LinearLayout.LayoutParams(-1, 0, 1f))
        historyPage = HistoryPage(this, history, receiverRoot)
        storagePage = StoragePage(this, receiverRoot, export = {
            showArchiveIntro {originalArchive.launch("BackupDuck-originals-${System.currentTimeMillis()}.zip")}
        }, totals = { counts ->
            receiverHome.totals(counts.getInt("published"),counts.getInt("total"),counts.optInt("failed"))
            historyPage.totals(counts.getInt("total"),counts.getInt("published"))
        })
        if (ReceiverEnvironment.proposedDesign) receivedPhotos = receivedPhotosPage()
        val pages = listOf(receiverPage(), receivedPhotos?.view ?: historyPage, storagePage.view, if (ReceiverEnvironment.proposedDesign) proposedDesignPage() else settingsPage())
        pages.forEach { host.addView(it, FrameLayout.LayoutParams(-1, -1)) }
        val titles = listOf(R.string.nav_receive, R.string.nav_transfers, R.string.nav_storage, R.string.nav_settings)
        // design/navigation.md: Receive, Photos, Settings. Storage opens from Settings and the hub.
        val proposed = ReceiverEnvironment.proposedDesign
        val pageTitles = if (receivedPhotos != null) titles.toMutableList().apply { set(1, R.string.nav_photos) } else titles
        val navTitles = if (proposed) titles.toMutableList().apply { set(1, R.string.nav_photos) } else titles
        val icons = listOf(R.drawable.ic_receiver, R.drawable.ic_transfers, R.drawable.ic_storage, R.drawable.ic_settings)
        navigation = BottomNavigationView(this).apply {
            id = R.id.main_navigation
            labelVisibilityMode = NavigationBarView.LABEL_VISIBILITY_LABELED
            isItemHorizontalTranslationEnabled = false
            setBackgroundColor(getColor(if (look) R.color.duck_m3_surface_container else R.color.duck_subtle)); elevation=0f
            itemIconSize=dp(22)
            itemActiveIndicatorColor=android.content.res.ColorStateList.valueOf(getColor(if (look) R.color.duck_m3_secondary_container else R.color.duck_action_background))
            itemActiveIndicatorWidth=dp(56);itemActiveIndicatorHeight=dp(32)
            duckNavigation(this)
            navTitles.forEachIndexed { index, title -> if (!(proposed && index == 2)) menu.add(0, index + 1, index, title).setIcon(if (proposed && index == 1) R.drawable.ic_photo else icons[index]) }
            setOnItemSelectedListener { item ->
                selectedPage = item.itemId
                toolbar.setTitle(pageTitles[selectedPage - 1])
                toolbar.menu.findItem(100).apply {isVisible=selectedPage==2&&receivedPhotos==null;setIcon(R.drawable.ic_more);setTitle(R.string.duck_advanced_filters)}
                pages.forEachIndexed { index, page -> page.visibility = if (index + 1 == selectedPage) View.VISIBLE else View.GONE }
                if (selectedPage == 3) storagePage.refresh(force = true)
                true
            }
        }
        if (!look) root.addView(duckRule())
        root.addView(navigation, LinearLayout.LayoutParams(-1, if(resources.configuration.fontScale>1.3f) -2 else dp(80)))
        setContentView(root)
        navigation.selectedItemId = selectedPage
        refreshDiscovery()
        handleDestination(intent)
        // A theme change or rotation recreates the activity; the connect screen or device page stays open.
        when (savedInstanceState?.getString("connect.surface")) { "devices" -> openDevices(); "pairing" -> openConnect(); "connect-mac" -> openConnect(mac = true); "storage" -> openStorage() }
        storagePage.refresh(force = true, includeDetails = selectedPage == 3)
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (selectedPage != 1) navigation.selectedItemId = 1 else finish()
            }
        })
        lifecycleScope.launch {
            val filtered = history.state.value.let { it.filter != "all" || it.kind != "all" || it.sender != null }
            if (history.state.value.items.isEmpty() || (receivedPhotos != null && filtered)) history.select(receiverRoot, filter = "all", kind = "all", sender = null)
            recentHistory.select(receiverRoot)
            if (receivedPhotos != null) attentionHistory.select(receiverRoot, filter = "failed")
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch { history.state.collect { historyPage.render(it); receivedPhotos?.render(it) } }
                receivedPhotos?.let { page -> launch { attentionHistory.state.collect(page::attention) } }
                launch { ReceiverState.snapshot.collect(::renderReceiver) }
                launch {
                  var knownProgressIDs=emptySet<String>()
                  var knownStates=emptyMap<String,String?>()
                  ReceiverProgress.snapshot.collect {progress ->
                    historyPage.progress(progress)
                    receivedPhotos?.progress(progress)
                    receiverHome.progress(progress)
                    val added=progress.keys-knownProgressIDs
                    val states=progress.mapValues {it.value.processing}
                    val statusChanged=states.any {(id,value)->value!=knownStates[id]}
                    knownStates=states
                    knownProgressIDs=progress.keys.toSet()
                    if(added.isNotEmpty()||statusChanged) {
                        // Both pages must reconcile the same result even while one tab is hidden.
                        recentHistory.refreshVisible(receiverRoot,0)
                        history.refreshVisible(receiverRoot,recordsFirstVisible())
                        if(receivedPhotos!=null) attentionHistory.refreshVisible(receiverRoot,0)
                    }
                  }
                }
                launch { recentHistory.state.collect { state ->
                    receiverHome.history(state)
                } }
                launch {
                    while (isActive) {
                        devicePanels.refresh()
                        renderReceiver(ReceiverState.snapshot.value)
                        if (selectedPage == 1) {
                            recentHistory.refreshVisible(receiverRoot, 0)
                        }
                        if (selectedPage == 2) {
                            history.refreshVisible(receiverRoot, recordsFirstVisible())
                            if (receivedPhotos != null) attentionHistory.refreshVisible(receiverRoot, 0)
                        }
                        if (selectedPage == 3) storagePage.refresh()
                        delay(2_000)
                    }
                }
            }
        }
    }
    override fun onDestroy() {
        // Recreated for a theme change or rotation: onCreate reopens what was showing.
        if (isChangingConfigurations) { connectPage?.dismiss(); devicesPage?.dismiss(); storageScreen?.dismiss() }
        super.onDestroy()
    }
    override fun onNewIntent(next:Intent) {super.onNewIntent(next);setIntent(next);handleDestination(next)}
    override fun onResume() {
        super.onResume()
        if (::navigation.isInitialized) refreshDiscovery()
    }
    private fun refreshDiscovery() {
        val unseen = FeatureDiscovery(this).isUnseen(FeatureDiscovery.PHOTOS_CLEANUP)
        experimentsDiscoveryDot?.visibility = if (unseen) View.VISIBLE else View.GONE
        experimentsDiscoveryTitle?.contentDescription = if (unseen)
            getString(R.string.discovery_entry_label, getString(R.string.experiments_title)) else null
        if (unseen) navigation.getOrCreateBadge(4).apply {
            clearNumber()
            backgroundColor = getColor(R.color.duck_brand_accent)
            setContentDescriptionNumberless(getString(R.string.discovery_available))
            isVisible = true
        } else navigation.removeBadge(4)
    }
    private fun handleDestination(next:Intent) {
        when(next.getStringExtra("destination")) {
            "receive"->navigation.selectedItemId=1
            "transfers"->navigation.selectedItemId=2
            "storage"->openStorage()
            "settings"->navigation.selectedItemId=4
        }
        when(next.getStringExtra("surface")) {
            "pairing"->choosePairing()
            "connect-mac"->openConnect(mac=true)
            "devices"->openDevices()
            "storage-limits"->showStorageControls(StorageSection.LIMITS) {storagePage.refresh(force=true)}
            "retention"->storagePage.showRetention()
            "archive"->showArchiveIntro {originalArchive.launch("BackupDuck-originals-${System.currentTimeMillis()}.zip")}
            "report"->showReportExport(false)
        }
        next.removeExtra("surface");next.removeExtra("destination")
    }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putInt("page", selectedPage)
        outState.putString("connect.surface", when { connectPage?.isShowing == true -> connectPage?.flow?.surface; devicesPage?.isShowing == true -> "devices"; storageScreen?.isShowing == true -> "storage"; else -> null })
        super.onSaveInstanceState(outState)
    }
    override fun onStart() {
        super.onStart()
        currentSettingValues.forEach {(view,value)->val next=value();if(view.text.toString()!=next)view.text=next}
        if (ReceiverPreferences.enabled(this)) startReceiverService()
        val updates = AppUpdates.preferences(this)
        val now = System.currentTimeMillis()
        if (ReceiverEnvironment.checksUpdates && !packageName.endsWith(".validation") && updates.getBoolean("automatic", true) && now - updates.getLong("checked", 0) > 86_400_000L) {
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
        if (ReceiverEnvironment.proposedDesign) {
            val hubActions = ReceiverHub.Actions(start = ::beginReceiving, connect = ::choosePairing, toggleReceive = ::pauseReceiving,
                records = ::openTransfers,
                openWifi = { runCatching { startActivity(Intent(android.provider.Settings.ACTION_WIFI_SETTINGS)) }.onFailure { openHelp(ReceiverHelpTopic.CONNECTION) } },
                openPhotos = ::openPhotos, openCleanup = ::openCleanup, devices = ::openDevices,
                recovery = { receiverProblem(ReceiverState.snapshot.value)?.let { recover(it.recovery) } })
            receiverHome = ReceiverHub(this, hubActions)
            return receiverHome.view
        }
        receiverHome=ReceiverHome(this,::choosePairing,{pairingUI.iphone()},{pairingUI.mac()},
            {navigation.selectedItemId=2},{lifecycleScope.launch {recentHistory.refreshVisible(receiverRoot,0)}},::pauseReceiving) {
            receiverProblem(ReceiverState.snapshot.value)?.let { recover(it.recovery) } ?: openSettings()
        }
        return receiverHome.view
    }
    /** The redesigned pages and their components (DuckLook.kt); the current pages keep today's look. */
    private val look get() = ReceiverEnvironment.proposedDesign
    private fun recordsFirstVisible() = receivedPhotos?.firstVisible() ?: historyPage.firstVisible()
    /** The proposed records page (design/records.md); [history] stays on the "all" filter there. */
    private fun receivedPhotosPage() = ReceivedPhotosPage(this, ReceivedPhotosPage.Actions(
        more = { lifecycleScope.launch { history.more(receiverRoot) } },
        reload = { lifecycleScope.launch { history.select(receiverRoot, filter = "all", kind = "all", sender = null); attentionHistory.select(receiverRoot, filter = "failed") } },
        retryAll = { done -> retryProcessing(null, done) },
        retry = { item, done -> retryProcessing(item.id, done) },
        connect = ::openConnection))
    private fun retryProcessing(id: String?, done: (Boolean) -> Unit) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) { runCatching { NativeBridge.request(JSONObject().put("op", "retry_processing").apply { id?.let { put("id", it) } }) } }
            done(result.isSuccess)
            if (result.isSuccess) { attentionHistory.refreshVisible(receiverRoot, 0); history.refreshVisible(receiverRoot, recordsFirstVisible()); recentHistory.refreshVisible(receiverRoot, 0) }
        }
    }
    internal fun showPhoto(item: HistoryItem) { receivedPhotos?.showDetail(item) }
    private fun recover(recovery: ReceiverRecovery) = when(recovery) {
        ReceiverRecovery.NETWORK -> runCatching { startActivity(Intent(android.provider.Settings.ACTION_WIFI_SETTINGS)) }.onFailure { openHelp(ReceiverHelpTopic.CONNECTION) }.let {}
        ReceiverRecovery.STORAGE -> openStorage()
        ReceiverRecovery.RESUME -> beginReceiving()
        ReceiverRecovery.CONNECTION_HELP -> openHelp(ReceiverHelpTopic.CONNECTION)
        ReceiverRecovery.DIAGNOSTICS_HELP -> openHelp(ReceiverHelpTopic.RECOVERY)
    }
    private fun choosePairing() {if(ReceiverEnvironment.proposedDesign) openConnect() else pairingUI.choose()}
    private var connectPage:ConnectPage?=null
    /** The one connect flow (design/pixel-connect.md) for the hub, the device page and the Received photos empty state. */
    private fun openConnect(mac:Boolean=false) {
        connectPage?.dismiss()
        connectPage=ConnectPage(this,::scanCode,::beginReceiving) {connectPage=null;devicePanels.refresh();devicesPage?.reload()}.also {
            it.show();if(mac) it.flow.showMac(null) else it.flow.showCode()
        }
    }
    private var devicesPage:DevicesPage?=null
    private fun openDevices() {devicesPage=DevicesPage(this,{openConnect()}) {devicePanels.refresh()}.also {it.show()}}
    private fun scanCode(done:(String?)->Unit) {
        ReceiverEnvironment.scanOverride?.let {it(done);return}
        connectScan=done
        runCatching {scanner.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setPrompt(getString(R.string.connect_mac_title)).setBeepEnabled(false).setBarcodeImageEnabled(false).setCaptureActivity(ReceiverScanActivity::class.java).setOrientationLocked(true))}
            .onFailure {connectScan=null;done(null)}
    }
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
        val receive=duckGroup(panel,getString(R.string.duck_receive_settings))
        receiverSetting(receive,getString(R.string.duck_restore),null,
            duckSwitch(ReceiverPreferences.restore(this)) { ReceiverPreferences.setRestore(this,it) })
        val thermal=duckText("",13,true)
        fun thermalValue() {thermal.text=if(ReceiverThermalSettings.enabled(this)) "${ReceiverThermalSettings.threshold(this)} °C" else getString(R.string.duck_off)}
        thermalValue()
        receiverSetting(receive,getString(R.string.duck_thermal),null,thermal) {showThermalSettings {thermalValue()}}
        val conversion=duckText("",13,true)
        fun conversionValue() {conversion.text=getString(if(MotionConversionSettings.enabled(this)) R.string.duck_on else R.string.duck_off)}
        conversionValue()
        receiverSetting(receive,getString(R.string.duck_conversion),null,conversion) {showConversionSettings {conversionValue()}}
        receiverSetting(receive,getString(R.string.receiver_stop),action=::confirmStopReceiving)
        val browser=duckGroup(panel)
        val browserValue=duckText("",13,true);val browserCurrent={getString(if(ReceiverDashboardSettings.enabled(this))R.string.duck_on else R.string.duck_off)};browserValue.text=browserCurrent();currentSettingValues+=browserValue to browserCurrent
        receiverSetting(browser,getString(R.string.dashboard_section),control=browserValue,action={startActivity(Intent(this,BrowserManagementActivity::class.java))})
        val device=duckGroup(panel,getString(R.string.duck_device_appearance))
        devicePanels.compactSettings(device)
        val appearanceValue=duckText(getString(when(delegate.localNightMode) { AppCompatDelegate.MODE_NIGHT_YES -> R.string.appearance_dark;AppCompatDelegate.MODE_NIGHT_NO -> R.string.appearance_light;else -> R.string.appearance_system }),13,true)
        receiverSetting(device,getString(R.string.settings_appearance),control=appearanceValue) {chooseAppearance()}
        receiverSetting(device,getString(R.string.duck_language),control=duckText(languageLabel(),13,true)) {chooseLanguage()}  // design-exception: legacy settings row, replaced by proposedDesignPage
        recordsAndExports(panel)
        val experiments=duckGroup(panel,getString(R.string.experiments_title))
        val experimentTitle=receiverSetting(experiments,getString(R.string.experiments_title)) {startActivity(Intent(this,ExperimentsActivity::class.java))}
        val words=experimentTitle.parent as LinearLayout
        words.removeView(experimentTitle)
        val discoveryHeading=LinearLayout(this).apply {gravity=android.view.Gravity.CENTER_VERTICAL}
        discoveryHeading.addView(experimentTitle,LinearLayout.LayoutParams(0,-2,1f))
        experimentsDiscoveryDot=duckDiscoveryDot().also {dot ->
            discoveryHeading.addView(dot,LinearLayout.LayoutParams(dp(8),dp(8)).apply {marginStart=dp(8)})
        }
        words.addView(discoveryHeading,0)
        experimentsDiscoveryTitle=experimentTitle
        val help=duckGroup(panel,getString(R.string.receiver_application_help))
        receiverSetting(help,getString(R.string.updates_title),control=duckText(receiverDisplayVersion(),13,true).apply {
            tag="duck.version"
            contentDescription=receiverVersionLabel()
            if(resources.configuration.fontScale<=1.3f) {maxLines=1;ellipsize=android.text.TextUtils.TruncateAt.END}
        },action={startActivity(Intent(this,UpdatesActivity::class.java))})
        receiverSetting(help,getString(R.string.receiver_help_title),action={openHelp()})
    }
    private fun appearanceLabel() = getString(when(delegate.localNightMode) { AppCompatDelegate.MODE_NIGHT_YES -> R.string.appearance_dark;AppCompatDelegate.MODE_NIGHT_NO -> R.string.appearance_light;else -> R.string.appearance_system })
    private fun currentLanguageTag() = if(Build.VERSION.SDK_INT>=33) getSystemService(android.app.LocaleManager::class.java).applicationLocales.toLanguageTags() else AppCompatDelegate.getApplicationLocales().toLanguageTags()
    private fun languageLabel() = currentLanguageTag().let { if(it.startsWith("zh")) "简体中文" else if(it.startsWith("en")) "English" else getString(R.string.appearance_system) }
    private fun chooseAppearance() {
        val modes=listOf(AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM,AppCompatDelegate.MODE_NIGHT_NO,AppCompatDelegate.MODE_NIGHT_YES)
        val labels=listOf(R.string.appearance_system,R.string.appearance_light,R.string.appearance_dark)
        val sheet=DuckSheet(this,getString(R.string.settings_appearance))
        val choices=duckGroup(sheet.body)
        labels.forEachIndexed { i,label -> receiverSetting(choices,getString(label),control=if(delegate.localNightMode==modes[i]) duckPill(getString(R.string.duck_selected),R.color.duck_action,R.color.duck_action_background) else duckText("",13)) {
            sheet.dismiss();getSharedPreferences("appearance",MODE_PRIVATE).edit().putInt("mode",modes[i]).apply();delegate.localNightMode=modes[i]
        } };sheet.show()
    }
    private fun chooseLanguage() {
        val language=currentLanguageTag()
        val sheet=DuckSheet(this,getString(R.string.duck_language))
        val choices=duckGroup(sheet.body)
        listOf("" to getString(R.string.appearance_system),"zh-CN" to "简体中文","en" to "English").forEach { (tag,label) -> receiverSetting(choices,label,control=if(language.equals(tag,true))duckPill(getString(R.string.duck_selected),R.color.duck_action,R.color.duck_action_background) else duckText("",13)) {
            sheet.dismiss();getSharedPreferences("appearance",MODE_PRIVATE).edit().putString("language",tag).apply();AppCompatDelegate.setApplicationLocales(androidx.core.os.LocaleListCompat.forLanguageTags(tag))
        } };sheet.show()
    }
    /** Settings per design/settings.md in Material 3, built from the shared components; shown by the design catalog until migration step 6. */
    private fun proposedDesignPage(): View = scrollPage { panel ->
        panel.setPadding(token(R.dimen.duck_space_medium),token(R.dimen.duck_space_x_small),token(R.dimen.duck_space_medium),token(R.dimen.duck_space_large))
        // Identity header: this Pixel, what it is doing, and Edit to rename it.
        val header=lookCard(panel).apply {orientation=LinearLayout.HORIZONTAL;gravity=android.view.Gravity.CENTER_VERTICAL}
        header.addView(android.widget.ImageView(this).apply {
            setImageResource(R.drawable.ic_receiver);token(R.dimen.duck_space_small).let {setPadding(it,it,it,it)}
            imageTintList=android.content.res.ColorStateList.valueOf(getColor(R.color.duck_m3_on_primary_container))
            background=android.graphics.drawable.GradientDrawable().apply {shape=android.graphics.drawable.GradientDrawable.OVAL;setColor(getColor(R.color.duck_m3_primary_container))}
            importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO
        },LinearLayout.LayoutParams(dp(52),dp(52)).apply {marginEnd=token(R.dimen.duck_space_medium)})
        val words=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL}
        val deviceName=lookText("",com.google.android.material.R.style.TextAppearance_Material3_TitleLarge)
        val status=lookText("",com.google.android.material.R.style.TextAppearance_Material3_BodyMedium,secondary=true)
        words.addView(deviceName);words.addView(status)
        header.addView(words,LinearLayout.LayoutParams(0,-2,1f))
        header.addView(lookButton(getString(R.string.pref_edit),LookButton.TEXT) {devicePanels.rename()})
        lookSection(panel,getString(R.string.pref_section_receive))
        val receive=lookGroup(panel)
        val devices=lookRow(receive,R.drawable.ic_receiver,getString(R.string.pref_devices),"") {openDevices()}
        val storage=lookRow(receive,R.drawable.ic_storage,getString(R.string.pref_storage),"") {openStorage()}
        lookSection(panel,getString(R.string.pref_section_general))
        val general=lookGroup(panel)
        val appearance=lookRow(general,R.drawable.ic_contrast,getString(R.string.pref_appearance),appearanceLabel()) {chooseAppearance()}
        lookRow(general,R.drawable.ic_globe,getString(R.string.pref_language),languageLabel()) {chooseLanguage()}
        lookSection(panel,getString(R.string.pref_section_help))
        val help=lookGroup(panel)
        lookRow(help,R.drawable.ic_help,getString(R.string.pref_help)) {openHelp()}
        // V1: the discovery dot is one of duck yellow's brand moments.
        val dot=View(this).apply {background=android.graphics.drawable.GradientDrawable().apply {shape=android.graphics.drawable.GradientDrawable.OVAL;setColor(getColor(R.color.duck_brand_duck_yellow))}}
        val experiments=lookRow(help,R.drawable.ic_flask,getString(R.string.pref_experiments),trailing=FrameLayout(this).apply {addView(dot,FrameLayout.LayoutParams(dp(8),dp(8),android.view.Gravity.CENTER))}) {startActivity(Intent(this,ExperimentsActivity::class.java))}
        experimentsDiscoveryDot=dot;experimentsDiscoveryTitle=(experiments.parent as LinearLayout).getChildAt(0) as TextView
        val footer=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;gravity=android.view.Gravity.CENTER_HORIZONTAL;setPadding(0,token(R.dimen.duck_space_large),0,0)}
        footer.addView(lookText(getString(R.string.pref_version,receiverDisplayVersion()),com.google.android.material.R.style.TextAppearance_Material3_BodySmall,secondary=true))
        val links=FlowRow(this,0)
        fun link(text:Int,action:()->Unit)=links.addView(lookButton(getString(text),LookButton.TEXT,action=action))
        link(R.string.pref_check_updates) {startActivity(Intent(this@MainActivity,UpdatesActivity::class.java))}
        link(R.string.pref_diagnostics) {showReportExport(false)}
        link(R.string.pref_advanced) {proposedAdvancedPage()}
        footer.addView(links,LinearLayout.LayoutParams(-2,-2))
        panel.addView(footer)
        fun refresh() {
            deviceName.text=devicePanels.name ?: Build.MODEL
            val senders=devicePanels.senderNames
            val state=getString(when { !ReceiverPreferences.enabled(this) -> R.string.pref_status_off; ReceiverPreferences.paused(this) -> R.string.pref_status_paused; else -> R.string.pref_status_receiving })
            status.text=if(senders.isEmpty()) state else state+" · "+resources.getQuantityString(R.plurals.pref_status_devices,senders.size,senders.size)
            devices.setSupporting(if(senders.isEmpty()) getString(R.string.pref_devices_none) else getString(R.string.pref_devices_value,senders.size,senders.joinToString(getString(R.string.photos_list_separator))))
            val free=getString(R.string.pref_storage_free,android.text.format.Formatter.formatShortFileSize(this,ReceiverEnvironment.deviceStorage(this).freeBytes))
            storage.setSupporting(free+" · "+getString(if(PhotosCleanup(this).enabled) R.string.pref_storage_cleanup_on else R.string.pref_storage_cleanup_off))
            appearance.setSupporting(appearanceLabel())
        }
        refresh();proposedRefresh=::refresh
        currentSettingValues+=status to {refresh();status.text.toString()}
    }
    /** Advanced (design/feature-triage.md): format conversion, browser access, stop receiving. */
    private fun proposedAdvancedPage() {
        val page=LookPage(this,getString(R.string.pref_advanced))
        val body=lookGroup(page.body)
        fun onOff(on:Boolean)=getString(if(on) R.string.pref_on else R.string.pref_off)
        lateinit var conversion:TextView
        lateinit var browser:TextView
        conversion=lookRow(body,R.drawable.ic_motion,getString(R.string.pref_conversion),onOff(MotionConversionSettings.enabled(this))) {
            showConversionSettings {conversion.setSupporting(onOff(MotionConversionSettings.enabled(this)))}
        }
        browser=lookRow(body,R.drawable.ic_computer,getString(R.string.pref_browser),onOff(ReceiverDashboardSettings.enabled(this))) {
            startActivity(Intent(this,BrowserManagementActivity::class.java))
        }
        lookRow(body,R.drawable.ic_receiver,getString(R.string.receiver_stop)) {page.dismiss();confirmStopReceiving()}
        page.setOnShowListener {browser.setSupporting(onOff(ReceiverDashboardSettings.enabled(this)))}
        page.show()
    }
    private fun recordsAndExports(parent:LinearLayout, heading:Boolean=true) {
        val group=duckGroup(parent,if(heading)getString(R.string.receiver_records_exports) else null)
        receiverSetting(group,getString(R.string.logs_retention_settings)) {showStorageControls(StorageSection.LOGS) {}}
        receiverSetting(group,getString(R.string.logs_export)) {showReportExport(false)}
        receiverSetting(group,getString(R.string.gallery_receipts_export)) {exportGalleryRecords()}
        receiverSetting(group,getString(R.string.originals_export)) {
            showArchiveIntro {originalArchive.launch("BackupDuck-originals-${System.currentTimeMillis()}.zip")}
        }
    }
    internal fun showDiagnostics() {
        val page=DuckPage(this,getString(R.string.receiver_records_exports))
        recordsAndExports(page.body,false)
        page.show()
    }
    private fun confirmStopReceiving() {
        duckConfirm(R.string.receiver_stop,R.string.duck_stop_service_intro,R.string.receiver_stop,true,notice=R.string.duck_reset_unchanged) {dialog ->
            ReceiverPreferences.setEnabled(this,false);ReceiverEnvironment.stopService(this);dialog.dismiss();renderReceiver(ReceiverState.snapshot.value)
        }
    }
    internal fun exportGalleryRecords() {showReportExport(true)}
    private var reportPage:DuckPage?=null
    private var reportGallery=false
    private fun receiverDisplayVersion():String {
        return receiverVersionLabel()
    }
    private fun showReportExport(gallery:Boolean) {
        val page=DuckPage(this,getString(if(gallery)R.string.gallery_receipts_export else R.string.logs_export));reportPage=page;reportGallery=gallery
        page.body.addView(duckParagraph(getString(if(gallery)R.string.gallery_receipts_export_note else R.string.duck_report_logs)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(20)})
        page.body.addView(duckButton(getString(R.string.duck_choose_location),true) {
            if(gallery)exportGalleryReceipts.launch("BackupDuck-gallery-receipts.json") else exportLogs.launch("BackupDuck-diagnostics.json")
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
    internal val hasKnownSenders get()=devicePanels.hasSenders
    internal val receiverDeviceName get()=devicePanels.name ?: Build.MODEL
    internal fun openConnection() {navigation.selectedItemId=1;choosePairing()}
    internal fun openTransfers(failed:Boolean=false) {
        navigation.selectedItemId=2
        // Received photos has no filters: what needs the user is its first section.
        receivedPhotos?.let { it.scrollToTop(); return }
        if(failed) lifecycleScope.launch {history.select(receiverRoot,filter="failed")}
    }
    internal fun openSettings() { navigation.selectedItemId = 4 }
    /** Storage is a tab in the current design and a page opened from Settings and the hub in the redesign. */
    internal fun openStorage() {
        if (!ReceiverEnvironment.proposedDesign) { navigation.selectedItemId = 3; return }
        storageScreen = StorageScreen(this, receiverRoot, ::openPhotos, ::openCleanup) { proposedRefresh?.invoke() }.also { it.show() }
    }
    private var storageScreen: StorageScreen? = null
    internal fun openCleanup() { startActivity(Intent(this, ExperimentsActivity::class.java)) }
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
        runCatching { ReceiverEnvironment.startService(this) }.onFailure {
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
