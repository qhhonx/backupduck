package app.backupduck

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

internal data class ArchiveEntry(val digest: String, val size: Long)
internal data class ArchiveTicket(val uri: Uri, val receiverRoot: String, val ids: List<String>, val entries: Map<String, ArchiveEntry>, val resources: Set<String>)
internal object OriginalArchive {
    private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private suspend fun copy(input: InputStream, limit: Long, write: (ByteArray, Int) -> Unit): ArchiveEntry {
        val hash = MessageDigest.getInstance("SHA-256"); val buffer = ByteArray(65536); var size = 0L
        while (true) {
            currentCoroutineContext().ensureActive()
            val count = input.read(buffer); if (count < 0) break
            check(count.toLong() <= limit - size) { "archive_integrity" }
            hash.update(buffer, 0, count); size += count; write(buffer, count)
        }
        return ArchiveEntry(hash.digest().joinToString("") { "%02x".format(it) }, size)
    }
    suspend fun export(context: Context, uri: Uri, receiverRoot: String = "${context.filesDir}/receiver",progress:suspend (Boolean,Int)->Unit={_,_->}): ArchiveTicket {
        val items = NativeBridge.request(JSONObject().put("op", "archive_batch").put("root", receiverRoot)) as JSONArray
        check(items.length() > 0) { "archive_empty" }
        val entries = linkedMapOf<String, ArchiveEntry>(); val ids = mutableListOf<String>(); val digests = mutableSetOf<String>()
        checkNotNull(context.contentResolver.openOutputStream(uri, "wt")).use { output ->
            ZipOutputStream(output).use { zip ->
                for (index in 0 until items.length()) {
                    progress(false,index)
                    val item = items.getJSONObject(index); val id = item.getString("id"); ids += id
                    val asset = item.getJSONObject("asset"); val metadata = asset.toString().toByteArray(Charsets.UTF_8)
                    val manifest = "$id/manifest.json"; zip.putNextEntry(ZipEntry(manifest)); zip.write(metadata); zip.closeEntry()
                    entries[manifest] = ArchiveEntry(digest(metadata), metadata.size.toLong())
                    val resources = asset.getJSONArray("resources")
                    for (r in 0 until resources.length()) {
                        val resource = resources.getJSONObject(r); val hash = resource.getString("sha256")
                        val name = "$id/${resource.getString("role")}-${resource.getString("filename")}"
                        val expected = ArchiveEntry(hash, resource.getLong("size")); check(entries.put(name, expected) == null)
                        zip.putNextEntry(ZipEntry(name))
                        val actual = File(item.getJSONObject("resources").getString(hash)).inputStream().use { input -> copy(input, expected.size) { b, n -> zip.write(b, 0, n) } }
                        check(actual == expected) { "archive_integrity" }; zip.closeEntry(); digests += hash
                    }
                }
            }
        }
        val ticket = ArchiveTicket(uri, receiverRoot, ids, entries, digests)
        progress(true,ids.size)
        verify(context, ticket)
        NativeBridge.request(JSONObject().put("op", "record_event").put("receiver", true).put("root", receiverRoot).put("code", "original_archive_verified"))
        return ticket
    }
    suspend fun verify(context: Context, ticket: ArchiveTicket) {
        val remaining = ticket.entries.toMutableMap()
        checkNotNull(context.contentResolver.openInputStream(ticket.uri)).use { input ->
            ZipInputStream(input).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val expected = remaining.remove(entry.name) ?: error("archive_integrity")
                    check(copy(zip, expected.size) { _, _ -> } == expected) { "archive_integrity" }; zip.closeEntry()
                }
            }
        }
        check(remaining.isEmpty()) { "archive_integrity" }
    }
}
