package app.backupduck

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatDelegate

class ExperimentsActivity:BackupDuckActivity() {
    override fun onCreate(savedInstanceState:Bundle?) {
        delegate.localNightMode=getSharedPreferences("appearance",MODE_PRIVATE).getInt("mode",AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        startActivity(Intent(this,MainActivity::class.java).putExtra("destination","storage"))
        finish()
    }
}
