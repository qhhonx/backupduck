package app.backupduck

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Synthetic database consumed by the real Rust pagination op, never a receiver or Photos write. */
internal object CatalogOrdering {
    private var root: File? = null
    private var trace: File? = null
    fun prepare(context: Context) {
        val directory = File(context.cacheDir, "ordering-${System.nanoTime()}").apply { mkdirs() }
        val store = File(directory, "store").apply { mkdirs() }
        SQLiteDatabase.openOrCreateDatabase(File(store, "receiver.sqlite3"), null).use { db ->
            db.execSQL("CREATE TABLE assets(id TEXT PRIMARY KEY,manifest TEXT,received INTEGER,processing TEXT,processing_error TEXT,originals_released INTEGER,release_reason TEXT,received_at_ms INTEGER,published_at_ms INTEGER,state_changed_at_ms INTEGER)")
            db.execSQL("CREATE TABLE receiver_history_revision(singleton INTEGER PRIMARY KEY,revision INTEGER)")
            db.execSQL("INSERT INTO receiver_history_revision VALUES(1,411)")
            db.execSQL("CREATE TABLE asset_senders(asset_id TEXT,sender_id TEXT)")
            db.beginTransaction()
            for (arrival in 1..411) {
                val id = digest("catalog-ordering-$arrival")
                // 12 days cross five 100-item pages. Arrival and change ranks disagree.
                val rank = (arrival * 139) % 411
                val changed = 1792713600000L - rank * 2_400_000L
                val failed = arrival == 7 || arrival == 307
                val manifest = JSONObject().put("version", 2).put("source_id", "ordering-$arrival").put("revision", "1").put("kind", "photo")
                    .put("metadata", JSONObject()).put("resources", JSONArray().put(JSONObject().put("role", "photo")
                        .put("filename", "ordering-$arrival.jpg").put("media_type", "image/jpeg").put("size", 1).put("sha256", digest("x"))))
                db.execSQL("INSERT INTO assets VALUES(?,?,1,?,?,0,NULL,?,?,?)", arrayOf(id, manifest.toString(), if (failed) "failed" else "complete",
                    if (failed) "storage_io" else null, 1791600000000L + arrival, if (failed) null else changed, changed))
            }
            db.setTransactionSuccessful(); db.endTransaction()
        }
        root = directory
        trace = File(context.getExternalFilesDir(null), "ordering-pages.jsonl").apply { writeText("") }
    }
    fun answer(query: JSONObject): String {
        val request = JSONObject(query.toString()).put("root", checkNotNull(root).path)
        val response = JSONObject(NativeBridge.call(request.toString()))
        val value = response.optJSONObject("value")
        if (value != null && !value.optBoolean("unchanged")) {
            // Keep the core reply as evidence before optional Catalog image metadata.
            synchronized(this) { trace?.appendText(JSONObject().put("query", request).put("page", value).toString()+"\n") }
            response.put("value", CatalogMedia.history(value))
        }
        return response.toString()
    }
    private fun digest(value: String) = MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
}
