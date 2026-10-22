package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import com.google.android.material.button.MaterialButton
import java.io.File

/** Isolated page check: no update download, website navigation or preference changes. */
internal fun Instrumentation.checkUpdatesLayout(args:Bundle):String {
    check(targetContext.packageName.endsWith(".validation")&&android.os.Build.MODEL.contains("sdk_gphone"))
    val prefs=targetContext.getSharedPreferences("appearance",0)
    val oldMode=prefs.getInt("mode",-1)
    val dark=args.getString("dark")=="true"
    prefs.edit().putInt("mode",if(dark)2 else 1).commit()
    val page=startActivitySync(Intent(targetContext,UpdatesActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as UpdatesActivity
    fun views(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {views(v.getChildAt(it))} else emptyList()
    try {
        waitForIdleSync()
        var result:Result<Unit>?=null
        runOnMainSync {result=runCatching {
            val actions=views(page.window.decorView).filterIsInstance<MaterialButton>()
            val action=actions.single {it.text.toString()==page.getString(R.string.updates_check)}
            val text=views(page.window.decorView).filterIsInstance<android.widget.TextView>()
            check(text.none {it.text.toString()==page.getString(R.string.updates_installed)}) {"Installed version must appear only in About"}
            check(actions.size==1) {"Update page must have only its check/download action"}
            val toggle=views(page.window.decorView).filterIsInstance<com.google.android.material.materialswitch.MaterialSwitch>().single()
            check(toggle.contentDescription==page.getString(R.string.updates_automatic))
            val status=text.single {it.text.toString()==page.getString(R.string.duck_update_development)}
            action.requestRectangleOnScreen(Rect(0,0,action.width,action.height),true)
            check(action.height>=page.dp(48))
            check(status.visibility==View.VISIBLE)
            check(!action.isEnabled&&toggle.isEnabled) {"Validation app must not download production updates"}
        }}
        result!!.getOrThrow();waitForIdleSync()
        runOnMainSync {views(page.window.decorView).filterIsInstance<android.widget.ScrollView>().single().fullScroll(View.FOCUS_DOWN)}
        waitForIdleSync();Thread.sleep(300)
        val image=checkNotNull(uiAutomation.takeScreenshot())
        File(targetContext.cacheDir,"updates-layout-${if(dark)"dark" else "light"}.png").outputStream().use {image.compress(Bitmap.CompressFormat.PNG,100,it)}
        image.recycle()
        return "PASS: one update action with 48dp target, status and automatic switch; no installed-version line; validation update disabled"
    } finally {
        runOnMainSync {page.finish()}
        if(oldMode<0)prefs.edit().remove("mode").commit() else prefs.edit().putInt("mode",oldMode).commit()
    }
}
