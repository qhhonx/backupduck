package app.backupduck

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

internal enum class ReceiverHelpTopic(val key: String, val title: Int, val description: Int, val sections: List<Pair<Int, Int>>) {
    CONNECTION("connection",R.string.help_connection_title,R.string.help_connection_summary,listOf(
        R.string.duck_help_wifi_title to R.string.duck_help_wifi_note,
        R.string.duck_help_pair_title to R.string.duck_help_pair_note,
        R.string.duck_help_start_title to R.string.duck_help_start_note)),
    BACKGROUND("background",R.string.help_background_title,R.string.help_background_summary,listOf(
        R.string.duck_help_background_title to R.string.duck_help_background_note,
        R.string.duck_help_restore_title to R.string.duck_help_restore_note,
        R.string.duck_help_sender_title to R.string.duck_help_sender_note)),
    RESULTS("results",R.string.help_results_title,R.string.help_results_summary,listOf(
        R.string.duck_help_receipt_title to R.string.duck_help_receipt_note,
        R.string.duck_help_gallery_title to R.string.duck_help_gallery_note,
        R.string.duck_help_cloud_title to R.string.duck_help_cloud_note)),
    STORAGE("storage",R.string.help_storage_title,R.string.help_storage_summary,listOf(
        R.string.storage_limits to R.string.duck_help_limit_note,
        R.string.duck_keep to R.string.duck_help_keep_note,
        R.string.duck_help_relay_title to R.string.duck_help_relay_note,
        R.string.originals_export to R.string.duck_help_archive_note)),
    RECOVERY("recovery",R.string.help_recovery_title,R.string.help_recovery_summary,listOf(
        R.string.duck_help_retry_title to R.string.duck_help_retry_note,
        R.string.duck_help_report_title to R.string.duck_help_report_note,
        R.string.updates_title to R.string.duck_help_update_note)),
}

class ReceiverHelpActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        val topic = ReceiverHelpTopic.entries.firstOrNull { it.key == intent.getStringExtra("topic") }
        nativeDetailPage(topic?.title ?: R.string.receiver_help_title) { panel ->
            if(topic==null) {
                panel.addView(duckParagraph(getString(R.string.receiver_help_intro)),android.widget.LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(20)})
                val group=duckGroup(panel)
                ReceiverHelpTopic.entries.forEach {entry ->
                    duckSetting(group,getString(entry.title)) {startActivity(Intent(this,ReceiverHelpActivity::class.java).putExtra("topic",entry.key))}
                }
            } else {
                if(topic==ReceiverHelpTopic.CONNECTION) {
                    val holder=android.widget.LinearLayout(this).apply {orientation=android.widget.LinearLayout.VERTICAL};panel.addView(holder)
                    duckNotice(holder,getString(R.string.help_address_loading))
                    lifecycleScope.launch {
                        val result=withContext(Dispatchers.IO) {runCatching {NativeBridge.request(JSONObject().put("op","receiver_connection_info").put("root","$filesDir/receiver")) as JSONObject}}
                        holder.removeAllViews()
                        result.onSuccess {
                            duckNotice(holder,getString(R.string.help_address_title),if(it.isNull("endpoint")) getString(R.string.help_address_missing) else getString(R.string.help_address_saved,it.getString("endpoint")))
                        }.onFailure {duckProblem(holder,getString(R.string.help_address_unavailable))}
                    }
                }
                val group=duckGroup(panel)
                topic.sections.forEach {(title,text)->
                    // Help is read only: paths are text, never a hidden workflow transition.
                    duckSetting(group,getString(title),getString(text),duckText("",13))

                }
            }
        }
    }
}
