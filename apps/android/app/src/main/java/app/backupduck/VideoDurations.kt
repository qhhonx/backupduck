package app.backupduck

import android.content.ContentValues
import android.content.Context
import android.database.DatabaseUtils
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import android.os.CancellationSignal
import android.os.OperationCanceledException
import android.os.SystemClock
import android.provider.MediaStore
import android.util.LruCache
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

/** Optional presentation metadata, never publication, playback or cloud evidence. */
internal class VideoDurationStore(context: Context, name: String = "video-durations.db",
    private val limit: Int = 20_000) : SQLiteOpenHelper(context, name, null, 1) {
    init { require(limit > 0) }
    private var count: Long? = null
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE durations (asset_id TEXT PRIMARY KEY, milliseconds INTEGER NOT NULL CHECK(milliseconds > 0), last_used INTEGER NOT NULL)")
        db.execSQL("CREATE INDEX durations_last_used ON durations(last_used, asset_id)")
    }
    override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) = Unit

    @Synchronized fun read(id: String): Long? {
        val db = readableDatabase
        val duration = db.query("durations", arrayOf("milliseconds"), "asset_id=?", arrayOf(id), null, null, null).use {
            if (it.moveToFirst()) it.getLong(0).takeIf { value -> value > 0 } else null
        }
        if (duration != null && !db.isReadOnly) runCatching {
            db.update("durations", ContentValues().apply {
                put("last_used", System.currentTimeMillis())
            }, "asset_id=?", arrayOf(id))
        }
        return duration
    }

    @Synchronized fun save(id: String, milliseconds: Long) {
        if (id.isBlank() || id.length > 128 || milliseconds <= 0) return
        val db = writableDatabase
        var nextCount = count
        var committed = false
        try {
            db.beginTransaction()
            try {
                val values = ContentValues().apply {
                    put("asset_id", id); put("milliseconds", milliseconds); put("last_used", System.currentTimeMillis())
                }
                val existing = db.update("durations", values, "asset_id=?", arrayOf(id)) > 0
                if (!existing) {
                    var rows = count ?: DatabaseUtils.queryNumEntries(db, "durations")
                    if (rows >= limit) {
                        // Amortize eviction, retaining a strict row cap without scanning the table per insert.
                        val batch = minOf(rows, (limit / 100).coerceIn(1, 128).toLong())
                        db.execSQL("DELETE FROM durations WHERE asset_id IN (SELECT asset_id FROM durations ORDER BY last_used, asset_id LIMIT ?)", arrayOf(batch))
                        rows -= batch
                    }
                    db.insertOrThrow("durations", null, values)
                    nextCount = rows + 1
                }
                db.setTransactionSuccessful()
            } finally { db.endTransaction() }
            committed = true
        } finally {
            // A failed commit may restore evicted rows. Recount before the next insertion.
            count = if (committed) nextCount else null
            // Some SQLite failures leave the native connection inside an uncommitted
            // transaction after endTransaction throws. Reopening discards that write.
            if (!committed) runCatching { close() }
        }
    }
}

