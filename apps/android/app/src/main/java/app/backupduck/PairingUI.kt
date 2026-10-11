package app.backupduck

import android.graphics.Bitmap
import android.graphics.Color
import android.os.SystemClock
import android.view.View
import android.view.WindowManager
import android.widget.*
import androidx.lifecycle.lifecycleScope
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import kotlinx.coroutines.*
import org.json.JSONObject

/** Real receiver states drive the same sheet; failures stay visible until explicitly retried. */
internal class PairingUI(private val activity:MainActivity,private val start:()->Unit,private val scan:()->Unit) {
    private enum class Action { CODE,SCAN }
    private var sheet:DuckSheet?=null
    private var pending:Action?=null
    private var startingAt=0L
    private var timeout:Job?=null
    private var scanPage:DuckPage?=null
    private var scanWork:Job?=null
    fun choose() {
        sheet?.dismiss()
        sheet=DuckSheet(activity,activity.getString(R.string.design_connect_device)).also {dialog ->
            dialog.body.addView(activity.duckParagraph(activity.getString(R.string.duck_pairing_intro)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=activity.dp(20)})
            val group=activity.duckGroup(dialog.body)
            activity.duckSetting(group,activity.getString(R.string.duck_pair_iphone),activity.getString(R.string.duck_pair_iphone_note)) {request(Action.CODE)}
            activity.duckSetting(group,activity.getString(R.string.duck_pair_mac),activity.getString(R.string.duck_pair_mac_note)) {request(Action.SCAN)}
            dialog.setOnDismissListener {pending=null;timeout?.cancel()};dialog.show()
        }
    }
    fun iphone() {choose();request(Action.CODE)}
    fun mac() {choose();request(Action.SCAN)}
    private fun request(action:Action) {
        pending=action;startingAt=SystemClock.elapsedRealtime()
        sheet?.body?.removeAllViews()
        sheet?.body?.let {activity.duckNotice(it,activity.getString(R.string.duck_pairing_starting))}
        if(ReceiverState.snapshot.value.phase=="ready"&&ReceiverState.pairing!=null) update(ReceiverState.snapshot.value)
        else {start();timeout?.cancel();timeout=activity.lifecycleScope.launch {delay(60_000);if(pending!=null) fail(R.string.receiver_pair_start_failed,action)}}
    }
    fun update(state:ReceiverSnapshot) {
        val action=pending?:return
        if(state.phase=="ready"&&ReceiverState.pairing!=null) {
            pending=null;timeout?.cancel();sheet?.dismiss();sheet=null
            if(action==Action.CODE) code() else scanning()
        } else if(state.phase=="waiting"&&state.error!=null) fail(receiverProblem(state)?.message ?: R.string.receiver_pair_start_failed,action)
        else if(SystemClock.elapsedRealtime()-startingAt>60_000) fail(R.string.receiver_pair_start_failed,action)
    }
    private fun fail(message:Int,action:Action) {
        pending=null;timeout?.cancel()
        sheet?.body?.let {body ->
            body.removeAllViews();activity.duckProblem(body,activity.getString(message))
            body.addView(activity.duckButton(activity.getString(R.string.duck_retry)) {request(action)})
        }
    }
    private fun code() {
        val dialog=DuckSheet(activity,activity.getString(R.string.duck_pair_iphone))
        dialog.body.addView(activity.duckParagraph(activity.getString(R.string.receiver_pair_instruction)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=activity.dp(20)})
        val image=ImageView(activity).apply {adjustViewBounds=true;scaleType=ImageView.ScaleType.FIT_CENTER}
        dialog.body.addView(image,LinearLayout.LayoutParams(-1,activity.dp(240)))
        val error=activity.duckFailure(dialog.body,activity.getString(R.string.receiver_pair_start_failed))
        fun refresh() {
            val payload=ReceiverState.pairing
            val result=runCatching {
                check(ReceiverState.snapshot.value.phase=="ready"&&payload!=null)
                val size=512;val matrix=MultiFormatWriter().encode(payload,BarcodeFormat.QR_CODE,size,size)
                val pixels=IntArray(size*size) {index->if(matrix[index%size,index/size]) Color.BLACK else Color.WHITE}
                image.setImageBitmap(Bitmap.createBitmap(pixels,size,size,Bitmap.Config.ARGB_8888))
            }
            image.visibility=if(result.isSuccess) View.VISIBLE else View.GONE;error.visibility=if(result.isFailure) View.VISIBLE else View.GONE
        }
        dialog.body.addView(activity.duckButton(activity.getString(R.string.duck_pair_refresh)) {refresh()},LinearLayout.LayoutParams(-1,-2).apply {topMargin=activity.dp(20)})
        dialog.show();dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE);refresh()
    }
    private fun launchScan() {runCatching(scan).onFailure {scanned(null)}}
    private fun scanning() {
        scanPage?.dismiss()
        val page=DuckPage(activity,activity.getString(R.string.duck_scan_title));scanPage=page
        val art=ImageView(activity).apply {setImageResource(R.drawable.ic_scan);imageTintList=android.content.res.ColorStateList.valueOf(activity.getColor(R.color.duck_action));background=activity.duckBackground(R.color.duck_subtle,16,false);setPadding(activity.dp(48),activity.dp(48),activity.dp(48),activity.dp(48))}
        page.body.addView(art,LinearLayout.LayoutParams(-1,activity.dp(200)))
        page.body.addView(activity.duckParagraph(activity.getString(R.string.duck_scan_instruction)),LinearLayout.LayoutParams(-1,-2).apply {topMargin=activity.dp(20)})
        activity.duckNotice(page.body,activity.getString(R.string.duck_scan_permission))
        page.body.addView(activity.duckButton(activity.getString(R.string.duck_scan_start),true,::launchScan),LinearLayout.LayoutParams(-1,-2))
        page.setOnDismissListener {scanWork?.cancel();if(scanPage===page)scanPage=null};page.show();launchScan()
    }
    fun scanned(contents:String?) {
        val page=scanPage?:return
        page.body.removeAllViews()
        if(contents==null) {
            if(androidx.core.content.ContextCompat.checkSelfPermission(activity,android.Manifest.permission.CAMERA)!=android.content.pm.PackageManager.PERMISSION_GRANTED) activity.duckNotice(page.body,activity.getString(R.string.duck_scan_permission)) else activity.duckNotice(page.body,activity.getString(R.string.duck_scan_cancelled));page.body.addView(activity.duckButton(activity.getString(R.string.duck_scan_start),true,::launchScan));return
        }
        activity.duckNotice(page.body,activity.getString(R.string.receiver_pairing_connecting))
        scanWork=activity.lifecycleScope.launch {
            val result=withContext(Dispatchers.IO) {runCatching {
                require(contents.length<=32768);val pairing=ReceiverState.pairing?:error("receiver_not_ready")
                NativeBridge.request(JSONObject().put("op","submit_desktop_pairing").put("invite",JSONObject(contents)).put("pairing",JSONObject(pairing)))
            }}
            if(!page.isShowing)return@launch
            page.body.removeAllViews()
            result.onSuccess {
                activity.duckNotice(page.body,activity.getString(R.string.receiver_desktop_paired))
                page.body.addView(activity.duckButton(activity.getString(R.string.nav_receive),true) {page.dismiss()})
            }.onFailure {
                activity.duckProblem(page.body,activity.getString(R.string.duck_scan_code_fail))
                page.body.addView(activity.duckButton(activity.getString(R.string.duck_scan_start)) {page.dismiss();scanning()})
            }
        }
    }
}
