package app.backupduck

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

/** Every receiver activity uses the same generated fixed Material scheme. */
open class BackupDuckActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        DuckLook.applyScheme(this)
    }
}
