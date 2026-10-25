package app.backupduck

import android.app.Activity
import android.app.Application
import android.content.BroadcastReceiver
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import java.lang.ref.WeakReference

/** Test-only transport: substitutes a decoded string at the camera result boundary. */
class ValidationScanTransport : ContentProvider(), Application.ActivityLifecycleCallbacks {
    override fun onCreate(): Boolean {
        check(BuildConfig.VALIDATION_BUILD)
        (context!!.applicationContext as Application).registerActivityLifecycleCallbacks(this)
        return true
    }
    override fun onActivityResumed(activity: Activity) {
        if (activity is ReceiverScanActivity) scanner = WeakReference(activity)
    }
    override fun onActivityPaused(activity: Activity) {
        if (scanner?.get() === activity) scanner = null
    }
    override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
    override fun onActivityStarted(activity: Activity) = Unit
    override fun onActivityStopped(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
    override fun onActivityDestroyed(activity: Activity) = Unit
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, args: Array<out String>?, order: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, args: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<out String>?): Int = 0
    companion object { internal var scanner: WeakReference<ReceiverScanActivity>? = null }
}

/** Present only in -PvalidationApp debug/release manifests and bytecode. */
class ValidationScanReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        check(BuildConfig.VALIDATION_BUILD)
        val payload = intent.getStringExtra("backupduck.test.scan") ?: return
        val activity = ValidationScanTransport.scanner?.get() ?: return
        activity.setResult(Activity.RESULT_OK, Intent()
            .putExtra(com.google.zxing.client.android.Intents.Scan.RESULT, payload)
            .putExtra(com.google.zxing.client.android.Intents.Scan.RESULT_FORMAT, "QR_CODE"))
        activity.finish()
    }
}
