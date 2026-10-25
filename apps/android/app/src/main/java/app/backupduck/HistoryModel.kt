package app.backupduck

import androidx.lifecycle.ViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject

internal data class HistoryItem(val cursor: Long, val id: String, val filename: String, val kind: String,
    val totalBytes: Long, val confirmedBytes: Long, val receipt: String, val processing: String,
    val processingError: String?, val originalsReleased: Boolean, val releaseReason: String? = null, val senderNames: String = "", val capturedAtMs: Long? = null, val burstPrimary: Boolean? = null, val receivedAtMs: Long? = null, val publishedAtMs: Long? = null, val stateChangedAtMs: Long? = null) {
    val statusLabel: Int get() = when {
        receipt != "received" -> R.string.receiver_item_receiving
        processing == "complete" -> R.string.receiver_item_published
        processing == "failed" -> R.string.receiver_item_failed
        else -> R.string.receiver_item_received
    }
}
internal data class HistoryCounts(val total:Int,val published:Int,val failed:Int)
internal data class HistoryState(val items: List<HistoryItem> = emptyList(), val total: Int = 0,
    val nextCursor: String? = null, val loading: Boolean = false, val failed: Boolean = false,
    val filter: String = "all", val kind: String = "all", val sender: String? = null,
    val counts:HistoryCounts? = null, val revision: Long? = null)

/** Rust applies filters and cursor pagination. UI keeps only requested pages. */
internal class HistoryModel(private val readPage:(JSONObject)->JSONObject = { NativeBridge.request(it) as JSONObject }) : ViewModel() {
    private val mutable = MutableStateFlow(HistoryState())
    val state = mutable.asStateFlow()
    private val requests = Mutex()
    private var generation = 0
    private var loadedOnce=false
    private var selecting=false
    suspend fun select(root: String, filter: String = mutable.value.filter, kind: String = mutable.value.kind, sender: String? = mutable.value.sender) {
        val requestedGeneration=++generation
        selecting=true
        try {load(root,replace=true,selection=HistoryState(filter=filter,kind=kind,sender=sender))} finally {if(requestedGeneration==generation)selecting=false}
    }
    suspend fun more(root: String) {
        if (mutable.value.nextCursor == null) return
        if (!selecting&&!mutable.value.loading) load(root, replace = false)
    }
    // A revision check is cheap. When state changes, replace the loaded prefix
    // atomically from one new snapshot; never splice pages from two timelines.
    suspend fun refreshVisible(root: String, @Suppress("UNUSED_PARAMETER") firstVisible: Int) {
        if (selecting || mutable.value.loading) return
        load(root, replace = true, refresh = true)
    }

    private fun parse(data: JSONObject): HistoryState {
        val rows = data.getJSONArray("items")
        val items = (0 until rows.length()).map { i ->
            val row = rows.getJSONObject(i)
            val peers = row.optJSONArray("senders")
            val names = if (peers == null) "" else (0 until peers.length()).joinToString(SENDER_SEPARATOR) { peers.getJSONObject(it).getJSONObject("profile").getString("name") }
            HistoryItem(row.getLong("cursor"), row.getString("id"), row.getString("filename"), row.getString("kind"),
                row.getLong("total_bytes"), row.getLong("confirmed_bytes"), row.getString("receipt"),
                row.getString("processing"), row.optString("processing_error").takeIf { !row.isNull("processing_error") },
                row.getBoolean("originals_released"), row.optString("release_reason").takeIf { it == "gallery" || it == "archive" }, names,
                row.optLong("captured_at_ms").takeIf { it > 0 }, if (row.isNull("burst_primary")) null else row.getBoolean("burst_primary"),
                row.optLong("received_at_ms").takeIf { it > 0 }, row.optLong("published_at_ms").takeIf { it > 0 },
                row.optLong("state_changed_at_ms").takeIf { it > 0 })
        }
        val counts = data.optJSONObject("counts")?.let { HistoryCounts(it.getInt("total"), it.getInt("published"), it.getInt("failed")) }
        return HistoryState(items = items, total = data.getInt("total"), nextCursor = if (data.isNull("next_cursor")) null else data.getString("next_cursor"),
            counts = counts, revision = if (data.has("revision")) data.getLong("revision") else null)
    }

    private suspend fun load(root: String, replace: Boolean, refresh: Boolean = false, selection: HistoryState? = null) {
        val expected = generation
        requests.withLock {
            if (expected != generation) return
            val previous = mutable.value
            val snapshot = selection ?: previous
            // A queued scroll may follow a refresh that replaced its cursor.
            // Resolve the continuation under the same lock as the loaded prefix.
            val continuation = if (replace) null else previous.nextCursor ?: return
            if (!refresh && (selection == null || !loadedOnce)) mutable.value = snapshot.copy(loading = true, failed = false)
            val result = withContext(Dispatchers.IO) { runCatching {
                fun fetch(cursor: String?, revision: Long? = null): JSONObject {
                    val query = JSONObject().put("op", "receiver_history_latest").put("root", root)
                        .put("state", snapshot.filter).put("kind", snapshot.kind)
                    snapshot.sender?.let { query.put("sender_id", it) }
                    cursor?.let { query.put("cursor", it) }
                    revision?.let { query.put("known_revision", it) }
                    return readPage(query)
                }
                fun prefix(target: Int, knownRevision: Long?): HistoryState? {
                    val data = fetch(null, knownRevision)
                    if (data.optBoolean("unchanged")) return null
                    var page = parse(data)
                    val items = page.items.toMutableList()
                    while (items.size < target && page.nextCursor != null) {
                        page = parse(fetch(page.nextCursor)); items.addAll(page.items)
                    }
                    return page.copy(items = items)
                }
                if (replace) prefix(if (refresh) snapshot.items.size.coerceAtLeast(100) else 100, if (refresh) snapshot.revision else null)
                else try {
                    val page = parse(fetch(continuation))
                    page.copy(items = snapshot.items + page.items)
                } catch (error: Exception) {
                    if (!error.message.orEmpty().contains("history_snapshot_expired")) throw error
                    prefix(snapshot.items.size + 100, null)
                }
            } }
            if (expected != generation) return
            loadedOnce = true
            result.onSuccess { update ->
                if (update != null) mutable.value = snapshot.copy(items = update.items, total = update.total,
                    nextCursor = update.nextCursor, loading = false, failed = false, counts = update.counts, revision = update.revision)
                else mutable.value = snapshot.copy(loading = false, failed = false)
            }.onFailure { mutable.value = (if (selection != null) previous else snapshot).copy(loading = false, failed = true) }
        }
    }
}
