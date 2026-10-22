package app.backupduck

import android.content.Context
import android.graphics.BitmapFactory
import android.location.Geocoder
import android.media.MediaMetadataRetriever
import android.net.ConnectivityManager
import android.net.Uri
import android.os.CancellationSignal
import android.provider.MediaStore
import android.util.LruCache
import androidx.exifinterface.media.ExifInterface as Exif
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal data class PhotoMetadata(val camera: String? = null, val lens: String? = null,
    val aperture: Double? = null, val exposure: Double? = null, val focal: Double? = null,
    val equivalent: Int? = null, val iso: Int? = null, val width: Int? = null, val height: Int? = null,
    val bytes: Long? = null, val format: String? = null, val durationMs: Long? = null,
    val live: Boolean = false, val gps: Pair<Double, Double>? = null, val place: String? = null) {
    fun capture(locale: Locale): String? {
        fun n(value: Double) = java.text.NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = 2 }.format(value)
        return listOfNotNull(aperture?.let { "ƒ/${n(it)}" }, exposure?.let {
            // Only use a reciprocal when it represents the recorded value accurately.
            val denominator = kotlin.math.round(1 / it)
            if (it < 1 && kotlin.math.abs(denominator * it - 1) < 1e-9) "1/${n(denominator)} s" else "${java.math.BigDecimal.valueOf(it).stripTrailingZeros().toPlainString()} s"
        }, focal?.let { "${n(it)} mm" }, equivalent?.let { "${it} mm (35 mm)" }, iso?.let { "ISO $it" })
            .map { it.replace(' ', '\u00a0') }.joinToString(" · ").ifBlank { null }
    }
}

