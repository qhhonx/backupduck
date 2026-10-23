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
    var current:android.content.DialogInterface?=null
    var conversion:LookPage?=null
    try {
        settle()
        var starts=0
        val previousSnapshot=ReceiverState.snapshot.value
        val previousPairing=ReceiverState.pairing
        try {
            main {ReceiverState.mutable.value=ReceiverSnapshot(phase="starting");ReceiverState.pairing=null}
            val connect=main {ConnectPage(activity, {}, {starts++}, Bundle(), {}).also {it.show()}}
            settle();check(starts==1&&textExists(R.string.connect_getting_ready))
            main {ReceiverState.mutable.value=ReceiverSnapshot(phase="waiting",error="receiver_port_in_use")}
            Thread.sleep(600);settle()
            check(textExists(R.string.recovery_port)) {"Specific Connect failure not visible"}
            click(R.string.connect_try_again);check(starts==2);back()
        } finally {main {ReceiverState.mutable.value=previousSnapshot;ReceiverState.pairing=previousPairing}}
        main {conversion=activity.restorePage("conversion",Bundle()) as LookPage;conversion!!.show()};settle()
        main {
            check(activity.supportFragmentManager.backStackEntryCount==1)
            check(views(conversion!!.root).filterIsInstance<com.google.android.material.appbar.MaterialToolbar>().single().title==activity.getString(R.string.pref_advanced_settings))
        }
        shot("conversion")
        main {views(conversion!!.root).filterIsInstance<MaterialSwitch>().single().performClick()}
        check(MotionConversionSettings.enabled(targetContext)!=oldConversion);back()
        main {check(activity.supportFragmentManager.backStackEntryCount==0)}
        val devices=DevicePanels(activity)
        main {devices.refresh()};Thread.sleep(700)
        main {current=devices.rename()};settle()
        val field=main {views(root()).filterIsInstance<com.google.android.material.textfield.TextInputEditText>().single()}
        main {field.setText("")};click(R.string.device_save);settle()
        check(DeviceProfiles.read(targetContext).getJSONObject("device").getString("name")==oldName)
        check(main {views(root()).filterIsInstance<com.google.android.material.textfield.TextInputLayout>().single().error!=null})
        main {field.setText("UI Check Pixel")};shot("device-name");click(R.string.device_save);Thread.sleep(900)
        check(DeviceProfiles.read(targetContext).getJSONObject("device").getString("name")=="UI Check Pixel")
        main {activity.restorePage("legacy-devices",Bundle()).show()};settle();main {check(activity.supportFragmentManager.backStackEntryCount==1)};shot("devices");back()
        // Retired storage/retention/archive routes are checked as redirects in Catalog.
        main {activity.showDiagnostics()};settle();shot("diagnostics");back();main {activity.startActivity(Intent(activity,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra("surface","advanced"))};settle();click(R.string.receiver_stop);settle()
        check(textExists(R.string.duck_stop_service_intro));shot("stop");back();back()
        val nav=main {activity.findViewById<BottomNavigationView>(R.id.main_navigation)}
        main {activity.openStorage()};Thread.sleep(800);shot("storage");back()
        main {nav.selectedItemId=4};settle();shot("settings")
        val experiments=startActivitySync(Intent(targetContext,ExperimentsActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as ExperimentsActivity
        try {settle();check(textExists(R.string.pref_storage));shot("experiments")} finally {main {experiments.finish()}}
        val updates=startActivitySync(Intent(targetContext,UpdatesActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as UpdatesActivity
        try {
            settle();check(textExists(R.string.duck_update_development))
            main {
                val actions=views(root()).filterIsInstance<com.google.android.material.button.MaterialButton>()
                val checkButton=actions.single {it.text.toString()==targetContext.getString(R.string.updates_check)}
                val website=actions.single {it.text.toString()==targetContext.getString(R.string.official_website)}
                val upper=IntArray(2);val lower=IntArray(2)
                checkButton.getLocationOnScreen(upper);website.getLocationOnScreen(lower)
                check(lower[1]-(upper[1]+checkButton.height)>=updates.dp(8)) {"Update actions touch or overlap"}
                check(upper[0]==lower[0]&&checkButton.width==website.width)
            }
            shot("updates")
        } finally {main {updates.finish()}}
        return "PASS: current Connect pending/error/retry; retained thermal preferences; current Advanced conversion; rename validation/persistence; devices; retired editor/archive surfaces omitted; stop notices; settings/storage/diagnostics/compatibility trampoline/update screens. ${activity.resources.configuration.screenWidthDp}dp/font=${activity.resources.configuration.fontScale}"
    } finally {
        RelayMaintenance.cancelAutomatic()
        NativeBridge.request(JSONObject().put("op","receiver_settings").put("root",settingsRoot).put("settings",oldConfig))
        DeviceProfiles.read(targetContext,oldName);ReceiverThermalSettings.setEnabled(targetContext,oldThermal);ReceiverThermalSettings.setThreshold(targetContext,oldThreshold);MotionConversionSettings.setEnabled(targetContext,oldConversion)
        main {
            // Theme changes can recreate the host while a previously closed
            // dialog remains referenced by this check. Only dismiss attached windows.
            current?.dismiss()
            activity.finish()
        }
    }
}
