package app.backupduck

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject

/** Only durable byte acknowledgements; no gallery or cloud success inference. */
internal data class ReceiverByteProgress(val confirmed:Long,val total:Long,val received:Boolean,val processing:String?=null,val error:String?=null)
internal object ReceiverProgress {
    val mutable=MutableStateFlow<Map<String,ReceiverByteProgress>>(emptyMap())
    val snapshot=mutable.asStateFlow()
    fun parse(data:JSONObject):Map<String,ReceiverByteProgress> {
        val items=data.getJSONArray("items")
        return (0 until items.length()).associate {i ->
            val item=items.getJSONObject(i)
            item.getString("id") to ReceiverByteProgress(item.getLong("confirmed_bytes"),item.getLong("total_bytes"),item.getBoolean("received"),item.optString("processing").takeIf {it.isNotEmpty()},item.optString("processing_error").takeIf {it.isNotEmpty()&&it!="null"})
        }
    }
}
