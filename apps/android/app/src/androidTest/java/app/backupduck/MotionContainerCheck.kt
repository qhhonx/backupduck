package app.backupduck

import android.app.Instrumentation
import android.graphics.ImageDecoder
import android.os.Bundle
import androidx.exifinterface.media.ExifInterface
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Opt-in file-only check in the isolated validation app; never publishes media. */
internal fun Instrumentation.checkMotionContainer(arguments: Bundle): String {
    check(targetContext.packageName.endsWith(".validation")) { "validation_app_required" }
    val still = File(targetContext.filesDir, "motion-container-still.JPG")
    val video = File(targetContext.filesDir, "motion-container-paired.MOV")
    val expectedMime = arguments.getString("mime") ?: "image/heic"
    check(expectedMime in listOf("image/heic", "image/jpeg"))
    val output = File(targetContext.filesDir, "motion-container-result.${if (expectedMime == "image/heic") "heic" else "jpg"}")
    val captured = requireNotNull(arguments.getString("captured"))
    val metadata = JSONObject().put("created_at_ms", captured)
    fun digest(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).toList()
    val beforeStill = digest(still)
    val beforeVideo = digest(video)
    val declaredMime = if (expectedMime == "image/heic") "image/jpeg" else "image/heic"
    val mime = MediaContainer.imageMime(still, declaredMime)
    check(mime == expectedMime) { "container_type_wrong" }
    val dated = MediaDates.prepare(targetContext, still, mime, metadata)
    try {
        if (output.exists()) check(output.delete())
        NativeBridge.request(JSONObject().put("op", if (mime == "image/heic") "package_heic_motion" else "package_motion")
            .put(if (mime == "image/heic") "heic" else "jpeg", dated.path)
            .put(if (mime == "image/heic") "mov" else "mp4", video.path).put("output", output.path)
            .put("video_mime", "video/quicktime").put("metadata", metadata))
        val exif = ExifInterface(output)
        check(exif.dateTimeOriginal == captured.toLong()) { "capture_time_wrong" }
        // ExifInterface 1.3.7 can read HEIC dates but does not expose HEIC XMP.
        // Check the embedded packet here; the container reference is verified
        // by the native writer's tests and independent metadata inspection.
        val header = output.inputStream().use { input ->
            val bytes = ByteArray(1024 * 1024)
            val count = input.read(bytes)
            String(bytes, 0, count, Charsets.ISO_8859_1)
        }
        check(header.contains("GCamera:MotionPhoto=\"1\"")) { "motion_metadata_missing" }
        val before = ImageDecoder.decodeBitmap(ImageDecoder.createSource(still)) { decoder, _, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
        val after = ImageDecoder.decodeBitmap(ImageDecoder.createSource(output)) { decoder, _, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
        try { check(before.sameAs(after)) { "pixels_changed" } }
        finally { before.recycle(); after.recycle() }
        check(digest(still) == beforeStill && digest(video) == beforeVideo) { "original_bytes_changed" }
        return "PASS: declared=$declaredMime; actual=$mime; date, motion metadata and decoded pixels verified; originals unchanged; no MediaStore rows created"
    } finally { if (dated != still) dated.delete() }
}
