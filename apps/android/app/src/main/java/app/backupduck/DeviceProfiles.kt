package app.backupduck

import android.content.Context
import android.text.format.DateUtils
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.*
import org.json.JSONObject
import java.util.Locale

internal object DeviceProfiles {
    fun read(context: Context, name: String? = null): JSONObject {
        val request = JSONObject().put("op", "device_status")
            .put("root", "${context.filesDir}/receiver/store").put("language", Locale.getDefault().language)
        if (name != null) request.put("name", name)
        return NativeBridge.request(request) as JSONObject
    }
}
internal class DevicePanels(private val activity:MainActivity,private val changed:()->Unit={}) {
    private val nameLabels=mutableListOf<TextView>()
    private var state:JSONObject?=null
    private var work:Job?=null
    val name:String? get()=state?.optJSONObject("device")?.optString("name")
    fun compactSettings(parent:LinearLayout) {
        val value=activity.duckText(name ?: android.os.Build.MODEL,13,true);nameLabels+=value
        activity.duckSetting(parent,activity.getString(R.string.duck_device_name),control=value) {rename()}
        activity.duckSetting(parent,activity.getString(R.string.device_known_senders),activity.getString(R.string.duck_sender_settings_note)) {showPeers()}
    }
    fun refresh() {
        if(work?.isActive==true)return
        work=activity.lifecycleScope.launch {
            runCatching {withContext(Dispatchers.IO) {DeviceProfiles.read(activity)}}.onSuccess(::render)
                .onFailure {if(state==null) nameLabels.forEach {it.setText(R.string.device_load_failed)}}
        }
    }
    private fun render(next:JSONObject) {
        state=next;changed();val name=next.getJSONObject("device").getString("name")
        nameLabels.forEach {if(it.text.toString()!=name) it.text=name}
    }
    fun showPeers():DuckPage {
        val page=DuckPage(activity,activity.getString(R.string.device_known_senders));page.show()
        fun load() {
            page.body.removeAllViews();activity.duckNotice(page.body,activity.getString(R.string.device_loading))
            activity.lifecycleScope.launch {
                val result=withContext(Dispatchers.IO) {runCatching {DeviceProfiles.read(activity)}}
                if(!page.isShowing)return@launch
                page.body.removeAllViews()
                result.onSuccess {data ->
                    render(data);val peers=data.getJSONArray("peers")
                    if(peers.length()==0) {
                        activity.duckNotice(page.body,activity.getString(R.string.device_no_senders),activity.getString(R.string.duck_devices_empty))
                        page.body.addView(activity.duckButton(activity.getString(R.string.design_connect_device),true) {page.dismiss();activity.openConnection()})
                    } else {
                        val group=activity.duckGroup(page.body)
                        for(i in 0 until peers.length()) {
                            val peer=peers.getJSONObject(i)
                            val seen=DateUtils.getRelativeTimeSpanString(peer.getLong("last_seen")*1000).toString()
                            activity.duckSetting(group,peer.getJSONObject("profile").getString("name"),listOfNotNull(peer.optString("device_type").takeUnless {it.isBlank()||it=="null"},seen).joinToString(" · "),
                                activity.duckPill(activity.getString(if(peer.optBoolean("enabled",true)) R.string.device_enable else R.string.device_disabled))) {showPeer(peer,page.body) {load()}}
                        }
                    }
                }.onFailure {
                    activity.duckProblem(page.body,activity.getString(R.string.device_load_failed))
                    page.body.addView(activity.duckButton(activity.getString(R.string.duck_retry)) {load()})
                }
            }
        }
        load();return page
    }
    private fun showPeer(peer:JSONObject,host:View,changed:()->Unit) {
        val sheet=DuckSheet(activity,peer.getJSONObject("profile").getString("name"))
        val group=activity.duckGroup(sheet.body)
        fun datum(title:Int,value:String) {activity.duckSetting(group,activity.getString(title),value,activity.duckText("",13))}
        datum(R.string.duck_device_name,peer.getJSONObject("profile").getString("name"))
        datum(R.string.duck_type,peer.optString("device_type").takeUnless {it.isBlank()||it=="null"} ?: "—")
        datum(R.string.duck_device_address,peer.optString("ip").takeUnless {it.isBlank()||it=="null"} ?: "—")
        datum(R.string.duck_device_last_seen,java.text.DateFormat.getDateTimeInstance().format(java.util.Date(peer.getLong("last_seen")*1000)))
        activity.duckNotice(sheet.body,activity.getString(R.string.device_disable_help),activity.getString(R.string.duck_reset_unchanged))
        val enabled=peer.optBoolean("enabled",true)
        sheet.body.addView(activity.duckButton(activity.getString(if(enabled) R.string.device_disable else R.string.device_enable)) {
            sheet.hide();var saved=false
            val confirmation=activity.duckConfirm(R.string.device_known_senders,R.string.duck_device_permission,R.string.device_save,busyNotice=R.string.duck_saving) {dialog ->
                dialog.busy(true)
                activity.lifecycleScope.launch {
                    val result=withContext(Dispatchers.IO) {runCatching {
                        NativeBridge.request(JSONObject().put("op","set_sender_enabled").put("root","${activity.filesDir}/receiver/store")
                            .put("id",peer.getJSONObject("profile").getString("id")).put("enabled",!enabled))
                    }}
                    dialog.busy(false)
                    result.onSuccess {saved=true;dialog.dismiss();sheet.dismiss();refresh();changed();activity.duckAcknowledge(activity.getString(R.string.device_save),host)}
                        .onFailure {dialog.showFailure(R.string.device_save_failed)}
                }
            }
            confirmation.setOnDismissListener {if(!saved) sheet.show()}
        },LinearLayout.LayoutParams(-1,-2));sheet.show()
    }
    internal fun rename():DuckSheet {
        val sheet=DuckSheet(activity,activity.getString(R.string.duck_device_name))
        sheet.body.addView(activity.duckParagraph(activity.getString(R.string.duck_name_intro)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=activity.dp(20)})
        val field=DuckField(activity,activity.getString(R.string.device_name),name ?: android.os.Build.MODEL,maxLength=80)
        field.input.addTextChangedListener(object:android.text.TextWatcher {
            override fun beforeTextChanged(s:CharSequence?,start:Int,count:Int,after:Int)=Unit
            override fun onTextChanged(s:CharSequence?,start:Int,before:Int,count:Int) {field.box.error=null}
            override fun afterTextChanged(s:android.text.Editable?)=Unit
        })
        sheet.body.addView(field.view);activity.duckNotice(sheet.body,activity.getString(R.string.duck_code_tasks_unchanged))
        val failure=activity.duckFailure(sheet.body,activity.getString(R.string.device_save_failed))
        val cancel=sheet.addAction(activity.getString(R.string.device_cancel)) {sheet.dismiss()}
        val save=sheet.addAction(activity.getString(R.string.device_save),true) {
            val value=field.input.text.toString().trim();field.box.error=null
            if(value.isBlank()||value.codePointCount(0,value.length)>40||value.any {Character.isISOControl(it)||it in '\u2028'..'\u202e'||it in '\u2066'..'\u2069'}) {field.box.error=activity.getString(R.string.device_name_invalid);return@addAction}
            field.input.isEnabled=false;cancel.isEnabled=false;sheet.setCancelable(false);failure.visibility=View.GONE
            sheet.footer.getChildAt(1).isEnabled=false
            activity.lifecycleScope.launch {
                val result=withContext(Dispatchers.IO) {runCatching {DeviceProfiles.read(activity,value)}}
                field.input.isEnabled=true;cancel.isEnabled=true;sheet.footer.getChildAt(1).isEnabled=true;sheet.setCancelable(true)
                result.onSuccess {render(it);sheet.dismiss();activity.duckAcknowledge(activity.getString(R.string.device_save))}
                    .onFailure {if(it.message=="invalid_input") field.box.error=activity.getString(R.string.device_name_invalid) else failure.visibility=View.VISIBLE}
            }
        }
        save.tag="device.save";sheet.show();return sheet
    }
}
