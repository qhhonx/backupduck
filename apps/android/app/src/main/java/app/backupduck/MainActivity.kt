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

class MainActivity : BackupDuckActivity() {
    internal val notificationWindows = ReceiverNotificationWindows()
    private val currentSettingValues=mutableListOf<Pair<TextView,()->String>>()
    private lateinit var pairingUI:PairingUI

    private val history: HistoryModel by viewModels()
    private val recentHistory = HistoryModel()
    /** Attention items for the proposed Received photos page; [history] holds its timeline. */
    private val attentionHistory = HistoryModel()
    private val receiverRoot get() = "$filesDir/receiver"
    private var selectedPage = 1
    private val rootBack = object : OnBackPressedCallback(false) {
        override fun handleOnBackPressed() { navigation.selectedItemId = 1 }
    }
    private fun updateRootBack() {
        rootBack.isEnabled = supportFragmentManager.backStackEntryCount == 0 && selectedPage != 1
    }
    private lateinit var navigation: BottomNavigationView
    private var storageDiscoveryDot: View? = null
    private var storageDiscoveryTitle: TextView? = null
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
    private var diagnosticsScreen: DiagnosticsScreen? = null
    private var exportingDiagnostics: DiagnosticsScreen? = null
    private val exportLogs = registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/json")) { uri ->
        val owner = exportingDiagnostics ?: diagnosticsScreen
        exportingDiagnostics = null
        if (uri != null && owner != null) lifecycleScope.launch {
            owner.result("busy")
            val result = withContext(Dispatchers.IO) { runCatching {
                val data = combinedDiagnostics(receiverRoot)
                checkNotNull(contentResolver.openOutputStream(uri, "wt")).use { it.write(data) }
                diagnosticFileName(uri, "BackupDuck-diagnostics.json")
            } }
            owner.result(if (result.isSuccess) "success" else "failure", result.getOrNull())
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        if(Build.VERSION.SDK_INT<33) getSharedPreferences("appearance",MODE_PRIVATE).getString("language",null)?.let {
            AppCompatDelegate.setApplicationLocales(androidx.core.os.LocaleListCompat.forLanguageTags(it))
        }
        window.requestFeature(android.view.Window.FEATURE_ACTIVITY_TRANSITIONS)
        supportRequestWindowFeature(androidx.appcompat.app.AppCompatDelegate.FEATURE_ACTION_MODE_OVERLAY)
        theme.applyStyle(R.style.ThemeOverlay_BackupDuck_NativeLibrary, true)
        super.onCreate(savedInstanceState)
        RelayMaintenance.schedule(this)
        devicePanels = DevicePanels(this) {
            if(::receiverHome.isInitialized) receiverHome.render(ReceiverState.snapshot.value,devicePanels.name,false)
            if(::historyPage.isInitialized) historyPage.render(history.state.value)
            receivedPhotos?.render(history.state.value)
            proposedRefresh?.invoke()
            maybeStartFirstRun()
        }
        pairingUI=PairingUI(this,::beginReceiving) {
            scanner.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setPrompt(getString(R.string.receiver_scan_prompt)).setBeepEnabled(false).setBarcodeImageEnabled(false).setCaptureActivity(ReceiverScanActivity::class.java).setOrientationLocked(true))
        }
        selectedPage = savedInstanceState?.getInt("page", 1) ?: 1
        val canvas = getColor(R.color.duck_role_background)
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(canvas) }
        val toolbar = MaterialToolbar(this).apply {
            menu.add(0,100,0,R.string.receiver_help_title).apply {
                isVisible=false
                setIcon(R.drawable.ic_info)
                setShowAsAction(android.view.MenuItem.SHOW_AS_ACTION_ALWAYS)
            }
            setOnMenuItemClickListener {if(selectedPage==2&&receivedPhotos==null)historyPage.showFilters();true}
        }
        titleBar = toolbar
        val coordinator = androidx.coordinatorlayout.widget.CoordinatorLayout(this)
        val appBar = com.google.android.material.appbar.AppBarLayout(this)
        val collapsing = com.google.android.material.appbar.CollapsingToolbarLayout(this, null,
            com.google.android.material.R.attr.collapsingToolbarLayoutLargeStyle).apply {
            title = getString(R.string.nav_receive)
            minimumHeight = resources.getDimensionPixelSize(com.google.android.material.R.dimen.m3_appbar_size_compact)
        }
        toolbar.id = View.generateViewId()
        collapsing.addView(toolbar, com.google.android.material.appbar.CollapsingToolbarLayout.LayoutParams(-1, resources.getDimensionPixelSize(com.google.android.material.R.dimen.m3_appbar_size_compact)).apply {
            collapseMode = com.google.android.material.appbar.CollapsingToolbarLayout.LayoutParams.COLLAPSE_MODE_PIN
        })
        appBar.addView(collapsing, com.google.android.material.appbar.AppBarLayout.LayoutParams(-1, resources.getDimensionPixelSize(com.google.android.material.R.dimen.m3_appbar_size_large)).apply {
            scrollFlags = com.google.android.material.appbar.AppBarLayout.LayoutParams.SCROLL_FLAG_SCROLL or
                com.google.android.material.appbar.AppBarLayout.LayoutParams.SCROLL_FLAG_EXIT_UNTIL_COLLAPSED
        })
        coordinator.addView(appBar, androidx.coordinatorlayout.widget.CoordinatorLayout.LayoutParams(-1, -2))
        val host = FrameLayout(this)
        coordinator.addView(host, androidx.coordinatorlayout.widget.CoordinatorLayout.LayoutParams(-1, -1).apply {
            behavior = com.google.android.material.appbar.AppBarLayout.ScrollingViewBehavior()
        })
        root.addView(coordinator, LinearLayout.LayoutParams(-1, 0, 1f))
        historyPage = HistoryPage(this, history, receiverRoot)
        storagePage = StoragePage(this, receiverRoot, totals = { counts ->
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
            navTitles.forEachIndexed { index, title -> if (!(proposed && index == 2)) menu.add(0, index + 1, index, title).setIcon(if (proposed && index == 1) R.drawable.ic_photo else icons[index]) }
            setOnItemSelectedListener { item ->
                selectedPage = item.itemId
                updateRootBack()
                // Top-level tabs retain the same compact chrome when switching.
                val largeTitle = !proposed
                collapsing.isTitleEnabled = largeTitle
                val pageTitle = getString(pageTitles[selectedPage - 1])
                collapsing.title = if (largeTitle) pageTitle else null
                toolbar.title = if (largeTitle) null else pageTitle
                collapsing.layoutParams = (collapsing.layoutParams as com.google.android.material.appbar.AppBarLayout.LayoutParams).apply {
                    height = resources.getDimensionPixelSize(if (largeTitle) com.google.android.material.R.dimen.m3_appbar_size_large
                        else com.google.android.material.R.dimen.m3_appbar_size_compact)
                    scrollFlags = if (largeTitle) com.google.android.material.appbar.AppBarLayout.LayoutParams.SCROLL_FLAG_SCROLL or
                        com.google.android.material.appbar.AppBarLayout.LayoutParams.SCROLL_FLAG_EXIT_UNTIL_COLLAPSED else 0
                }
                appBar.setExpanded(true, false)
                toolbar.menu.findItem(100).apply {isVisible=selectedPage==2&&receivedPhotos==null;setIcon(R.drawable.ic_more);setTitle(R.string.duck_advanced_filters)}
                pages.forEachIndexed { index, page -> page.visibility = if (index + 1 == selectedPage) View.VISIBLE else View.GONE }
                if (selectedPage == 3) storagePage.refresh(force = true)
                true
            }
        }
        root.addView(navigation, LinearLayout.LayoutParams(-1, -2))
        setContentView(root)
        navigation.selectedItemId = selectedPage
        refreshDiscovery()
        handleDestination(intent)
        storagePage.refresh(force = true, includeDetails = selectedPage == 3)
        onBackPressedDispatcher.addCallback(this, rootBack)
        supportFragmentManager.addOnBackStackChangedListener { updateRootBack() }
        updateRootBack()
        lifecycleScope.launch {
            val filtered = history.state.value.let { it.filter != "all" || it.kind != "all" || it.sender != null }
            if (history.state.value.items.isEmpty() || (receivedPhotos != null && filtered)) history.select(receiverRoot, filter = "all", kind = "all", sender = null)
            recentHistory.select(receiverRoot)
            if (receivedPhotos != null) attentionHistory.select(receiverRoot, filter = "failed")
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch { history.state.collect { historyPage.render(it); receivedPhotos?.render(it) } }
                receivedPhotos?.let { page -> launch { attentionHistory.state.collect(page::attention) } }
                launch { ReceiverState.snapshot.collect(::renderReceiver) }
                launch { ReceiverEnvironment.cleanupOperations.state.collect {
                    refreshDiscovery(); renderReceiver(ReceiverState.snapshot.value)
                } }
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
                        refreshDiscovery()
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
    internal var restorePhotoAnchor: ((Intent?) -> Unit)? = null
    override fun onActivityReenter(resultCode: Int, data: Intent?) {
        super.onActivityReenter(resultCode, data)
        restorePhotoAnchor?.invoke(data)
    }
    override fun onNewIntent(next:Intent) {super.onNewIntent(next);setIntent(next);handleDestination(next)}
    override fun onResume() {
        super.onResume()
        if (::navigation.isInitialized) refreshDiscovery()
    }
    private fun refreshDiscovery() {
        val unseen = FeatureDiscovery(this).isUnseen(FeatureDiscovery.PHOTOS_CLEANUP)
        val attention = currentCleanupStatus().needsAttention
        storageDiscoveryDot?.apply {
            visibility = if (attention || unseen) View.VISIBLE else View.GONE
            setDuckEntryMark(attention)
        }
        storageDiscoveryTitle?.contentDescription = when {
            attention -> getString(R.string.attention_entry_label, getString(R.string.pref_storage))
            unseen -> getString(R.string.discovery_entry_label, getString(R.string.pref_storage))
            else -> null
        }
        if (!::navigation.isInitialized) return
        if (attention || unseen) navigation.getOrCreateBadge(4).apply {
            clearNumber()
            backgroundColor = getColor(if (attention) R.color.duck_state_attention else R.color.duck_brand_accent)
            setContentDescriptionNumberless(getString(if (attention) R.string.attention_required else R.string.discovery_available))
            isVisible = true
        } else navigation.removeBadge(4)
    }
    private fun handleDestination(next:Intent) {
        val notificationRoute = ReceiverNotificationRoute.parse(next.getStringExtra(ReceiverNotificationRoute.EXTRA))
        next.removeExtra(ReceiverNotificationRoute.EXTRA)
        if (notificationRoute != null) {
            notificationWindows.dismiss()
            supportFragmentManager.popBackStackImmediate(null, androidx.fragment.app.FragmentManager.POP_BACK_STACK_INCLUSIVE)
            navigation.selectedItemId = 1
            when (notificationRoute) {
                ReceiverNotificationRoute.RECEIVE -> Unit
                ReceiverNotificationRoute.NEEDS_YOU -> {
                    openTransfers(failed = true)
                    receivedPhotos?.openNeedsYou()
                }
                ReceiverNotificationRoute.STORAGE -> openStorage()
            }
            return
        }
        when(next.getStringExtra("destination")) {
            "receive"->navigation.selectedItemId=1
            "transfers"->navigation.selectedItemId=2
            "storage"->openStorage()
            "settings"->navigation.selectedItemId=4
        }
        when(next.getStringExtra("surface")) {
            "photo-history" -> {
                openTransfers()
            }
            "pairing"->choosePairing()
            "connect-mac"->openConnect(mac=true)
            "devices"->openDevices()
            "storage-limits", "retention", "reclaim-originals", "relay-history" -> openStorage()
            "archive", "archive-export", "archive-result", "archive-reclaim" -> showDiagnostics()
            "report"->showReportExport(false)
            "gallery-report"->showReportExport(true)
            "advanced"->proposedAdvancedPage()
            "conversion"->proposedAdvancedPage()
            "help"->openHelp()
            "help-connection","help-background","help-results","help-storage","help-recovery",
            "help-connect","help-full","help-stopped","help-cleanup"->
                openHelp(ReceiverHelpTopic.entries.first {it.key==next.getStringExtra("surface")!!.removePrefix("help-")})
            "browser"->startActivity(Intent(this,BrowserManagementActivity::class.java))
            "updates"->startActivity(Intent(this,UpdatesActivity::class.java))
            "about"->createAboutPage().show()
            "feedback"->showFeedback()
            "settings-bottom"->findViewById<androidx.core.widget.NestedScrollView>(R.id.settings_scroll)?.let { scroll ->
                scroll.post {scroll.fullScroll(View.FOCUS_DOWN)}
            }
            "diagnostics", "logs-retention"->showDiagnostics()
            "diagnostics-log", "diagnostics-detail" -> startActivity(Intent(this, ReceiverActivityLogActivity::class.java).putExtra("detail", next.getStringExtra("surface") == "diagnostics-detail"))
            "diagnostics-probe", "diagnostics-setup", "diagnostics-bind", "diagnostics-progress" -> {
                val route = when(next.getStringExtra("surface")) { "diagnostics-probe" -> "diagnostics"; "diagnostics-setup" -> "cleanup"; "diagnostics-bind" -> "bind"; else -> "progress" }
                startActivity(Intent(this, PhotosProbeActivity::class.java).putExtra("route", route).putExtra("diagnostics", route == "diagnostics"))
            }
            "cleanup-consent"->{openStorage();storageScreen?.showCleanupConsent()}
            "cleanup"->openCleanup()
            "auto-cleanup"->openAutoCleanup()
        }
        next.removeExtra("surface");next.removeExtra("destination")
    }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putInt("page", selectedPage)
        super.onSaveInstanceState(outState)
    }
    private var updateFeedback: android.widget.TextView? = null
    override fun onStart() {
        super.onStart()
        currentSettingValues.forEach {(view,value)->val next=value();if(view.text.toString()!=next)view.text=next}
        if (ReceiverPreferences.enabled(this)) startReceiverService()
        val updates = AppUpdates.preferences(this)
        val now = System.currentTimeMillis()
        if (ReceiverEnvironment.checksUpdates && !packageName.endsWith(".validation") && updates.getBoolean("automatic", true) && now - updates.getLong("checked", 0) > 86_400_000L) {
            updates.edit().putLong("checked", now).apply()
            lifecycleScope.launch {
                val next = (AppUpdates.check(this@MainActivity) as? UpdateCheckStatus.Available)?.release
                if (next != null && !isFinishing && lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                    updateFeedback?.text = getString(R.string.updates_available,next.version)
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
    /** First run (design/flows.md) once, for a Pixel that has never been connected. */
    private fun maybeStartFirstRun() {
        val prefs = getSharedPreferences("first_run", MODE_PRIVATE)
        if (!ReceiverEnvironment.proposedDesign || prefs.getBoolean("done", false) || devicePanels.hasSenders != false) return
        prefs.edit().putBoolean("done", true).apply()
        startActivity(Intent(this, ReceiverOnboardingActivity::class.java))
    }
    private fun choosePairing() {if(ReceiverEnvironment.proposedDesign) openConnect() else pairingUI.choose()}
    private var connectPage:ConnectPage?=null
    /** The one connect flow (design/pixel-connect.md) for the hub, the device page and the Received photos empty state. */
    private fun createConnectPage(state: Bundle): ConnectPage {
        lateinit var next: ConnectPage
        next = ConnectPage(this, ::scanCode, ::beginReceiving, state) {
            if (connectPage === next) connectPage = null
            devicePanels.refresh(); devicesPage?.reload()
        }
        connectPage = next
        if (state.getBoolean("scan")) connectScan = next.flow::scanned
        return next
    }
    private fun openConnect(mac:Boolean=false) {
        if (connectPage?.isShowing == true) return
        createConnectPage(Bundle().apply { putString("surface", if (mac) "connect-mac" else "pairing") }).show()
    }
    private var devicesPage:DevicesPage?=null
    private fun createDevicesPage() = DevicesPage(this, { openConnect() }) { devicePanels.refresh() }.also { devicesPage = it }
    private fun openDevices() { createDevicesPage().show() }
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
        currentSettingValues+=conversion to {getString(if(MotionConversionSettings.enabled(this)) R.string.duck_on else R.string.duck_off)}
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
        receiverSetting(duckGroup(panel),getString(R.string.pref_storage),action=::openStorage)
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
        com.google.android.material.dialog.MaterialAlertDialogBuilder(this)
            .setTitle(R.string.settings_appearance)
            .setSingleChoiceItems(labels.map {getString(it)}.toTypedArray(), modes.indexOf(delegate.localNightMode)) { dialog, index ->
                dialog.dismiss();getSharedPreferences("appearance",MODE_PRIVATE).edit().putInt("mode",modes[index]).apply();delegate.localNightMode=modes[index]
            }.setNegativeButton(R.string.device_cancel, null).show().also { trackNotificationWindow(it) }
    }
    private fun chooseLanguage() {
        val language=currentLanguageTag()
        val tags=listOf("", "zh-CN", "en")
        val labels=arrayOf(getString(R.string.appearance_system), "简体中文", "English")
        com.google.android.material.dialog.MaterialAlertDialogBuilder(this)
            .setTitle(R.string.duck_language)
            .setSingleChoiceItems(labels, tags.indexOfFirst {language.equals(it,true)}) { dialog, index ->
                val tag=tags[index]
                dialog.dismiss();getSharedPreferences("appearance",MODE_PRIVATE).edit().putString("language",tag).apply()
                AppCompatDelegate.setApplicationLocales(androidx.core.os.LocaleListCompat.forLanguageTags(tag))
            }.setNegativeButton(R.string.device_cancel, null).show().also { trackNotificationWindow(it) }
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
        val storage=lookRow(receive,R.drawable.ic_storage,getString(R.string.pref_storage),"", trailing=duckDiscoveryDot().also { storageDiscoveryDot=it }) {openStorage()}
        storageDiscoveryTitle=(storage.parent as LinearLayout).getChildAt(0) as TextView
        refreshDiscovery()
        lookSection(panel,getString(R.string.pref_section_general))
        val general=lookGroup(panel)
        val appearance=lookRow(general,R.drawable.ic_contrast,getString(R.string.pref_appearance),appearanceLabel()) {chooseAppearance()}
        lookRow(general,R.drawable.ic_globe,getString(R.string.pref_language),languageLabel()) {chooseLanguage()}
        lookSection(panel,getString(R.string.pref_help_feedback))
        val help=lookGroup(panel)
        lookRow(help,R.drawable.ic_help,getString(R.string.pref_help)) {openHelp()}
        lookRow(help,R.drawable.ic_feedback,getString(R.string.pref_send_feedback),feedbackSummary()) {showFeedback()}
        val more=lookGroup(panel)
        (more.parent as View).let {card ->
            card.layoutParams=(card.layoutParams as LinearLayout.LayoutParams).apply {topMargin=token(R.dimen.duck_space_large)}
        }
        lookRow(more,R.drawable.ic_info,getString(R.string.pref_about),getString(R.string.pref_version_value,receiverAppVersion())) {
            createAboutPage().show()
        }
        settingsFooter(panel, {showDiagnostics()}, {proposedAdvancedPage()})
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
    }.apply {id=R.id.settings_scroll}
    /** Advanced (design/feature-triage.md): format conversion, browser access, stop receiving. */
    private fun proposedAdvancedPage() { createAdvancedPage().show() }
    private fun createAdvancedPage(): LookPage {
        val page=LookPage(this,getString(R.string.pref_advanced), "advanced")
        val body=lookGroup(page.body)
        fun onOff(on:Boolean)=getString(if(on) R.string.pref_on else R.string.pref_off)
        lateinit var browser:TextView
        val conversion=lookSwitchRow(body,R.drawable.ic_motion,getString(R.string.pref_conversion),getString(R.string.advanced_conversion_note),MotionConversionSettings.enabled(this)) {
            MotionConversionSettings.setEnabled(this,it)
        }
        browser=lookRow(body,R.drawable.ic_computer,getString(R.string.pref_browser),onOff(ReceiverDashboardSettings.enabled(this))) {
            startActivity(Intent(this,BrowserManagementActivity::class.java))
        }
        lookRow(body,R.drawable.ic_receiver,getString(R.string.receiver_stop)) {page.dismiss();confirmStopReceiving()}
        page.resumed = {
            browser.setSupporting(onOff(ReceiverDashboardSettings.enabled(this)))
            conversion.toggle.restore(MotionConversionSettings.enabled(this))
        }
        return page
    }
    private fun recordsAndExports(parent:LinearLayout, heading:Boolean=true) {
        val group=duckGroup(parent,if(heading)getString(R.string.receiver_records_exports) else null)
        receiverSetting(group,getString(R.string.diag_export)) {showDiagnostics()}

    }
    internal fun showDiagnostics() { createDiagnosticsPage().show() }
    private fun createDiagnosticsPage(restored: Bundle = Bundle()): LookPage {
        val screen = DiagnosticsScreen(this, restored, { owner ->
            exportingDiagnostics = owner
            runCatching { exportLogs.launch("BackupDuck-diagnostics.json") }
                .onFailure { exportingDiagnostics = null; owner.result("failure") }
        })
        diagnosticsScreen = screen
        return screen.page
    }
    private fun confirmStopReceiving() {
        duckConfirm(R.string.receiver_stop,R.string.duck_stop_service_intro,R.string.receiver_stop,true,notice=R.string.duck_reset_unchanged) {dialog ->
            ReceiverPreferences.setEnabled(this,false);ReceiverEnvironment.stopService(this);dialog.dismiss();renderReceiver(ReceiverState.snapshot.value)
        }
    }
    internal fun exportGalleryRecords() { showDiagnostics() }
    private fun receiverDisplayVersion(): String = receiverVersionLabel()
    private fun showReportExport(gallery: Boolean) { showDiagnostics() }
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
        storageScreen?.takeIf { it.isShowing }?.let { return }
        createStoragePage().show()
    }
    private fun createStoragePage(state: Bundle = Bundle()) = StorageScreen(this, receiverRoot, ::openPhotos, state) {
        proposedRefresh?.invoke(); refreshDiscovery()
    }.also { storageScreen = it }
    private var storageScreen: StorageScreen? = null
    private fun createPhotosRedirect(): DuckPage = DuckPage(this, getString(R.string.nav_photos), "photo-history").also { page ->
        page.root.post { page.dismiss(); openTransfers() }
    }
    internal override fun restorePage(route: String, state: Bundle): PageDestination = when (route) {
        "photo-history" -> createPhotosRedirect()
        "connect" -> createConnectPage(state)
        "devices" -> createDevicesPage().page
        "storage" -> createStoragePage(state).page
        "auto-cleanup" -> AutoCleanupScreen(this, state).page
        "about" -> createAboutPage()
        "advanced" -> createAdvancedPage()
        "conversion" -> createAdvancedPage()
        "storage-limits", "retention", "reclaim-originals", "relay-history" -> createStoragePage().page
        "diagnostics" -> createDiagnosticsPage(state)
        "logs-report" -> createDiagnosticsPage(Bundle().apply { putString("export", "failure") })
        "gallery-report" -> createDiagnosticsPage(Bundle().apply { putString("export", "failure") })
        "archive", "archive-export", "archive-result", "archive-reclaim" -> createDiagnosticsPage()
        "legacy-devices" -> devicePanels.showPeers(show = false)
        "legacy-scan" -> pairingUI.scanning(show = false)
        else -> super.restorePage(route, state)
    }
    internal fun openAutoCleanup() { AutoCleanupScreen(this).page.show() }
    internal fun openCleanup() { openStorage(); storageScreen?.focusCleanup() }
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