/** Metadata is read from retained originals, then the owned gallery copy. Never from a thumbnail. */
internal object PhotoMetadataReader {
    private val cache = LruCache<String, PhotoMetadata>(96)
    private val geocoding = AtomicBoolean(false)
    private val geocoderWorker = Executors.newSingleThreadExecutor { task -> Thread(task, "photo-place").apply { isDaemon = true } }
    fun clearCache() = cache.evictAll()
    fun read(context: Context, item: HistoryItem, signal: CancellationSignal): PhotoMetadata {
        val key = "${item.id}:${item.receipt}:${item.processing}:${item.originalsReleased}:${context.resources.configuration.locales[0]}"
        signal.throwIfCanceled()
        cache.get(key)?.let { return it }
        val sources = ReceiverEnvironment.metadataFiles?.invoke(item) ?: originals(context, item, signal)
        val source = sources.firstOrNull { it.first.isFile }
        val published = if (source == null) runCatching { GalleryPreview.resolve(context, item, null, signal) }.getOrNull() else null
        val uri = source?.first?.let(Uri::fromFile) ?: published?.uri ?: return PhotoMetadata()
        val resolver = context.contentResolver
        val header = resolver.openInputStream(uri)?.use { input -> ByteArray(4096).let { b -> val count = input.read(b); b.copyOf(count.coerceAtLeast(0)) } }
        signal.throwIfCanceled()
        val mime = header?.let(MediaContainer::imageMime) ?: source?.second ?: published?.mime
        var bytes = source?.first?.length()?.takeIf { it > 0 }
        var width: Int? = null; var height: Int? = null
        var duration = published?.durationMs
        if (uri.scheme == "content") runCatching {
            resolver.query(uri, arrayOf(MediaStore.MediaColumns.WIDTH, MediaStore.MediaColumns.HEIGHT, MediaStore.MediaColumns.SIZE), null, null, null, signal)?.use { c ->
                if (c.moveToFirst()) { width = c.getInt(0).takeIf { it > 0 }; height = c.getInt(1).takeIf { it > 0 }; bytes = c.getLong(2).takeIf { it > 0 } }
            }
        }
        val format = when (mime) { "image/heic", "image/heif" -> "HEIC"; "image/jpeg" -> "JPEG"; "image/png" -> "PNG"; "video/quicktime" -> "MOV"; "video/mp4" -> "MP4"; else -> null }
        var result = PhotoMetadata()
        if (mime?.startsWith("image/") == true) {
            runCatching { resolver.openInputStream(uri)?.use { input ->
                signal.setOnCancelListener { runCatching { input.close() } }
                try {
                    val exif = Exif(input)
                    fun attr(tag: String) = exif.getAttribute(tag)?.trim()?.takeIf { it.isNotBlank() }
                    fun number(tag: String) = exif.getAttributeDouble(tag, Double.NaN).takeIf { it.isFinite() && it > 0 }
                    val model = attr(Exif.TAG_MODEL); val make = attr(Exif.TAG_MAKE)
                    val camera = photoCameraName(make, model)
                    width = width ?: number(Exif.TAG_IMAGE_WIDTH)?.toInt()
                    height = height ?: number(Exif.TAG_IMAGE_LENGTH)?.toInt()
                    val gps = exif.latLong?.takeIf { it[0].isFinite() && it[1].isFinite() && it[0] in -90.0..90.0 && it[1] in -180.0..180.0 }?.let { it[0] to it[1] }
                    result = PhotoMetadata(camera, attr(Exif.TAG_LENS_MODEL), number(Exif.TAG_F_NUMBER), number(Exif.TAG_EXPOSURE_TIME),
                        number(Exif.TAG_FOCAL_LENGTH), number(Exif.TAG_FOCAL_LENGTH_IN_35MM_FILM)?.toInt(), number(Exif.TAG_PHOTOGRAPHIC_SENSITIVITY)?.toInt(), gps = gps)
                } finally { signal.setOnCancelListener(null) }
            } }
            signal.throwIfCanceled()
            if (width == null || height == null) runCatching { resolver.openInputStream(uri)?.use { input ->
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeStream(input, null, bounds)
                width = bounds.outWidth.takeIf { it > 0 }; height = bounds.outHeight.takeIf { it > 0 }
            } }
        }
        fun videoInfo(video: Uri, dimensions: Boolean) { runCatching { MediaMetadataRetriever().use { media ->
            signal.throwIfCanceled(); media.setDataSource(context, video)
            if (dimensions) {
                width = media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()?.takeIf { it > 0 }
                height = media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()?.takeIf { it > 0 }
            }
            duration = media.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.takeIf { it > 0 }
        } } }
        if (mime?.startsWith("video/") == true) videoInfo(uri, true)
        val motion = sources.firstOrNull { it.second.startsWith("video/") && it.first.isFile }
        val paired = item.kind == "motion" && source?.second?.startsWith("image/") == true && motion != null
        if (paired) videoInfo(Uri.fromFile(motion!!.first), false)
        signal.throwIfCanceled()
        result = result.copy(width = width, height = height, bytes = bytes, format = format, durationMs = duration, live = paired,
            place = result.gps?.let { offlinePlace(context, it, signal) })
        signal.throwIfCanceled()
        cache.put(key, result)
        return result
    }
    private fun originals(context: Context, item: HistoryItem, signal: CancellationSignal): List<Pair<File, String>> {
        if (item.receipt != "received" || item.originalsReleased) return emptyList()
        // The core supplies identity and paths; the host never queries its database or guesses blob names.
        return runCatching {
            val rows = if (item.processing == "complete") {
                NativeBridge.request(JSONObject().put("op", "archive_batch").put("root", "${context.filesDir}/receiver")) as JSONArray
            } else {
                NativeBridge.request(JSONObject().put("op", "publications").put("after", item.id.dropLast(1))) as JSONArray
            }
            signal.throwIfCanceled()
            val row = (0 until rows.length()).asSequence().map(rows::getJSONObject).firstOrNull { it.getString("id") == item.id } ?: return@runCatching emptyList()
            val resources = row.getJSONObject("asset").getJSONArray("resources")
            (0 until resources.length()).map { resources.getJSONObject(it) }.sortedBy { if (it.getString("media_type").startsWith("image/")) 0 else 1 }
                .map { File(row.getJSONObject("resources").getString(it.getString("sha256"))) to it.getString("media_type") }
        }.getOrElse { signal.throwIfCanceled(); emptyList() }
    }
    private fun offlinePlace(context: Context, gps: Pair<Double, Double>, signal: CancellationSignal): String? {
        // Geocoder implementations may use a network. Only ask with no active network; never transmit GPS.
        if ((context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).activeNetwork != null || !Geocoder.isPresent() || !geocoding.compareAndSet(false, true)) return null
        val future = geocoderWorker.submit<String?> {
            try {
                @Suppress("DEPRECATION")
                val address = Geocoder(context.applicationContext, context.resources.configuration.locales[0]).getFromLocation(gps.first, gps.second, 1)?.firstOrNull()
                listOfNotNull(address?.locality, address?.adminArea, address?.countryName).distinct().joinToString(", ").ifBlank { null }
            } finally { geocoding.set(false) }
        }
        signal.setOnCancelListener { future.cancel(true) }
        return try { future.get(350, TimeUnit.MILLISECONDS) } catch (_: Exception) { future.cancel(true); null }
            .also { signal.setOnCancelListener(null); signal.throwIfCanceled() }
    }
}

internal fun photoCameraName(make: String?, model: String?): String? {
    val brand = make?.replace(Regex("(?i)\\s+(corporation|corp\\.?|inc\\.?)$"), "")?.trim()
    return when {
        model == null -> brand
        brand == null || model.contains(brand, ignoreCase = true) || (brand.equals("Apple", true) && model.startsWith("iPhone")) -> model
        else -> "$brand $model"
    }
}

/** Keep recorded fractional seconds instead of rounding a short clip to zero. */
internal fun photoDuration(milliseconds: Long): String {
    val seconds = milliseconds / 1000
    val clock = if (seconds >= 3600) String.format(Locale.ROOT, "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        else String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60)
    val fraction = milliseconds % 1000
    return clock + if (fraction == 0L) "" else String.format(Locale.ROOT, ".%03d", fraction).trimEnd('0')
}
