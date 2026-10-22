package app.backupduck

import android.content.Context
import android.graphics.ColorSpace
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.util.Log
import android.util.LruCache
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import kotlin.math.ceil

/** Optional, local-only sample media. This source is compiled into the catalog alone. */
internal object CatalogMedia {
    private var appContext: Context? = null
    private data class Photo(val file: File, val takenMs: Long?)
    private class Pool(val photos: List<Photo>) {
        // Share decoded pool photos across scenario IDs without retaining full-size originals.
        val images = object : LruCache<String, Bitmap>(16 * 1024 * 1024) {
            override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
        }

        fun photo(id: String): Photo {
            val chosen = when (id) {
                "catalog-2000", "metadata-video", "metadata-live" -> "0013.jpg"
                "catalog-1999" -> "metadata-gps.heic"
                "catalog-1998" -> "0023.jpg"
                "metadata-portrait" -> "0020.jpg"
                "metadata-landscape" -> "0013.jpg"
                "metadata-square" -> "0763.jpg"
                else -> null
            }
            photos.firstOrNull { it.file.name == chosen }?.let { return it }
            // Fixed UTF-8 hash; independent of process, locale and runtime hash randomization.
            var hash = 1469598103934665603uL
            for (byte in id.toByteArray(Charsets.UTF_8)) {
                hash = (hash xor byte.toUByte().toULong()) * 1099511628211uL
            }
            return photos[(hash % photos.size.toULong()).toInt()]
        }
    }

    @Volatile private var pool: Pool? = null
    private val synthetic = object : LruCache<String, Bitmap>(4 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }

    /** Reload on scenario entry so a newly pushed pool needs only a scenario restart. */
    fun reload(context: Context) {
        appContext = context.applicationContext
        pool = runCatching {
            val external = context.getExternalFilesDir(null) ?: return@runCatching null
            val root = File(external, "catalog-media").canonicalFile
            val manifest = File(root, "manifest.json")
            if (!manifest.isFile) return@runCatching null
            val rows = JSONObject(manifest.readText()).getJSONArray("photos")
            val photos = (0 until rows.length()).map { index ->
                val row = rows.getJSONObject(index)
                val relative = row.getString("file")
                require(!File(relative).isAbsolute) { "Expected a pool-relative file" }
                val file = File(root, relative).canonicalFile
                require(file.path.startsWith(root.path + File.separator)) { "File leaves media pool" }
                Photo(file, taken(row.optString("taken")))
            }
            photos.takeIf { it.isNotEmpty() }?.let(::Pool)
        }.onFailure { Log.w("DuckCatalog", "Media manifest unavailable; using synthetic photos", it) }.getOrNull()
        synthetic.evictAll()
        Log.i("DuckCatalog", "Catalog media: ${pool?.photos?.size ?: 0} pool entries; synthetic fallback enabled")
    }

    private fun taken(value: String): Long? = runCatching { OffsetDateTime.parse(value).toInstant().toEpochMilli() }
        .recoverCatching { LocalDateTime.parse(value).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli() }
        .recoverCatching { LocalDate.parse(value).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli() }.getOrNull()

    /** Copy scripted answers; never overwrite an explicit scenario capture date or receipt time. */
    fun history(value: Any?): Any? {
        val active = pool ?: return value
        val source = value as? JSONObject ?: return value
        val copy = JSONObject(source.toString())
        val items = copy.optJSONArray("items") ?: return value
        for (index in 0 until items.length()) {
            val item = items.getJSONObject(index)

            val id = item.optString("id").takeIf { it.isNotEmpty() } ?: continue
            val photo = active.photo(id)
            val original = originalsFor(id, item.optString("kind"))
            item.put("filename", original.firstOrNull()?.first?.name ?: photo.file.name)
            item.put("total_bytes", original.sumOf { it.first.length() })
            if (item.optLong("captured_at_ms") <= 0) photo.takenMs?.let { item.put("captured_at_ms", it) }
        }
        return copy
    }

