package app.backupduck

import android.view.KeyEvent
import android.view.View
import android.widget.LinearLayout
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.*
import org.json.JSONObject

/** Scope is a draft of this change, never a guessed display of stored scope. */
internal class RetentionControls(private val activity:MainActivity,private val parent:LinearLayout,private val changed:()->Unit={},private val owner:DuckSheet?=null) {
    private var applying=false
    private var saving=false
    private var enabled=false
    private var editing=false
    private var includeHistory=false
    private val failure=activity.duckFailure(parent,activity.getString(R.string.settings_failed))
    private val toggle=activity.duckSwitch(false) {value ->
        if(!applying&&!saving&&!editing&&value!=enabled) {
            if(value)scope() else save(false)
        }
    }
    private val scopeArea=LinearLayout(activity).apply {orientation=LinearLayout.VERTICAL;visibility=View.GONE;tag="retention.scope-inline"}
    private val choices=mutableListOf<View>()
    private val historyEffect=activity.duckParagraph(activity.getString(R.string.storage_flow_history_effect)).apply {visibility=View.GONE}
    private val historyButton=activity.duckButton(activity.getString(R.string.relay_check_history)) {activity.checkHistoricalOriginals(changed,owner)}
    private val adjust=activity.duckButton(activity.getString(R.string.storage_flow_change_scope)) {scope()}
    init {
        parent.addView(activity.duckParagraph(activity.getString(R.string.storage_flow_original_definition)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=activity.dp(20)})
        val group=activity.duckGroup(parent)
        activity.receiverSetting(group,activity.getString(R.string.relay_toggle),control=toggle)
        parent.addView(activity.duckParagraph(activity.getString(R.string.storage_flow_policy_note)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=activity.dp(20)})
        parent.addView(adjust,LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=activity.dp(12)})
        parent.addView(scopeArea,LinearLayout.LayoutParams(-1,-2))
        scopeArea.addView(activity.duckParagraph(activity.getString(R.string.storage_flow_scope_caption)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=activity.dp(12)})
        val selection=activity.duckGroup(scopeArea)
        listOf(R.string.relay_new_only,R.string.relay_include_history).forEachIndexed {index,label ->
            val check=activity.duckPill(activity.getString(R.string.duck_selected),R.color.duck_action,R.color.duck_action_background);choices+=check
            activity.receiverSetting(selection,activity.getString(label),control=check) {
                if(!saving) {includeHistory=index==1;renderChoices()}
            }
        }
        scopeArea.addView(historyEffect,LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=activity.dp(12)})
        parent.addView(historyButton,LinearLayout.LayoutParams(-1,-2).apply {topMargin=activity.dp(12)})
        owner?.setOnKeyListener {_,key,event ->
            if(key==KeyEvent.KEYCODE_BACK&&editing&&!saving) {
                if(event.action==KeyEvent.ACTION_UP)cancelScope()
                true
            } else false
        }
    }
    fun render(value:Boolean) {if(saving)return;enabled=value;applying=true;toggle.isChecked=value;applying=false;adjust.visibility=if(value&&!editing)View.VISIBLE else View.GONE}
    internal fun scope() {
        if(saving)return
        editing=true;includeHistory=false;scopeArea.visibility=View.VISIBLE;adjust.visibility=View.GONE
        applying=true;toggle.isChecked=true;applying=false;toggle.isEnabled=false
        failure.visibility=View.GONE;renderChoices();renderActions()
    }
    private fun renderChoices() {
        choices.forEachIndexed {index,view ->view.visibility=if((index==1)==includeHistory)View.VISIBLE else View.INVISIBLE}
        historyEffect.visibility=if(includeHistory)View.VISIBLE else View.GONE
    }
    internal fun cancelScope() {
        if(saving)return
        editing=false;scopeArea.visibility=View.GONE;toggle.isEnabled=true;owner?.footer?.removeAllViews();(owner?.footer?.tag as? View)?.visibility=View.GONE;render(enabled)
    }
    private fun renderActions() {
        owner?.footer?.removeAllViews()
        owner?.addAction(activity.getString(R.string.device_cancel)) {cancelScope()}
        owner?.addAction(activity.getString(if(saving)R.string.duck_saving else R.string.settings_save),true) {save(true,includeHistory)}
        owner?.footer?.let {for(i in 0 until it.childCount)it.getChildAt(i).isEnabled=!saving}
    }
    private fun save(value:Boolean,history:Boolean=false) {
        if(saving)return
        saving=true;toggle.isEnabled=false;adjust.isEnabled=false;scopeArea.isEnabled=false;failure.visibility=View.GONE
        historyButton.isEnabled=false;owner?.setCancelable(false);if(editing)renderActions()
        activity.lifecycleScope.launch {
            val result=withContext(Dispatchers.IO) {runCatching {NativeBridge.request(JSONObject().put("op","set_receiver_relay").put("root","${activity.filesDir}/receiver").put("enabled",value).put("include_history",history))}}
            saving=false;toggle.isEnabled=true;adjust.isEnabled=true;scopeArea.isEnabled=true;historyButton.isEnabled=true;owner?.setCancelable(true)
            if(result.isSuccess) {
                editing=false;scopeArea.visibility=View.GONE;owner?.footer?.removeAllViews();(owner?.footer?.tag as? View)?.visibility=View.GONE;render(value)
                RelayMaintenance.cancelAutomatic();if(value)RelayMaintenance.schedule(activity)
                changed();activity.duckAcknowledge(activity.getString(if(value)R.string.relay_enabled else R.string.relay_disabled),parent)
            } else {
                if(editing) {toggle.isEnabled=false;renderActions()} else render(enabled)
                failure.visibility=View.VISIBLE
            }
        }
    }
}
