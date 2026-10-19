package app.backupduck

import org.json.JSONObject

object NativeBridge {
    init { System.loadLibrary("backupduck_native") }
    @JvmStatic external fun call(request: String): String
    /** The Rust core boundary. The design catalog answers from scenario data instead. */
    @Volatile var transport: (String) -> String = ::call

    // Blocking calls belong on Dispatchers.IO. Never log pairing requests.
    fun request(request: JSONObject): Any {
        val response = JSONObject(transport(request.toString()))
        check(response.getBoolean("ok")) { response.getString("error") }
        return response.get("value")
    }
}
