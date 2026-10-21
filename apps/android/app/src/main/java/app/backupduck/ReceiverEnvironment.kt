package app.backupduck

import android.content.Context
import android.content.Intent

/**
 * What the receiver UI takes from outside the activity: the Rust core (see
 * [NativeBridge.transport]), the receiving service and update checks. The app
 * uses the real ones. The design catalog replaces them once at launch so the
 * production pages render scenario states without running a receiver.
 */
internal object ReceiverEnvironment {
    @Volatile var startService: (Context) -> Unit = { it.startForegroundService(Intent(it, ReceiverService::class.java)) }
    @Volatile var stopService: (Context) -> Unit = { it.stopService(Intent(it, ReceiverService::class.java)) }
    @Volatile var checksUpdates = true
    /** Explicit update checks; the catalog supplies a result without network or downloads. */
    @Volatile var latestUpdate: suspend (Context) -> AppRelease? = { AppUpdates.latest(it) }
    /** The redesigned pages (design/redesign-roadmap.md, step 6). The catalog can switch back to the earlier ones. */
    @Volatile var proposedDesign = true
    /** The device's own storage reading; the catalog fixes it per scenario. */
    @Volatile var deviceStorage: (Context) -> DeviceStorage = { DeviceStorage.read(it) }
    /** BackupDuck's files in the Pixel's Photos, read from the media index; the catalog fixes it per scenario. */
    @Volatile var galleryUsage: suspend (Context) -> GalleryUsage = { GalleryInventory.read(it) }
    /** The clock that decides Today and Yesterday; the catalog fixes it per scenario. */
    @Volatile var now: () -> Long = System::currentTimeMillis
    /** Synthetic pictures for the catalog, which has no files. Unset, pages read the copy in the Pixel's Photos. */
    @Volatile var previewImage: ((HistoryItem, Int, Int) -> android.graphics.Bitmap?)? = null
    /** A scripted camera for the catalog's Mac scenarios. Unset, scanning opens the camera. */
    @Volatile var scanOverride: (((String?) -> Unit) -> Unit)? = null
}

/** Space on the volume that holds the receiver's files, as the device reports it. */
internal data class DeviceStorage(val totalBytes: Long, val freeBytes: Long) {
    /** Less than 15% free: the hub hints at space while auto cleanup is off (flows.md § Hub rules). */
    val low: Boolean get() = totalBytes > 0 && freeBytes * 100 / totalBytes < 15
    companion object {
        fun read(context: Context): DeviceStorage = android.os.StatFs(context.filesDir.path).let { DeviceStorage(it.totalBytes, it.availableBytes) }
    }
}
