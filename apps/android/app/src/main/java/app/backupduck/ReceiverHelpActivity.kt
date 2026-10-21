package app.backupduck

import android.content.Intent
import android.os.Bundle
import android.widget.LinearLayout
import android.view.View
import androidx.appcompat.widget.SearchView
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

/** Read-only receiver guidance, grouped by task and problem (I8). */
class ReceiverHelpActivity : BackupDuckActivity() {
    private var query=""
    override fun onSaveInstanceState(outState:Bundle) {
        outState.putString("query",query)
        super.onSaveInstanceState(outState)
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        query=savedInstanceState?.getString("query").orEmpty()
        val topic = ReceiverHelpTopic.entries.firstOrNull { it.key == intent.getStringExtra("topic") }
        nativeDetailPage(topic?.title ?: R.string.pref_help) { panel ->
            if(topic==null) {
                val results=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL}
                fun render() {
                    results.removeAllViews()
                    val needle=query.trim()
                    val visible=ReceiverHelpTopic.entries.filter {entry ->
                        (listOf(entry.title,entry.description)+entry.sections.flatMap {listOf(it.first,it.second)})
                            .any {getString(it).contains(needle,ignoreCase=true)}
                    }
                    listOf(R.string.help_tasks to listOf(ReceiverHelpTopic.CONNECTION,ReceiverHelpTopic.RESULTS,ReceiverHelpTopic.STORAGE),
                        R.string.help_problems to listOf(ReceiverHelpTopic.BACKGROUND,ReceiverHelpTopic.RECOVERY)).forEach {(title,topics) ->
                        val matches=topics.filter {it in visible}
                        if(matches.isNotEmpty()) {
                            lookSection(results,getString(title))
                            val group=lookGroup(results)
                            matches.forEach {entry ->
                                lookRow(group,null,getString(entry.title),getString(entry.description)) {
                                    startActivity(Intent(this,ReceiverHelpActivity::class.java).putExtra("topic",entry.key))
                                }
                            }
                        }
                    }
                    if(visible.isEmpty()) results.addView(duckParagraph(getString(R.string.help_no_results)))
                }
                panel.addView(SearchView(this).apply {
                    queryHint=getString(R.string.help_search)
                    setIconifiedByDefault(false)
                    setQuery(this@ReceiverHelpActivity.query,false)
                    setOnQueryTextListener(object:SearchView.OnQueryTextListener {
                        override fun onQueryTextSubmit(text:String?)=true
                        override fun onQueryTextChange(text:String?):Boolean {this@ReceiverHelpActivity.query=text.orEmpty();render();return true}
                    })
                },LinearLayout.LayoutParams(-1,-2))
                panel.addView(results,LinearLayout.LayoutParams(-1,-2))
                render()
            } else {
                if(topic==ReceiverHelpTopic.CONNECTION) {
                    val address=duckParagraph(getString(R.string.help_address_loading)).apply {
                        accessibilityLiveRegion=View.ACCESSIBILITY_LIVE_REGION_POLITE
                        setTextIsSelectable(true)
                    }
                    panel.addView(address)
                    lifecycleScope.launch {
                        val result=withContext(Dispatchers.IO) {runCatching {NativeBridge.request(JSONObject().put("op","receiver_connection_info").put("root","$filesDir/receiver")) as JSONObject}}
                        address.text=result.fold({if(it.isNull("endpoint")) getString(R.string.help_address_missing) else getString(R.string.help_address_saved,it.getString("endpoint"))},
                            {getString(R.string.help_address_unavailable)})
                    }
                }
                topic.sections.forEach {(title,text)->
                    // Articles contain only reading content; they never start a workflow.
                    lookSection(panel,getString(title))
                    panel.addView(lookText(getString(text),com.google.android.material.R.style.TextAppearance_Material3_BodyLarge))
                }
            }
        }
    }
}
