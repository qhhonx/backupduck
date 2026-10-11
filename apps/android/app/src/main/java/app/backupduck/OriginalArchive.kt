package app.backupduck

import android.content.Context
import android.net.Uri
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.withLock
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

internal fun MainActivity.showArchiveIntro(choose:()->Unit):DuckConfirmation = duckConfirm(
    R.string.originals_export,R.string.originals_export_note,R.string.originals_choose,notice=R.string.duck_export_no_delete) {dialog->dialog.dismiss();choose()}
internal fun MainActivity.exportOriginals(uri:Uri) {
    val page=DuckPage(this,getString(R.string.originals_export));page.show()
    var job:Job?=null
    page.setOnDismissListener {job?.cancel()}
    val status=duckNotice(page.body,getString(R.string.originals_exporting),getString(R.string.originals_export_wait))
    val cancel=page.addAction(getString(R.string.duck_task_cancel)) {
        job?.cancel();page.body.removeAllViews();duckNotice(page.body,getString(R.string.duck_export_cancelled))
    }
    job=lifecycleScope.launch {
        try {
            val ticket=withContext(Dispatchers.IO) {ReceiverState.mediaOperations.withLock {
                OriginalArchive.export(this@exportOriginals,uri) {verifying,_ ->withContext(Dispatchers.Main) {
                    val words=(status as android.widget.LinearLayout).getChildAt(1) as android.widget.LinearLayout
                    (words.getChildAt(0) as android.widget.TextView).setText(if(verifying) R.string.duck_export_verifying else R.string.originals_exporting)
                }}
            }}
            cancel.visibility=android.view.View.GONE;page.setOnDismissListener(null);page.dismiss()
            val result=DuckSheet(this@exportOriginals,getString(R.string.originals_verified))
            duckNotice(result.body,getString(R.string.originals_verified),getString(R.string.originals_reclaim_confirmation,ticket.ids.size))
            result.body.addView(duckButton(getString(R.string.originals_keep)) {result.dismiss()},android.widget.LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(16)})
            result.body.addView(duckButton(getString(R.string.originals_reclaim)) {
                result.hide();var done=false
                val confirmation=duckConfirm(R.string.originals_reclaim,R.string.duck_export_verified_note,R.string.originals_reclaim,true,notice=R.string.duck_keep_source,busyNotice=R.string.duck_saving,
                    messageText=getString(R.string.originals_reclaim_confirmation,ticket.ids.size)) {dialog ->
                    dialog.busy(true)
                    lifecycleScope.launch {
                        val reclaimed=withContext(Dispatchers.IO) {runCatching {ReceiverState.mediaOperations.withLock {
                            OriginalArchive.verify(this@exportOriginals,ticket)
                            NativeBridge.request(JSONObject().put("op","release_archived").put("root",ticket.receiverRoot).put("ids",JSONArray(ticket.ids)).put("verified",JSONArray(ticket.resources.toList())))
                        }}}
                        dialog.busy(false)
                        reclaimed.onSuccess {done=true;dialog.dismiss();result.dismiss();duckAcknowledge(getString(R.string.originals_reclaimed))}
                            .onFailure {dialog.showFailure(R.string.originals_export_failed)}
                    }
                }
                confirmation.setOnDismissListener {if(!done)result.show()}
            },android.widget.LinearLayout.LayoutParams(-1,-2));result.show()
        } catch(cancelled:CancellationException) {throw cancelled}
        catch(error:Exception) {
            page.body.removeAllViews()
            if(error.message in listOf("archive_empty","not_found")) duckNotice(page.body,getString(R.string.originals_export_empty))
            else {duckProblem(page.body,getString(R.string.originals_export_failed));page.body.addView(duckButton(getString(R.string.duck_retry)) {page.dismiss();exportOriginals(uri)})}
        } finally {cancel.visibility=android.view.View.GONE}
    }
}
