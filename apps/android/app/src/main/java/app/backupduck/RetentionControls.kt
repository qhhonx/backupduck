package app.backupduck

import android.view.View
import android.widget.LinearLayout
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.*
import org.json.JSONObject

internal class RetentionControls(private val activity:MainActivity,parent:LinearLayout,private val changed:()->Unit={},private val owner:DuckSheet?=null) {
    private var applying=false;private var saving=false
    private var enabled=false
    private val toggle=activity.duckSwitch(false) {checked ->if(!applying&&!saving) {if(checked) {render(false);scope()} else save(false)}}
    private val failure=activity.duckFailure(parent,activity.getString(R.string.settings_failed))
    init {
        val group=activity.duckGroup(parent)
        activity.duckSetting(group,activity.getString(R.string.relay_toggle),activity.getString(R.string.relay_note),toggle)
        activity.duckWarning(parent,activity.getString(R.string.duck_keep_source),activity.getString(R.string.duck_relay_boundary))
        parent.addView(activity.duckButton(activity.getString(R.string.duck_scope)) {scope()},LinearLayout.LayoutParams(-1,-2))
        parent.addView(activity.duckLink(activity.getString(R.string.relay_check_history)) {activity.checkHistoricalOriginals(changed)},LinearLayout.LayoutParams(-2,-2))
    }
    fun render(value:Boolean) {if(saving)return;enabled=value;applying=true;toggle.isChecked=value;applying=false}
    internal fun scope():DuckSheet {
        val sheet=DuckSheet(activity,activity.getString(R.string.duck_scope))
        sheet.body.addView(activity.duckParagraph(activity.getString(R.string.duck_scope_intro)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=activity.dp(20)})
        var includeHistory=false
        val group=activity.duckGroup(sheet.body)
        val selections=mutableListOf<View>()
        listOf(R.string.relay_new_only,R.string.relay_include_history).forEachIndexed {index,label ->
            val pill=activity.duckPill(activity.getString(R.string.duck_selected),R.color.duck_action,R.color.duck_action_background).apply {visibility=if(index==0) View.VISIBLE else View.INVISIBLE};selections+=pill
            activity.duckSetting(group,activity.getString(label),control=pill) {
                includeHistory=index==1;selections.forEachIndexed {i,view->view.visibility=if(i==index)View.VISIBLE else View.INVISIBLE}
            }
        }
        activity.duckWarning(sheet.body,activity.getString(R.string.duck_scope_history_notice),activity.getString(R.string.duck_scope_history_note))
        val error=activity.duckFailure(sheet.body,activity.getString(R.string.settings_failed))
        sheet.addAction(activity.getString(R.string.device_cancel)) {sheet.dismiss()}
        sheet.addAction(activity.getString(R.string.settings_save),true) {save(true,includeHistory,sheet,error)}
        // Dialog.isShowing is false after hide(); that is exactly the owner we
        // need to restore. Do not restore a window owned by a destroyed Activity.
        sheet.setOnDismissListener {if(!activity.isFinishing&&!activity.isDestroyed)owner?.show()}
        owner?.hide();sheet.show();return sheet
    }
    private fun save(value:Boolean,includeHistory:Boolean=false,sheet:DuckSheet?=null,error:View=failure) {
        if(saving)return
        saving=true;toggle.isEnabled=false;error.visibility=View.GONE;sheet?.setCancelable(false)
        sheet?.footer?.let {footer->for(i in 0 until footer.childCount) footer.getChildAt(i).isEnabled=false}
        val busy=sheet?.let {activity.duckNotice(it.body,activity.getString(R.string.duck_saving))}
        activity.lifecycleScope.launch {
            val result=withContext(Dispatchers.IO) {runCatching {NativeBridge.request(JSONObject().put("op","set_receiver_relay").put("root","${activity.filesDir}/receiver").put("enabled",value).put("include_history",includeHistory))}}
            (busy?.parent as? android.view.ViewGroup)?.removeView(busy)
            saving=false;toggle.isEnabled=true;sheet?.setCancelable(true)
            sheet?.footer?.let {footer->for(i in 0 until footer.childCount) footer.getChildAt(i).isEnabled=true}
            render(if(result.isSuccess)value else enabled)
            result.onSuccess {
                RelayMaintenance.cancelAutomatic();if(value)RelayMaintenance.schedule(activity)
                sheet?.dismiss();changed();activity.duckAcknowledge(activity.getString(if(value) R.string.relay_enabled else R.string.relay_disabled),owner?.body ?: failure.rootView)
            }.onFailure {error.visibility=View.VISIBLE}
        }
    }
}
