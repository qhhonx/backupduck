package app.backupduck

import android.app.*
import android.content.Intent
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.os.IBinder
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject

internal data class RecentTransfer(val id: String, val filename: String, val kind: String, val totalBytes: Long,
    val confirmedBytes: Long, val receipt: String, val processing: String)
internal data class ReceiverSnapshot(val phase: String = "idle", val published: Int = 0, val error: String? = null,
    val received: Int = 0, val total: Int = 0, val failed: Int = 0, val reservedBytes: Long = 0,
    val capacityBytes: Long = 0, val recent: List<RecentTransfer> = emptyList(), val processingName: String? = null,
    val thermalHeld: Boolean = false, val temperatureDeciCelsius: Int? = null,
    val manualPaused: Boolean = false)
internal object ReceiverState {
    val mutable = MutableStateFlow(ReceiverSnapshot())
    val snapshot = mutable.asStateFlow()
    val lifecycle = Mutex()
    val mediaOperations = Mutex()
    // Deliberately excluded from snapshots and their generated toString methods.
    @Volatile var pairing: String? = null
}

internal fun ReceiverSnapshot.startingIfRequested(announce: Boolean): ReceiverSnapshot =
    if (announce) copy(phase = "starting", error = null) else this

class ReceiverService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var started = false
    private val retryStartup = kotlinx.coroutines.channels.Channel<Unit>(kotlinx.coroutines.channels.Channel.CONFLATED)
    private var cursor = ""
    private var spaceBlocked = false
    private val retention = GalleryRetention()
    private val overviewUpdates = Mutex()
    private val cleanup by lazy { PhotosCleanup(this) }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("receiver", getString(R.string.app_name), NotificationManager.IMPORTANCE_LOW)
        )
        startForeground(1, ReceiverNotifications.build(this, ReceiverState.snapshot.value))
        scope.launch {
            var previous: ReceiverNotifications.Content? = null
            ReceiverState.snapshot.collect { state ->
                val content = ReceiverNotifications.content(this@ReceiverService, state)
                if (content != previous) {
                    previous = content
                    getSystemService(NotificationManager::class.java).notify(1,
                        ReceiverNotifications.build(this@ReceiverService, state))
                }
            }
        }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!ReceiverPreferences.enabled(this)) { stopSelf(); return START_NOT_STICKY }
        if (started) {
            if(ReceiverState.snapshot.value.phase=="waiting") retryStartup.trySend(Unit)
            return START_STICKY
        }
        started = true
        scope.launch {
            // A replacement service waits for the previous receiver to stop.
            ReceiverState.lifecycle.withLock {
                var announceStart = true
                while (isActive) {
                    // Background retries keep the recovery explanation visible.
                    // Only the initial/manual attempt announces a new start.
                    ReceiverState.mutable.update { it.startingIfRequested(announceStart) }
                    var opened = false
                    var dashboard: Job? = null
                    var thermalMonitor: Job? = null
                    var progressMonitor: Job? = null
                    var advertisement: ReceiverAdvertisement? = null
                    var wifiLease: WifiManager.WifiLock? = null
                    try {
                        val address = wifiAddress()
                        val port = if(packageName=="app.backupduck.validation") 48484 else 8484
                        // Create a locale-appropriate stable name even after boot,
                        // before a sender's first optional profile exchange.
                        runCatching { DeviceProfiles.read(this@ReceiverService) }
                        val pairing = NativeBridge.request(JSONObject().put("op", "start_receiver")
                            .put("root", "$filesDir/receiver").put("listen", "$address:$port")
                            .put("capacity", 6L * 1024 * 1024 * 1024)) as JSONObject
                        opened = true
                        // A foreground service alone does not keep the Wi-Fi radio awake
                        // when this always-on receiver's screen is off.
                        wifiLease = getSystemService(WifiManager::class.java)
                            .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "BackupDuck:receiver")
                            .apply { setReferenceCounted(false); acquire() }
                        val initialThermal = readThermal(this@ReceiverService)
                        val initialDecision = ThermalDecision().next(ReceiverThermalSettings.enabled(this@ReceiverService),
                            ReceiverThermalSettings.threshold(this@ReceiverService), initialThermal)
                        ReceiverHolds.setThermal(this@ReceiverService, initialDecision.held)
                        ReceiverState.pairing = pairing.toString()
                        if (ReceiverDashboardSettings.enabled(this@ReceiverService)) {
                            runCatching { NativeBridge.request(JSONObject().put("op", "start_dashboard")) }
                                .onFailure { runCatching { NativeBridge.request(JSONObject().put("op", "record_event")
                                    .put("receiver", true).put("code", "dashboard_unavailable")) } }
                        }
                        publishDashboardDeviceStatus(initialThermal, initialDecision.held)
                        advertisement = runCatching { ReceiverAdvertisement(this@ReceiverService, pairing.getString("receiver_id"), port) }.getOrNull()
                        // This is the same persistent receiver catalog. Keep its
                        // last known counters/rows until the first fresh query,
                        // rather than flashing them through invented zeroes.
                        ReceiverState.mutable.update { it.copy(phase = "ready", error = null, processingName = null,
                            thermalHeld = initialDecision.held, temperatureDeciCelsius = initialThermal.deciCelsius,
                            manualPaused = ReceiverPreferences.paused(this@ReceiverService)) }
                        ReceiverProgress.mutable.value=emptyMap()
                        progressMonitor=scope.launch {
                            var revision=0L
                            var phases=emptyMap<String,String>()
                            while(isActive) {
                                val data=runCatching {NativeBridge.request(JSONObject().put("op","receiver_progress").put("after",revision).put("timeout_ms",1000)) as JSONObject}.getOrNull()
                                ensureActive()
                                if(data!=null) {
                                    val next=data.getLong("revision")
                                    if(next!=revision) {
                                        revision=next
                                        val updates=ReceiverProgress.parse(data)
                                        ReceiverProgress.mutable.value=updates
                                        val nextPhases=updates.mapValues {"${it.value.received}|${it.value.processing}|${it.value.error}"}
                                        if(nextPhases!=phases) {phases=nextPhases;runCatching {updateOverview()}}
                                    }
                                    // Coalesce fast chunk completions to at most ten visual updates/second.
                                    delay(100)
                                } else delay(1000)
                            }
                        }
                        thermalMonitor = scope.launch {
                            try {
                                var decision = initialDecision
                                while (isActive) {
                                    val reading = readThermal(this@ReceiverService)
                                    val next = decision.next(ReceiverThermalSettings.enabled(this@ReceiverService),
                                        ReceiverThermalSettings.threshold(this@ReceiverService), reading)
                                    if (next.held != decision.held) {
                                        ReceiverHolds.setThermal(this@ReceiverService, next.held)
                                    }
                                    decision = next
                                    ReceiverState.mutable.update { it.copy(thermalHeld = decision.held,
                                        temperatureDeciCelsius = reading.deciCelsius) }
                                    publishDashboardDeviceStatus(reading, decision.held)
                                    delay(2_000)
                                }
                            } catch (cancelled: CancellationException) { throw cancelled }
                            catch (_: Exception) {
                                // Do not leave an unmonitored receiver accepting more bytes.
                                ReceiverState.mutable.update { it.copy(error = "thermal_monitor_unavailable") }
                                stopSelf()
                            }
                        }
                        dashboard = launch {
                            while (isActive) {
                                runCatching {
                                    updateOverview()
                                }
                                delay(1_000)
                            }
                        }
                        while (isActive) {
                            val currentAddress = runCatching { wifiAddress(address) }.getOrNull()
                            if (currentAddress != address) {
                                ReceiverState.mutable.update { it.copy(error = if (currentAddress == null) "wifi_required" else "receiver_address_changed") }
                                break
                            }
                            val healthy = NativeBridge.request(JSONObject().put("op", "receiver_status")) as JSONObject
                            check(healthy.getBoolean("running")) { "receiver_unavailable" }
                            val space = NativeBridge.request(JSONObject().put("op", "receiver_overview")) as JSONObject
                            if (ReceiverHolds.thermalHeld) ReceiverHolds.sync(this@ReceiverService)
                            else cleanup.tick(space.getLong("free_bytes"), space.getLong("min_free_bytes"))
                            if (!cleanup.held && !ReceiverHolds.thermalHeld) ReceiverState.mediaOperations.withLock {
                                if (!cleanup.held && !ReceiverHolds.thermalHeld) {
                                    retention.step(this@ReceiverService)
                                    publish()
                                }
                            }
                            delay(5_000)
                        }
                    } catch (cancelled: CancellationException) { throw cancelled }
                    catch (error: Exception) {
                        val code = safeError(error)
                        runCatching { NativeBridge.request(JSONObject().put("op", "record_event").put("receiver", true)
                            .put("root", "$filesDir/receiver").put("code", when (code) {
                                "receiver_port_in_use" -> "receiver_start_port_in_use"
                                "receiver_interface_unavailable", "wifi_required" -> "receiver_start_network_unavailable"
                                else -> "receiver_start_failed"
                            })) }
                        ReceiverState.mutable.update { it.copy(phase = "waiting", error = code) }
                    } finally {
                        withContext(NonCancellable + Dispatchers.IO) {
                            advertisement?.close()
                            thermalMonitor?.cancelAndJoin()
                            dashboard?.cancelAndJoin()
                            progressMonitor?.cancelAndJoin()
                            ReceiverProgress.mutable.value=emptyMap()
                            ReceiverState.pairing = null
                            if (opened) runCatching { NativeBridge.request(JSONObject().put("op", "stop_receiver")) }
                            ReceiverHolds.reset()
                            wifiLease?.let { lease -> if (lease.isHeld) lease.release() }
                            ReceiverState.mutable.update { it.copy(phase = if (scope.isActive) "waiting" else "idle",
                                processingName = null, thermalHeld = false, temperatureDeciCelsius = null) }
                        }
                    }
                    announceStart = withTimeoutOrNull(5_000) {retryStartup.receive()} != null
                }
            }
        }
        return START_STICKY
    }
    private suspend fun updateOverview() = overviewUpdates.withLock {
        val summary = NativeBridge.request(JSONObject().put("op", "receiver_overview")) as JSONObject
        val rows = summary.getJSONArray("recent")
        val recent = (0 until rows.length()).map { index ->
            val row = rows.getJSONObject(index)
            RecentTransfer(row.getString("id"), row.getString("filename"), row.getString("kind"),
                row.getLong("total_bytes"), row.getLong("confirmed_bytes"), row.getString("receipt"), row.getString("processing"))
        }
        ReceiverState.mutable.update { it.copy(received = summary.getInt("received"), total = summary.getInt("total"),
            published = summary.getInt("published"), failed = summary.getInt("failed"), reservedBytes = summary.getLong("reserved_bytes"),
            capacityBytes = summary.getLong("capacity_bytes"), recent = recent) }
    }
    private suspend fun publish() {
        val items = NativeBridge.request(JSONObject().put("op", "publications").put("after", cursor)) as JSONArray
        if (items.length() == 0) { cursor = ""; return }
        for (index in 0 until items.length()) {
            currentCoroutineContext().ensureActive()
            if (ReceiverHolds.thermalHeld) break
            val item = items.getJSONObject(index)
            cursor = item.getString("id")
            if (item.getString("processing") == "failed") continue
            val overview = NativeBridge.request(JSONObject().put("op", "receiver_overview")) as JSONObject
            val resources = item.getJSONObject("asset").getJSONArray("resources")
            var originals = 0L
            for (resource in 0 until resources.length()) originals = Math.addExact(originals, resources.getJSONObject(resource).getLong("size"))
            // Leave room for conversion scratch data and the MediaStore copy.
            val factor = if (item.getJSONObject("asset").getString("kind") == "motion") 3L else 1L
            val needed = Math.addExact(Math.multiplyExact(originals, factor), 32L shl 20)
            if (overview.getLong("free_bytes") - overview.getLong("min_free_bytes") < needed) {
                ReceiverState.mutable.update { it.copy(error = "processing_low_space", processingName = null) }
                if (!spaceBlocked) NativeBridge.request(JSONObject().put("op", "record_event").put("receiver", true).put("code", "processing_low_space"))
                spaceBlocked = true
                continue
            }
            if (spaceBlocked) {
                NativeBridge.request(JSONObject().put("op", "record_event").put("receiver", true).put("code", "processing_resumed"))
                spaceBlocked = false
            }
            val filename = item.getJSONObject("asset").getJSONArray("resources").getJSONObject(0).getString("filename")
            ReceiverState.mutable.update { it.copy(processingName = filename) }
            var failureCode: String? = null
            val success = try {
                val copy = MediaPublisher.publish(this, item)
                NativeBridge.request(JSONObject().put("op", "gallery_publication").put("id", cursor).put("copy", copy.json()))
                ReceiverState.mutable.update { it.copy(error = null) }
                true
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) {
                failureCode = safeError(error)
                ReceiverState.mutable.update { it.copy(error = failureCode) }
                false
            }
            if (!success) NativeBridge.request(JSONObject().put("op", "processed").put("id", cursor)
                .put("success", false).put("error", failureCode ?: "operation_failed"))
            ReceiverState.mutable.update { it.copy(processingName = null) }
        }
    }
    private fun wifiAddress(preferred: String? = null): String =
        ReceiverWifiAddress.read(getSystemService(ConnectivityManager::class.java), preferred)
    private fun publishDashboardDeviceStatus(reading: ThermalReading, held: Boolean) {
        runCatching { NativeBridge.request(JSONObject().put("op", "dashboard_device_status")
            .put("temperature_deci_celsius", reading.deciCelsius ?: JSONObject.NULL)
            .put("battery_percent", reading.batteryPercent ?: JSONObject.NULL)
            .put("charging", reading.charging ?: JSONObject.NULL)
            .put("thermal_held", held)
            .put("thermal_enabled", ReceiverThermalSettings.enabled(this))
            .put("thermal_threshold_celsius", ReceiverThermalSettings.threshold(this))) }
    }
    override fun onTimeout(startId: Int, fgsType: Int) {
        ReceiverState.mutable.update { it.copy(phase = "waiting", error = "system_time_limit") }
        stopSelf()
    }
    override fun onDestroy() { scope.cancel(); super.onDestroy() }
}

internal fun safeError(error: Exception): String = error.message?.takeIf { it.matches(Regex("[a-z_]{1,40}")) } ?: "operation_failed"
