package app.backupduck

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** A reviewable state of one receiver page. See `apps/android/app/src/catalog/README.md`. */
internal class CatalogScenario(json: JSONObject) {
    class Answer(val value: Any?, val error: String?, val delayMs: Long)
    class Step(val snapshot: JSONObject, val delayMs: Long)
    val id: String = json.getString("id")
    /** The bottom navigation destination: receive, transfers, storage or settings. */
    val page: String = json.getString("page")
    /** For onboarding: the screen to start on. */
    val step: String? = json.optString("step").ifEmpty { null }
    val title: String = json.optString("title", id)
    val expect: List<String> = json.optJSONArray("expect").strings()
    val actions: List<Pair<String, String>> = json.optJSONArray("actions").objects().map { it.optString("action") to it.optString("result") }
    val prefs: JSONObject = json.optJSONObject("prefs") ?: JSONObject()
    val snapshot: JSONObject = json.optJSONObject("snapshot") ?: JSONObject()
    /** Snapshots played when the page starts the receiving service. */
    val service: List<Step> = json.optJSONArray("service").objects().map { Step(it.getJSONObject("snapshot"), it.optLong("delay_ms")) }
    val stopped: JSONObject = json.optJSONObject("stopped") ?: JSONObject().put("phase", "idle")
    /** The pairing code a ready receiver shows. Synthetic values only. */
    val pairing: JSONObject? = json.optJSONObject("pairing")
    /** The scenario's clock, so Today and Yesterday stay the same on every review. */
    val nowMs: Long? = json.optLong("now_ms").takeIf { it > 0 }
    /** A sheet or page to open over [page]: `pairing`, `connect-mac` or `devices`. */
    val surface: String? = json.optString("surface").ifEmpty { null }
    /** What the camera reads when the page scans a code, after a short pause. Unset, the real camera opens. */
    val scan: String? = json.optString("scan").ifEmpty { null }
    /**
     * Fixed storage readings (`total_bytes`, `free_bytes`, `photos_bytes`), so the
     * hub's space hint and the Storage page show a designed state. Unset, the
     * pages read the device's own space and the catalog's own files in Photos.
     */
    val storage: JSONObject? = json.optJSONObject("storage")
    val core: Map<String, List<Answer>> = (json.optJSONObject("core") ?: JSONObject()).let { core ->
        core.keys().asSequence().associateWith { op ->
            val entry = core.get(op)
            val list = if (entry is JSONArray) entry.objects() else listOf(entry as JSONObject)
            list.map { Answer(if (it.has("value")) it.get("value") else null, it.optString("error").ifEmpty { null }, it.optLong("delay_ms")) }
        }
    }
}

private fun JSONArray?.strings() = if (this == null) emptyList() else (0 until length()).map { getString(it) }
private fun JSONArray?.objects() = if (this == null) emptyList() else (0 until length()).map { getJSONObject(it) }

/**
 * Replaces the receiver's outside world with the current scenario: core answers,
 * the receiving service and update checks. A core command the scenario does not
 * script fails with `catalog_unscripted` and is listed for the reviewer.
 */
internal object CatalogRuntime {
    private const val TAG = "DuckCatalog"
    private val main = Handler(Looper.getMainLooper())
    private val lock = Any()
    private var cursor = HashMap<String, Int>()
    private val missing = LinkedHashSet<String>()
    @Volatile var current: CatalogScenario? = null
        private set

    fun install() {
        NativeBridge.transport = ::answer
        ReceiverEnvironment.startService = { play() }
        ReceiverEnvironment.stopService = { publish(current?.stopped ?: JSONObject()) }
        ReceiverEnvironment.checksUpdates = false
        ReceiverEnvironment.previewImage = CatalogMedia::draw
    }

    val unscripted: List<String> get() = synchronized(lock) { missing.toList() }

    fun loadAll(context: Context): List<CatalogScenario> {
        val raw = context.assets.list("scenarios").orEmpty().filter { it.endsWith(".json") }.associate { name ->
            val json = JSONObject(context.assets.open("scenarios/$name").bufferedReader().use { it.readText() })
            json.getString("id") to json
        }
        fun resolve(id: String, seen: Set<String>): JSONObject {
            val json = raw[id] ?: error("unknown scenario $id")
            val base = json.optString("extends").ifEmpty { return json }
            check(base !in seen) { "extends cycle at $id" }
            val merged = JSONObject(resolve(base, seen + id).toString())
            for (key in json.keys()) {
                if (key == "extends") continue
                val value = json.get(key)
                if (key in setOf("core", "prefs", "snapshot") && value is JSONObject) {
                    val target = merged.optJSONObject(key) ?: JSONObject().also { merged.put(key, it) }
                    for (inner in value.keys()) target.put(inner, value.get(inner))
                } else merged.put(key, value)
            }
            return merged
        }
        // Bases only supply shared answers; they are not reviewed on their own.
        return raw.keys.sorted().map { resolve(it, emptySet()) }.filter { it.has("page") }.map(::CatalogScenario)
    }

