package app.backupduck

/** The receiver pairs through a portrait workflow, including the real scanner. */
class ReceiverScanActivity : com.journeyapps.barcodescanner.CaptureActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        DuckLook.applyScheme(this)
        super.onCreate(savedInstanceState)
    }
}
