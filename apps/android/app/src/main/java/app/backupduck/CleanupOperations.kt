package app.backupduck

import android.content.Context
import android.content.Intent
import android.provider.Settings
import kotlinx.coroutines.flow.StateFlow

/** Host operations are replaceable only by the Catalog; no duplicate cleanup queue. */
internal interface CleanupOperations {
    val state: StateFlow<PhotosProbeState>
    fun start(context: Context, bind: Boolean, route: String): Boolean
    fun stop()
    fun access(context: Context, returned: () -> Unit)
    fun photos(context: Context, returned: () -> Unit)
}
internal object LiveCleanupOperations : CleanupOperations {
    override val state get() = PhotosProbeService.state
    override fun start(context: Context, bind: Boolean, route: String) = PhotosProbeService.clean(bind, route)
    override fun stop() = PhotosProbeService.stop()
    override fun access(context: Context, returned: () -> Unit) { context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
    override fun photos(context: Context, returned: () -> Unit) {
        val intent = context.packageManager.getLaunchIntentForPackage(PhotosProbeService.PHOTOS_PACKAGE)
            ?: throw android.content.ActivityNotFoundException()
        context.startActivity(intent)
    }
}
