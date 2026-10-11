package app.backupduck

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import android.system.Os
import org.json.JSONObject
import java.io.File
import androidx.exifinterface.media.ExifInterface
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

/** Preserve the sender's capture time without changing verified media bytes. */
internal object MediaDates {
    fun captured(metadata: JSONObject?): Long? = metadata?.optString("created_at_ms")
        ?.toLongOrNull()?.takeIf { it > 0 && it <= 253402300799000L }

    /** Return a temporary date-enriched copy only when EXIF has no capture date. */
    fun prepare(context: Context, source: File, mime: String, metadata: JSONObject?): File {
        // Stream-only senders can supply a trustworthy MediaStore capture date
        // separately while explicitly retaining the original container bytes.
        // DATE_TAKEN/file timestamps are still published by values/stampPending.
        if (metadata?.optString("backupduck_preserve_container_bytes") == "true") return source
        val captured = captured(metadata) ?: return source
        val extension = when (mime) {
            "image/jpeg" -> "jpg"
            "image/png" -> "png"
            "image/heic", "image/heif" -> "heic"
            else -> return source
        }
        val original = ExifInterface(source)
        if (original.dateTimeOriginal != null) return source
        val output = File(context.cacheDir, "dated-${UUID.randomUUID()}.$extension")
        val date = DateTimeFormatter.ofPattern("uuuu:MM:dd HH:mm:ss", Locale.ROOT)
            .withZone(ZoneOffset.UTC).format(Instant.ofEpochMilli(captured))
        try {
            if (extension == "heic") {
                NativeBridge.request(JSONObject().put("op", "write_photo_date")
                    .put("source", source.path).put("output", output.path).put("date", date).put("subsecond", captured % 1000))
            } else {
                source.copyTo(output)
                ExifInterface(output).apply {
                    setAttribute(ExifInterface.TAG_SUBSEC_TIME_ORIGINAL, "%03d".format(Locale.ROOT, captured % 1000))
                    setAttribute(ExifInterface.TAG_SUBSEC_TIME_DIGITIZED, "%03d".format(Locale.ROOT, captured % 1000))
                    setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, date)
                    setAttribute(ExifInterface.TAG_OFFSET_TIME_ORIGINAL, "+00:00")
                    setAttribute(ExifInterface.TAG_DATETIME_DIGITIZED, date)
                    setAttribute(ExifInterface.TAG_OFFSET_TIME_DIGITIZED, "+00:00")
                    saveAttributes()
                }
            }
            val exif = ExifInterface(output)
            check(exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL) == date &&
                exif.getAttribute(ExifInterface.TAG_OFFSET_TIME_ORIGINAL) == "+00:00" && exif.dateTimeOriginal == captured) { "publication_date_failed" }
            return output
        } catch (error: Exception) { output.delete(); throw error }
    }

    fun values(captured: Long?): ContentValues = ContentValues().apply {
        captured?.let {
            put(MediaStore.MediaColumns.DATE_TAKEN, it)
            // DATE_TAKEN is milliseconds; file modification dates are seconds.
            put(MediaStore.MediaColumns.DATE_MODIFIED, it / 1000)
        }
    }

    /** Do this after the last byte is written and before releasing IS_PENDING.
     * Android's scanner can replace the insert-time DATE_TAKEN with a date inferred
     * from the file. Missing EXIF must therefore fall back to the capture time,
     * not the time this receiver created the copy. No original file is edited.
     */
    fun stampPending(context: Context, uri: Uri, captured: Long?) {
        if (captured == null) return
        checkNotNull(context.contentResolver.openFileDescriptor(uri, "rw")).use { descriptor ->
            if (!File("/proc/self/fd/${descriptor.fd}").setLastModified(captured)) {
                // Newer MediaProvider/FUSE implementations may reject the
                // /proc alias even for an owned, writable pending item. A
                // provider fd may refer to the lower filesystem while DATA
                // uses FUSE, so their inode/device numbers can legitimately
                // differ. Resolve only this authoritative, owned pending row.
                val path = context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA,
                    MediaStore.MediaColumns.OWNER_PACKAGE_NAME, MediaStore.MediaColumns.IS_PENDING), null, null, null)?.use {
                    if (it.moveToFirst()) {
                        check(it.getString(1) == context.packageName && it.getInt(2) == 1) { "publication_date_failed" }
                        it.getString(0)
                    } else null
                } ?: error("publication_date_failed")
                check(File(path).setLastModified(captured)) { "publication_date_failed" }
            }
            check(Os.fstat(descriptor.fileDescriptor).st_mtime == captured / 1000) { "publication_date_failed" }
        }
    }
}