    /** Read the unmodified pool file with the production metadata parser. */
    fun originals(item: HistoryItem): List<Pair<File, String>> = originalsFor(item.id, item.kind)
    private fun originalsFor(id: String, kind: String): List<Pair<File, String>> {
        val photo = pool?.photo(id)?.file?.takeIf { it.isFile } ?: return emptyList()
        val still = photo to if (photo.extension.equals("heic", true)) "image/heic" else "image/jpeg"
        val video = File(photo.parentFile, "metadata-video.mov").takeIf { it.isFile }?.let { it to "video/quicktime" }
        return when {
            id == "metadata-video" -> listOfNotNull(video)
            id == "metadata-live" && kind == "motion" -> listOfNotNull(still, video)
            else -> listOf(still)
        }
    }

    /** PhotoImages calls this on its bounded IO workers and retains view cancellation/identity. */
    fun draw(item: HistoryItem, width: Int, height: Int): Bitmap = draw(item.id, width, height)

    private fun draw(id: String, width: Int, height: Int): Bitmap {
        // A granted, read-only reference remains in MediaStore; never copy it into Photos.
        CatalogRuntime.referenceUri?.let { uri -> appContext?.let { context ->
            runCatching { GalleryPreview.decode(context, GalleryPreviewCopy(uri, context.contentResolver.getType(uri) ?: "image/png", null),
                android.util.Size(width, height), android.os.CancellationSignal()) }.getOrNull()?.let { return it }
        } }

        // Bucket nearby cell sizes; cap viewer decode size and memory on older devices.
        fun target(size: Int) = ((size.coerceIn(1, 2048) + 63) / 64) * 64
        val w = target(width)
        val h = target(height)
        val active = pool
        if (active != null) {
            val photo = active.photo(id)
            val key = "${photo.file.path}:${w}x$h"
            active.images.get(key)?.let { return it }
            val image = runCatching {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(photo.file)) { decoder, info, _ ->
                    val size = info.size
                    val scale = minOf(1.0, maxOf(w.toDouble() / size.width, h.toDouble() / size.height),
                        2048.0 / maxOf(size.width, size.height))
                    decoder.setTargetSize(ceil(size.width * scale).toInt().coerceAtLeast(1),
                        ceil(size.height * scale).toInt().coerceAtLeast(1))
                    // Normalize grayscale ICC profiles before JPEG export and subsequent decoding.
                    decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                }
            }.getOrNull()
            if (image != null) {
                active.images.put(key, image)
                return image
            }
        }
        val key = "${id}:${w}x$h"
        return synthetic.get(key) ?: SyntheticPhotos.draw(id, w, h).also { synthetic.put(key, it) }
    }

    /** Materialize scripted availability through the same ID mapping as published photos. */
    @Synchronized fun preview(request: JSONObject, value: Any?): Any? {
        val source = value as? JSONObject ?: return value
        if (source.optString("status") != "available") return value
        val id = request.getString("id")
        val directory = File(request.getString("cache_dir"), "catalog-receiver-previews").apply { mkdirs() }
        val name = MessageDigest.getInstance("SHA-256").digest(id.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        val file = File(directory, "$name.jpg")
        val original = draw(id, 512, 512)
        val scale = minOf(1.0, 512.0 / maxOf(original.width, original.height))
        val preview = if (scale == 1.0) original else Bitmap.createScaledBitmap(original,
            (original.width * scale).toInt().coerceAtLeast(1), (original.height * scale).toInt().coerceAtLeast(1), true)
        val temporary = File(directory, "$name.tmp")
        try {
            temporary.outputStream().use { check(preview.compress(Bitmap.CompressFormat.JPEG, 80, it)) }
            check(temporary.renameTo(file))
        } finally {
            temporary.delete()
            if (preview !== original) preview.recycle()
        }
        return JSONObject().put("status", "available").put("path", file.absolutePath)
            .put("cache_hit", false).put("max_edge", 512)
    }
}