    /** Makes [scenario] current: resets this app's preferences, seeds the scenario's and publishes its snapshot. */
    fun apply(context: Context, scenario: CatalogScenario) {
        CatalogMedia.reload(context)
        synchronized(lock) { cursor = HashMap(); missing.clear(); current = scenario }
        File(context.applicationInfo.dataDir, "shared_prefs").listFiles().orEmpty().forEach { file ->
            context.getSharedPreferences(file.nameWithoutExtension, Context.MODE_PRIVATE).edit().clear().commit()
        }
        for (name in scenario.prefs.keys()) {
            val values = scenario.prefs.getJSONObject(name)
            val editor = context.getSharedPreferences(name, Context.MODE_PRIVATE).edit()
            for (key in values.keys()) when (val value = values.get(key)) {
                is Boolean -> editor.putBoolean(key, value)
                is Int -> editor.putInt(key, value)
                is Long -> editor.putLong(key, value)
                is Number -> editor.putLong(key, value.toLong())
                else -> editor.putString(key, value.toString())
            }
            editor.commit()
        }
        ReceiverProgress.mutable.value = emptyMap()
        ReceiverEnvironment.now = scenario.nowMs?.let { fixed -> { fixed } } ?: System::currentTimeMillis
        val storage = scenario.storage
        ReceiverEnvironment.deviceStorage = if (storage == null) { context -> DeviceStorage.read(context) }
            else { _ -> DeviceStorage(storage.getLong("total_bytes"), storage.getLong("free_bytes")) }
        ReceiverEnvironment.galleryUsage = if (storage == null) { context -> GalleryInventory.read(context) }
            else { _ -> GalleryUsage(storage.optLong("photos_bytes"), storage.optLong("photos_count"), 0, 0, 0) }
        ReceiverEnvironment.scanOverride = scenario.scan?.let { payload -> { done -> main.postDelayed({ if (current === scenario) done(payload) }, 900) } }
        publish(scenario.snapshot, ReceiverSnapshot())
    }

    private fun play() {
        val scenario = current ?: return
        var at = 0L
        for (step in scenario.service) {
            at += step.delayMs
            main.postDelayed({ if (current === scenario) publish(step.snapshot) }, at)
        }
    }

    private fun publish(fields: JSONObject, base: ReceiverSnapshot = ReceiverState.snapshot.value) {
        val next = snapshot(base, fields)
        // As in the service: a running receiver has a pairing code, a stopped one has none.
        ReceiverState.pairing = current?.pairing?.takeIf { next.phase == "ready" }?.toString()
        ReceiverState.mutable.value = next
    }

    private fun snapshot(base: ReceiverSnapshot, json: JSONObject) = base.copy(
        phase = json.optString("phase", base.phase),
        published = json.optInt("published", base.published),
        error = if (json.has("error")) (if (json.isNull("error")) null else json.getString("error")) else base.error,
        received = json.optInt("received", base.received),
        total = json.optInt("total", base.total),
        failed = json.optInt("failed", base.failed),
        reservedBytes = json.optLong("reserved_bytes", base.reservedBytes),
        capacityBytes = json.optLong("capacity_bytes", base.capacityBytes),
        processingName = if (json.has("processing_name")) json.optString("processing_name").ifEmpty { null } else base.processingName,
        thermalHeld = json.optBoolean("thermal_held", base.thermalHeld),
        temperatureDeciCelsius = if (json.has("temperature_deci_celsius")) json.optInt("temperature_deci_celsius") else base.temperatureDeciCelsius,
        manualPaused = json.optBoolean("manual_paused", base.manualPaused),
    )

    private fun answer(request: String): String {
        val op = runCatching { JSONObject(request).getString("op") }.getOrDefault("?")
        val scenario = current
        val answer = synchronized(lock) {
            val list = scenario?.core?.get(op)
            if (list.isNullOrEmpty()) { missing += op; null } else {
                val index = cursor.getOrDefault(op, 0)
                cursor[op] = index + 1
                list[minOf(index, list.size - 1)]
            }
        }
        if (answer == null) {
            Log.w(TAG, "unscripted $op")
            return JSONObject().put("ok", false).put("error", "catalog_unscripted").toString()
        }
        if (answer.delayMs > 0) Thread.sleep(answer.delayMs)
        // A scenario switch while this answer waited belongs to the old page.
        if (current !== scenario) return JSONObject().put("ok", false).put("error", "catalog_cancelled").toString()
        answer.error?.let { return JSONObject().put("ok", false).put("error", it).toString() }
        val value = if (op == "receiver_history") CatalogMedia.history(answer.value) else answer.value
        return JSONObject().put("ok", true).put("value", value ?: JSONObject.NULL).toString()
    }
}
