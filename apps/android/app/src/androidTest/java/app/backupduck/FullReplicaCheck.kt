package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.*
import androidx.appcompat.app.AppCompatDelegate
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.materialswitch.MaterialSwitch
import org.json.JSONObject
import java.io.File

/** Execute real native forms on disposable emulator data; no screenshots are user sign-off. */
internal fun Instrumentation.checkFullReplica(args:Bundle):String {
    check(targetContext.packageName.endsWith(".validation"))
    check(android.os.Build.MODEL.contains("sdk_gphone")||android.os.Build.FINGERPRINT.contains("generic"))
    ReceiverPreferences.setEnabled(targetContext,false)
    val dark=args.getString("dark")=="true"
    targetContext.getSharedPreferences("appearance",0).edit().putInt("mode",if(dark)2 else 1).commit()
    uiAutomation.executeShellCommand("input keyevent 224").close();uiAutomation.executeShellCommand("wm dismiss-keyguard").close()
    fun <T> main(action:()->T):T {var value:Result<T>?=null;runOnMainSync {value=runCatching(action)};return value!!.getOrThrow()}
    fun views(view:View):List<View> = listOf(view)+if(view is ViewGroup)(0 until view.childCount).flatMap {views(view.getChildAt(it))} else emptyList()
    fun root():View=WindowInspector.getGlobalWindowViews().last {it.isShown&&it.hasWindowFocus()}
    fun settle() {waitForIdleSync();Thread.sleep(400)}
    fun textExists(id:Int):Boolean=main {views(root()).filterIsInstance<TextView>().any {it.isShown&&it.text.toString()==targetContext.getString(id)}}
    fun click(id:Int) = main {
        val text=views(root()).filterIsInstance<TextView>().first {it.text.toString()==targetContext.getString(id)}
        var view:View=text
        while(!view.isClickable) view=view.parent as View
        view.requestRectangleOnScreen(Rect(0,0,view.width,view.height),true);view.performClick();Unit
    }
    fun back() {sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK);settle()}
    fun shot(name:String) {
        settle();val image=checkNotNull(uiAutomation.takeScreenshot())
        File(targetContext.cacheDir,"full-$name-${if(dark)"dark" else "light"}.png").outputStream().use {image.compress(Bitmap.CompressFormat.PNG,100,it)};image.recycle()
    }
    val activity=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    val settingsRoot="${targetContext.filesDir}/receiver"
    fun config()=(NativeBridge.request(JSONObject().put("op","receiver_settings").put("root",settingsRoot)) as JSONObject).getJSONObject("settings")
    val oldConfig=config();val oldName=DeviceProfiles.read(targetContext).getJSONObject("device").getString("name")
    val oldThermal=ReceiverThermalSettings.enabled(targetContext);val oldThreshold=ReceiverThermalSettings.threshold(targetContext);val oldConversion=MotionConversionSettings.enabled(targetContext)
    var current:android.app.Dialog?=null
    try {
        settle()
        var starts=0
        val pairing=PairingUI(activity,start={starts++},scan={})
        main {pairing.iphone()};settle();check(starts==1&&textExists(R.string.duck_pairing_starting))
        main {pairing.update(ReceiverSnapshot(phase="waiting",error="receiver_port_in_use"))};settle()
        check(textExists(R.string.duck_start_port_busy)||textExists(R.string.recovery_port)) {"Specific pairing failure not visible"}
        click(R.string.duck_retry);check(starts==2);back()
        main {current=activity.showThermalSettings()};settle()
        check(textExists(R.string.duck_thermal_resume));shot("thermal")
        main {
            val choice=views(root()).filterIsInstance<TextView>().single {it.text.toString()=="43 °C"}
            (choice.parent.parent as View).performClick()
        };check(ReceiverThermalSettings.threshold(targetContext)==43);back()
        main {current=activity.showConversionSettings()};settle()
        check(textExists(R.string.duck_conversion_off_note)&&textExists(R.string.duck_conversion_cloud_note));shot("conversion")
        main {views(root()).filterIsInstance<MaterialSwitch>().single().performClick()}
        check(MotionConversionSettings.enabled(targetContext)!=oldConversion);back()
        val devices=DevicePanels(activity)
        main {devices.refresh()};Thread.sleep(700)
        main {current=devices.rename()};settle()
        val field=main {views(root()).filterIsInstance<com.google.android.material.textfield.TextInputEditText>().single()}
        main {field.setText("")};click(R.string.device_save);settle()
        check(DeviceProfiles.read(targetContext).getJSONObject("device").getString("name")==oldName)
        check(main {views(root()).filterIsInstance<com.google.android.material.textfield.TextInputLayout>().single().error!=null})
        main {field.setText("UI Check Pixel")};shot("device-name");click(R.string.device_save);Thread.sleep(900)
        check(DeviceProfiles.read(targetContext).getJSONObject("device").getString("name")=="UI Check Pixel")
        main {current=devices.showPeers()};settle();shot("devices");back()
        val custom=JSONObject(oldConfig.toString()).put("receiver_budget_bytes",123456789L).put("min_free_bytes",456789L).put("receiver_relay",false)
        NativeBridge.request(JSONObject().put("op","receiver_settings").put("root",settingsRoot).put("settings",custom))
        for(section in StorageSection.entries) {
            main {current=activity.showStorageControls(section) {}};Thread.sleep(800);settle()
            check(main {views(root()).filterIsInstance<Spinner>().size==2})
            shot(if(section==StorageSection.LIMITS)"storage-limits" else "log-limits")
            click(R.string.settings_save);Thread.sleep(700)
            check(config().getLong("receiver_budget_bytes")==123456789L&&config().getLong("min_free_bytes")==456789L) {"Custom limits rounded by native form"}
        }
        var retention:RetentionControls?=null
        main {current=DuckSheet(activity,activity.getString(R.string.duck_retention)).also {retention=RetentionControls(activity,it.body,owner=it);retention!!.render(false);it.show()}}
        settle();main {views(root()).filterIsInstance<MaterialSwitch>().single().performClick()};settle()
        check(!config().getBoolean("receiver_relay"));shot("relay-scope");back();check(!config().getBoolean("receiver_relay"))
        // Cancelled scope retains safe configuration, then explicit save changes it.
        main {retention!!.scope()};settle();click(R.string.settings_save);Thread.sleep(900)
        check(config().getBoolean("receiver_relay")) {"Scope save did not persist"};back()
        main {current=activity.showArchiveIntro {}};settle();check(textExists(R.string.duck_export_no_delete));shot("archive");back()
        main {activity.showDiagnostics()};settle();shot("diagnostics");click(R.string.receiver_stop);settle()
        check(textExists(R.string.duck_stop_service_intro));shot("stop");back();back()
        val nav=main {activity.findViewById<BottomNavigationView>(R.id.main_navigation)}
        main {nav.selectedItemId=3};Thread.sleep(800);shot("storage")
        main {nav.selectedItemId=4};settle();shot("settings")
        val experiments=startActivitySync(Intent(targetContext,ExperimentsActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as ExperimentsActivity
        try {settle();shot("experiments")} finally {main {experiments.finish()}}
        for((route,diagnostics) in listOf("cleanup" to false,"bind" to false,"progress" to false,"diagnostics" to true)) {
            val page=startActivitySync(Intent(targetContext,PhotosProbeActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("route",route).putExtra("diagnostics",diagnostics)) as PhotosProbeActivity
            try {settle();shot(if(route=="diagnostics")"photos-diagnostics" else route);if(route=="cleanup") {click(R.string.duck_cleanup_permission);settle();check(textExists(R.string.duck_cleanup_cloud_boundary));shot("cleanup-consent");back()}}
            finally {main {page.finish()}}
        }
        val updates=startActivitySync(Intent(targetContext,UpdatesActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as UpdatesActivity
        try {settle();check(textExists(R.string.duck_update_development));shot("updates")} finally {main {updates.finish()}}
        return "PASS: real pairing pending/error/retry; thermal persistence; conversion; rename validation/persistence; devices; exact storage/log limits; cancelled and saved relay scope; export and stop notices; settings/storage/diagnostics/experiments/account/progress/update screens. ${activity.resources.configuration.screenWidthDp}dp/font=${activity.resources.configuration.fontScale}"
    } finally {
        RelayMaintenance.cancelAutomatic()
        NativeBridge.request(JSONObject().put("op","receiver_settings").put("root",settingsRoot).put("settings",oldConfig))
        DeviceProfiles.read(targetContext,oldName);ReceiverThermalSettings.setEnabled(targetContext,oldThermal);ReceiverThermalSettings.setThreshold(targetContext,oldThreshold);MotionConversionSettings.setEnabled(targetContext,oldConversion)
        main {
            // Theme changes can recreate the host while a previously closed
            // dialog remains referenced by this check. Only dismiss attached windows.
            current?.takeIf {it.window?.decorView?.isAttachedToWindow==true}?.dismiss()
            activity.finish()
        }
    }
}
