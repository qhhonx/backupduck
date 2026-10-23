package app.backupduck

import android.content.Context
import android.text.format.Formatter
import androidx.lifecycle.lifecycleScope

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

/** Independent of reception; the durable native scope applies to every commit. */
internal object RelayMaintenance {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var work: Job? = null
    val manualActive = AtomicBoolean(false)
    private var revision = 0
    private val mutableStatus = MutableStateFlow<Int?>(null)
    val status = mutableStatus.asStateFlow()
    @Synchronized fun cancelAutomatic() { revision++; work?.cancel(); work = null; mutableStatus.value = null }
    @Synchronized fun schedule(context: Context) {
        if (work?.isActive == true) return
        val app = context.applicationContext
        val version = ++revision
        fun status(value: Int?) { synchronized(this) { if (version == revision) mutableStatus.value = value } }
        work = scope.launch {
            try {
                val root = "${app.filesDir}/receiver"
                val config = NativeBridge.request(JSONObject().put("op", "receiver_settings").put("root", root)) as JSONObject
                if (!config.getJSONObject("settings").getBoolean("receiver_relay")) return@launch
                val sweep = GalleryRetention(root)
                status(R.string.relay_scanning)
                while (isActive) {
                    waitForRelay(app) { status(R.string.relay_waiting) }
                    val count = ReceiverState.mediaOperations.withLock {
                        currentCoroutineContext().ensureActive()
                        if (relayHeld(app)) -1 else sweep.step(app)
                    }
                    if (count == 0) break
                    status(R.string.relay_scanning)
                    delay(250)
                }
                status(R.string.relay_scan_finished)
            } catch (cancelled: CancellationException) { status(null); throw cancelled }
            catch (_: Exception) { status(R.string.relay_scan_failed) }
        }
    }
}

internal fun relayHeld(context: Context): Boolean {
    val reading = readThermal(context)
    return ReceiverHolds.thermalHeld || PhotosCleanup(context).held ||
        ThermalDecision().next(ReceiverThermalSettings.enabled(context), ReceiverThermalSettings.threshold(context), reading).held
}
private suspend fun waitForRelay(context: Context, waiting: suspend () -> Unit) {
    while (relayHeld(context)) { waiting(); delay(2_000); currentCoroutineContext().ensureActive() }
}

internal data class RelayPlan(val candidates: List<JSONObject>, val retained: Map<String, Int>, val bytes: Long)

internal suspend fun verifyRelayCandidate(context: Context, candidate: JSONObject): GalleryCopy {
    val item = candidate.getJSONObject("publication")
    val stored = candidate.optJSONObject("copy")
    val asset = item.getJSONObject("asset")
    if (stored == null && (asset.getString("kind") == "motion" || asset.optJSONObject("metadata")?.has("burst_group_ref") == true))
        error("relay_evidence_missing")
    return if (stored != null) MediaPublisher.verify(context, GalleryCopy.parse(stored))
        else MediaPublisher.publish(context, item, existingOnly = true)
}

internal suspend fun inspectRelay(context: Context, root: String, progress: suspend (Int?) -> Unit): RelayPlan {
    val plan = mutableListOf<JSONObject>(); val retained = mutableMapOf<String, Int>()
    var cursor = ""; var checked = 0
    while (true) {
        currentCoroutineContext().ensureActive()
        waitForRelay(context) { progress(null) }
        val rows = ReceiverState.mediaOperations.withLock {
            NativeBridge.request(JSONObject().put("op", "gallery_candidates").put("root", root).put("after", cursor).put("manual", true)) as JSONArray
        }
        if (rows.length() == 0) break
        for (i in 0 until rows.length()) {
            currentCoroutineContext().ensureActive()
            val candidate = rows.getJSONObject(i)
            cursor = candidate.getJSONObject("publication").getString("id")
            waitForRelay(context) { progress(null) }
            try {
                ReceiverState.mediaOperations.withLock { verifyRelayCandidate(context, candidate) }
                plan += candidate
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) {
                val reason = when (error.message) {
                    "relay_evidence_missing" -> "evidence"
                    "gallery_copy_changed" -> "changed"
                    "gallery_copy_missing" -> "missing"
                    else -> "unverified"
                }
                retained[reason] = (retained[reason] ?: 0) + 1
            }
            progress(++checked)
        }
    }
    val ids = JSONArray(plan.map { it.getJSONObject("publication").getString("id") })
    val estimate = ReceiverState.mediaOperations.withLock {
        NativeBridge.request(JSONObject().put("op", "gallery_release_bytes").put("root", root).put("ids", ids)) as JSONObject
    }
    return RelayPlan(plan, retained, estimate.getLong("bytes"))
}

internal suspend fun reclaimRelay(context: Context, root: String, plan: RelayPlan, progress: suspend (Int?) -> Unit): Pair<Int, Long> {
    var released = 0; var bytes = 0L
    for (candidate in plan.candidates) {
        var retry: Boolean
        do {
        currentCoroutineContext().ensureActive()
        waitForRelay(context) { progress(null) }
        retry = false
        try {
            ReceiverState.mediaOperations.withLock {
                // A preview is not evidence at deletion time. Reopen and hash again.
                val proof = verifyRelayCandidate(context, candidate)
                currentCoroutineContext().ensureActive()
                if (relayHeld(context)) { retry = true; return@withLock }
                val result = NativeBridge.request(JSONObject().put("op", if (candidate.optBoolean("confirmed")) "release_gallery" else "gallery_publication")
                    .put("root", root).put("id", candidate.getJSONObject("publication").getString("id"))
                    .put("copy", proof.json()).put("manual", true)) as JSONObject
                bytes += result.getLong("bytes"); released++
            }
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { /* Changed or missing copies keep their originals. */ }
        } while (retry)
        progress(released)
    }
    return released to bytes
}
