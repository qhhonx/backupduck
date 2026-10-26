package app.backupduck

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.util.Size
import java.io.File
import kotlin.math.max

/**
 * A small private picture of each saved photo, kept after the copy in Photos is
 * removed (for example by Google Photos' Free up space), so the Received page
 * stays browsable. It is only a picture: never evidence of a copy anywhere.
 */
internal object ReceiptThumbnails {
    /** Long side in pixels; about 10 KB each as lossy WebP. */
    private const val SIDE = 320
    private val safeID = Regex("^[A-Za-z0-9_-]{1,128}$")

    private fun file(context: Context, id: String): File? =
        if (safeID.matches(id)) File(File(context.filesDir, "receipt-thumbnails"), "$id.webp") else null

    fun has(context: Context, id: String) = file(context, id)?.isFile == true

    fun read(context: Context, id: String): Bitmap? =
        file(context, id)?.takeIf { it.isFile }?.let { runCatching { BitmapFactory.decodeFile(it.absolutePath) }.getOrNull() }

    /** Keeps the first picture for an item; later calls are no-ops. */
    fun save(context: Context, id: String, image: Bitmap) {
        val target = file(context, id) ?: return
        if (target.isFile) return
        runCatching {
            target.parentFile?.mkdirs()
            val scale = SIDE.toFloat() / max(image.width, image.height)
            val small = if (scale < 1f) Bitmap.createScaledBitmap(image,
                (image.width * scale).toInt().coerceAtLeast(1), (image.height * scale).toInt().coerceAtLeast(1), true) else image
            val partial = File(target.parentFile, "${target.name}.partial")
            partial.outputStream().use {
                @Suppress("DEPRECATION")
                small.compress(if (Build.VERSION.SDK_INT >= 30) Bitmap.CompressFormat.WEBP_LOSSY else Bitmap.CompressFormat.WEBP, 70, it)
            }
            if (small !== image) small.recycle()
            if (!partial.renameTo(target)) partial.delete()
        }
    }

    /** After publication: picture the copy just written to Photos. Failure is silent. */
    fun capture(context: Context, id: String, locator: String) {
        if (has(context, id)) return
        runCatching {
            val uri = Uri.parse(locator)
            val mime = context.contentResolver.getType(uri) ?: return
            val image = GalleryPreview.decode(context, GalleryPreviewCopy(uri, mime, null), Size(SIDE, SIDE), CancellationSignal())
            save(context, id, image)
        }
    }
}
