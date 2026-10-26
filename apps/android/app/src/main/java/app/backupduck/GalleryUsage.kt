package app.backupduck

import android.content.Context
import android.os.SystemClock
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import android.provider.MediaStore
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

internal data class GalleryUsage(val readyBytes: Long, val readyCount: Long, val pendingBytes: Long, val pendingCount: Long, val unknownSizes: Long)

/** Indexed file sizes for this installation's delivery copies, never cloud state. */
internal object GalleryInventory {
    private val legacyDeliveryName = Regex("^BD_[0-9a-f]{64}(?:\\.[^/]+)?$")
    private val datedDeliveryName = Regex("^BD_(?:[0-9]{8}_[0-9]{6}Z|undated)_[0-9a-f]{4,64}(?:_MP)?(?:\\.[A-Za-z0-9]{1,12})?$")
    internal fun isDeliveryName(name: String) = legacyDeliveryName.matches(name) || datedDeliveryName.matches(name)
    @Suppress("DEPRECATION")
    suspend fun read(context: Context): GalleryUsage {
        var bytes = 0L; var count = 0L; var pendingBytes = 0L; var pendingCount = 0L; var unknown = 0L
        val columns = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.IS_PENDING, MediaStore.MediaColumns.OWNER_PACKAGE_NAME)
        for (collection in listOf(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY))) {
            currentCoroutineContext().ensureActive()
            // API 29 supports this query parameter; owner and path restrict scope.
            // No shared-library permission or file decoding is needed.
            val uri = MediaStore.setIncludePending(collection)
            val cursor = checkNotNull(context.contentResolver.query(uri, columns,
                "${MediaStore.MediaColumns.RELATIVE_PATH}=?", arrayOf("DCIM/BackupDuck/"), null))
            cursor.use {
                while (it.moveToNext()) {
                    currentCoroutineContext().ensureActive()
                    val name = it.getString(0) ?: ""
                    if (it.getString(3) != context.packageName || !isDeliveryName(name)) continue
                    val size = if (it.isNull(1) || it.getLong(1) < 0) { unknown++; 0L } else it.getLong(1)
                    if (it.getInt(2) == 0) { bytes = Math.addExact(bytes, size); count++ }
                    else { pendingBytes = Math.addExact(pendingBytes, size); pendingCount++ }
                }
            }
        }
        return GalleryUsage(bytes, count, pendingBytes, pendingCount, unknown)
    }
}

/**
 * Copies of this installation still indexed in Photos, re-read at most every
 * five seconds. Saved photos beyond this count were removed from this Pixel.
 */
internal class CopiesInPhotos(private val activity: androidx.appcompat.app.AppCompatActivity, private val changed: () -> Unit) {
    var value: Long? = null; private set
    private var job: Job? = null
    private var readAt = 0L
    fun refresh() {
        if (ReceiverEnvironment.previewImage != null || job?.isActive == true) return
        val now = SystemClock.elapsedRealtime()
        if (value != null && now - readAt < 5_000) return
        readAt = now
        job = activity.lifecycleScope.launch {
            val count = withContext(Dispatchers.IO) { runCatching { GalleryInventory.read(activity).readyCount }.getOrNull() }
            if (count != null && count != value) { value = count; changed() }
        }
    }
}

/** Saved photos whose copy is no longer in Photos; zero while the count is unknown. */
internal fun removedFromPixel(saved: Int, copiesInPhotos: Long?): Int =
    copiesInPhotos?.let { (saved - it).coerceIn(0, saved.toLong().coerceAtLeast(0)).toInt() } ?: 0
