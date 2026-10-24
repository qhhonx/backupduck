package app.backupduck

import android.content.Context
import android.view.View
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
    private var state:JSONObject?=null
    private var work:Job?=null
    val hasSenders:Boolean? get()=state?.let { peers.any { peer -> peer.enabled } }
    val name:String? get()=state?.optJSONObject("device")?.optString("name")
    /** The devices that send here, with their kind and last connection. */
    val peers:List<DevicePeer> get()=devicePeers(state?.optJSONArray("peers"))
    val senderNames:List<String> get()=peers.filter { it.enabled }.map { it.name }
    fun refresh() {
        if(work?.isActive==true)return
        work=activity.lifecycleScope.launch {
            runCatching {withContext(Dispatchers.IO) {DeviceProfiles.read(activity)}}.onSuccess(::render)
        }
    }
    private fun render(next:JSONObject) {
        val previousName=name;val previousPeers=peers
        state=next
        if(previousName!=name||previousPeers!=peers)changed()
    }
    internal fun rename():DuckEditDialog {
        val dialog = DuckEditDialog(activity, activity.getString(R.string.duck_device_name), activity.getString(R.string.device_name), name ?: android.os.Build.MODEL, maxLength = 80)
        val field = dialog.field
        field.input.addTextChangedListener(object:android.text.TextWatcher {
            override fun beforeTextChanged(s:CharSequence?,start:Int,count:Int,after:Int)=Unit
            override fun onTextChanged(s:CharSequence?,start:Int,before:Int,count:Int) {field.box.error=null}
            override fun afterTextChanged(s:android.text.Editable?)=Unit
        })
        val failure=activity.duckFailure(dialog.body,activity.getString(R.string.device_save_failed))
        dialog.show()
        dialog.save.tag="device.save"
        dialog.save.setOnClickListener {
            val value=field.input.text.toString().trim();field.box.error=null
            if(value.isBlank()||value.codePointCount(0,value.length)>40||value.any {Character.isISOControl(it)||it in '\u2028'..'\u202e'||it in '\u2066'..'\u2069'}) {
                field.box.error=activity.getString(R.string.device_name_invalid)
                return@setOnClickListener
            }
            dialog.busy(true);failure.visibility=View.GONE
            activity.lifecycleScope.launch {
                val result=withContext(Dispatchers.IO) {runCatching {DeviceProfiles.read(activity,value)}}
                dialog.busy(false)
                result.onSuccess {render(it);dialog.dismiss()}
                    .onFailure {if(it.message=="invalid_input") field.box.error=activity.getString(R.string.device_name_invalid) else failure.visibility=View.VISIBLE}
            }
        }
        return dialog
    }
}
