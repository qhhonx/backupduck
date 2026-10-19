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
    /** The proposed pages (design/settings.md, design/flows.md). The app shows the current ones until migration step 6. */
    @Volatile var proposedDesign = false
    /** The proposed visual language (design/visual-language.md) on the proposed pages; today's look otherwise. */
    @Volatile var proposedLook = false
    /** The clock that decides Today and Yesterday; the catalog fixes it per scenario. */
    @Volatile var now: () -> Long = System::currentTimeMillis
    /** Synthetic pictures for the catalog, which has no files. Unset, pages read the copy in the Pixel's Photos. */
    @Volatile var previewImage: ((HistoryItem, Int, Int) -> android.graphics.Bitmap?)? = null
    /** A scripted camera for the catalog's Mac scenarios. Unset, scanning opens the camera. */
    @Volatile var scanOverride: (((String?) -> Unit) -> Unit)? = null
}
