package app.backupduck

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.journeyapps.barcodescanner.CaptureManager
import com.journeyapps.barcodescanner.DecoratedBarcodeView

/** The caller owns permission; scanner failures return to our connection page. */
class ReceiverScanActivity : Activity() {
    companion object { internal const val CAMERA_UNAVAILABLE = "app.backupduck.camera_unavailable" }
    private lateinit var barcode: DecoratedBarcodeView
    private lateinit var capture: CaptureManager
    override fun onCreate(savedInstanceState: Bundle?) {
        DuckLook.applyScheme(this)
        super.onCreate(savedInstanceState)
        barcode = DecoratedBarcodeView(this)
        setContentView(barcode)
        capture = object : CaptureManager(this, barcode) {
            override fun displayFrameworkBugMessageAndExit(message: String?) {
                setResult(RESULT_CANCELED, Intent().putExtra(CAMERA_UNAVAILABLE, true))
                finish()
            }
        }
        capture.setShowMissingCameraPermissionDialog(false)
        capture.initializeFromIntent(intent, savedInstanceState)
        capture.decode()
    }
    override fun onResume() {
        super.onResume()
        if (checkSelfPermission(android.Manifest.permission.CAMERA) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            setResult(RESULT_CANCELED); finish(); return
        }
        capture.onResume()
    }
    override fun onPause() { capture.onPause(); super.onPause() }
    override fun onDestroy() { capture.onDestroy(); super.onDestroy() }
    override fun onSaveInstanceState(outState: Bundle) { super.onSaveInstanceState(outState); capture.onSaveInstanceState(outState) }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        capture.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
    override fun onKeyDown(keyCode: Int, event: android.view.KeyEvent): Boolean = barcode.onKeyDown(keyCode, event) || super.onKeyDown(keyCode, event)
}