/** Two readers shared by publication and visible cells; no background backlog or library scan. */
internal class VideoDurations(private val store: VideoDurationStore,
    private val resolve: (HistoryItem, CancellationSignal) -> Long?,
    private val clock: () -> Long = SystemClock::elapsedRealtime) {
    private data class Entry(val state: String, val duration: Long?, val checked: Long)
    private val memory = LruCache<String, Entry>(256)
    private fun state(item: HistoryItem) = "${item.receipt}:${item.processing}:${item.originalsReleased}"
    fun cached(item: HistoryItem): Long? = if (item.kind == "video" && ReceiverEnvironment.videoDuration == null) memory.get(item.id)?.duration else null

    fun remember(id: String, milliseconds: Long?) {
        val duration = milliseconds?.takeIf { it > 0 } ?: return
        // A full/read-only disk must not turn optional metadata into a publication failure.
        runCatching { store.save(id, duration) }
        memory.put(id, Entry("", duration, clock()))
    }

    suspend fun read(item: HistoryItem, signal: CancellationSignal): Long? {
        if (item.kind != "video") return null
        return withContext(Dispatchers.IO) {
            readers.withPermit {
                currentCoroutineContext().ensureActive(); signal.throwIfCanceled()
                ReceiverEnvironment.videoDuration?.let { synthetic ->
                    val value = synthetic(item, signal)?.takeIf { it > 0 }
                    currentCoroutineContext().ensureActive(); signal.throwIfCanceled()
                    return@withPermit value
                }
                val previous = memory.get(item.id)
                if (previous != null && (previous.duration != null ||
                    (previous.state == state(item) && clock() - previous.checked < 30_000))) return@withPermit previous.duration
                val retained = runCatching { store.read(item.id) }.getOrNull()
                currentCoroutineContext().ensureActive(); signal.throwIfCanceled()
                val duration = retained ?: runCatching { resolve(item, signal) }.getOrNull()?.takeIf { it > 0 }
                    ?: memory.get(item.id)?.duration
                currentCoroutineContext().ensureActive(); signal.throwIfCanceled()
                if (duration != null) remember(item.id, duration)
                else memory.put(item.id, Entry(state(item), null, clock()))
                duration
            }
        }
    }

    /** Best effort: busy readers skip this hint; visible cells can recover it later. */
    fun published(scope: CoroutineScope, context: Context, id: String, kind: String, locator: String) {
        if (kind != "video" || !readers.tryAcquire()) return
        val signal = CancellationSignal()
        // A separate suspended child can cancel the provider while the IO child
        // is inside a blocking Android query. There are at most two such pairs.
        val cancellation = scope.launch(start = CoroutineStart.UNDISPATCHED) {
            try { awaitCancellation() } finally { runCatching { signal.cancel() } }
        }
        val job = scope.launch(Dispatchers.IO) {
            try {
                val duration = indexedVideoDuration(context, Uri.parse(locator), signal)
                currentCoroutineContext().ensureActive(); signal.throwIfCanceled()
                remember(id, duration)
            } catch (_: OperationCanceledException) {
                // Android query cancellation is expected, not an uncaught service failure.
            }
        }
        // Also release when the service was already stopped before launch entered its body.
        job.invokeOnCompletion { try { cancellation.cancel() } finally { readers.release() } }
    }

    companion object {
        private val readers = Semaphore(2)
        private var shared: VideoDurations? = null
        @Synchronized fun get(context: Context): VideoDurations {
            shared?.let { return it }
            val app = context.applicationContext
            return VideoDurations(VideoDurationStore(app), { item, signal ->
                GalleryPreview.resolve(app, item, null, signal)?.let {
                    it.durationMs ?: indexedVideoDuration(app, it.uri, signal)
                }
            }).also { shared = it }
        }
    }
}

/** The media index can know a duration even when this device cannot decode a poster or play it. */
internal fun indexedVideoDuration(context: Context, uri: Uri, signal: CancellationSignal): Long? {
    signal.throwIfCanceled()
    return runCatching {
        context.contentResolver.query(uri, arrayOf(MediaStore.Video.Media.DURATION), null, null, null, signal)?.use {
            if (it.moveToFirst() && !it.isNull(0)) it.getLong(0).takeIf { value -> value > 0 } else null
        }
    }.getOrNull().also { signal.throwIfCanceled() }
}

/** Keep the grid clock compact while full duration remains in detail and accessibility. */
internal fun videoDurationLabel(milliseconds: Long?): String? {
    if (milliseconds == null || milliseconds <= 0) return null
    val seconds = milliseconds / 1000 + if (milliseconds % 1000 >= 500) 1 else 0
    val hours = seconds / 3600
    return when {
        hours >= 100 -> String.format(Locale.ROOT, "%dh", hours)
        hours > 0 -> String.format(Locale.ROOT, "%dh%02d", hours, seconds / 60 % 60)
        else -> String.format(Locale.ROOT, "%d:%02d", seconds / 60, seconds % 60)
    }
}
