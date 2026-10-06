package app.backupduck

import android.view.View
import android.widget.*
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.*
import org.json.JSONObject

internal enum class StorageSection { LIMITS, LOGS }

/** Draft values remain local until Rust validates and persists the entire settings change. */
internal fun MainActivity.showStorageControls(section:StorageSection,saved:()->Unit):DuckSheet {
    val sheet=DuckSheet(this,getString(if(section==StorageSection.LIMITS) R.string.storage_limits else R.string.logs_retention_settings))
    val content=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL};sheet.body.addView(content)
    var loading:Job?=null
    fun load() {
        content.removeAllViews();duckNotice(content,getString(R.string.history_loading))
        loading=lifecycleScope.launch {
            val result=withContext(Dispatchers.IO) {runCatching {NativeBridge.request(JSONObject().put("op","receiver_settings").put("root","$filesDir/receiver")) as JSONObject}}
            if(!sheet.isShowing)return@launch
            content.removeAllViews()
            result.onFailure {duckProblem(content,getString(R.string.settings_failed));content.addView(duckButton(getString(R.string.duck_retry)) {load()})}
            result.onSuccess {state ->
                val settings=state.getJSONObject("settings")
                content.addView(duckParagraph(getString(if(section==StorageSection.LIMITS) R.string.duck_storage_limits_intro else R.string.duck_logs_limits_intro)))
                val controls=linkedMapOf<String,Pair<Spinner,List<Long>>>()
                fun options(key:String,title:Int,values:List<Long>,format:(Long)->String) {
                    val current=settings.getLong(key);val all=(values+current).distinct().sorted()
                    controls[key]=duckSelect(content,getString(title),all.map(format),all.indexOf(current)) to all
                }
                if(section==StorageSection.LIMITS) {
                    options("receiver_budget_bytes",R.string.storage_budget,listOf(2L,4,6,10,16,32,64,128).map {it shl 30}) {android.text.format.Formatter.formatShortFileSize(this@showStorageControls,it)}
                    options("min_free_bytes",R.string.storage_reserve,listOf(0L,1,2,3,5,10).map {it shl 30}) {android.text.format.Formatter.formatShortFileSize(this@showStorageControls,it)}
                } else {
                    options("log_days",R.string.logs_days,listOf(1L,7,14,30,90)) {"$it ${getString(R.string.days_unit)}"}
                    options("log_limit",R.string.logs_limit,listOf(1000L,5000,10000,20000)) {it.toString()}
                }
                val notice=duckNotice(content,getString(R.string.duck_code_tasks_unchanged))
                val failure=duckFailure(content,getString(R.string.settings_failed))
                sheet.footer.removeAllViews()
                val cancel=sheet.addAction(getString(R.string.device_cancel)) {sheet.dismiss()}
                lateinit var save:com.google.android.material.button.MaterialButton
                save=sheet.addAction(getString(R.string.settings_save),true) {
                    val draft=JSONObject(settings.toString());controls.forEach {(key,pair)->draft.put(key,pair.second[pair.first.selectedItemPosition])}
                    save.isEnabled=false;cancel.isEnabled=false;controls.values.forEach {it.first.isEnabled=false};sheet.setCancelable(false);failure.visibility=View.GONE;notice.visibility=View.GONE;save.setText(R.string.duck_saving)
                    lifecycleScope.launch {
                        val persisted=withContext(Dispatchers.IO) {runCatching {NativeBridge.request(JSONObject().put("op","receiver_settings").put("root","$filesDir/receiver").put("settings",draft))}}
                        save.isEnabled=true;cancel.isEnabled=true;controls.values.forEach {it.first.isEnabled=true};sheet.setCancelable(true);save.setText(R.string.settings_save)
                        persisted.onSuccess {sheet.dismiss();saved();duckAcknowledge(getString(R.string.settings_save))}.onFailure {failure.visibility=View.VISIBLE}
                    }
                }
            }
        }
    }
    sheet.setOnDismissListener {loading?.cancel()};sheet.show();load();return sheet
}
