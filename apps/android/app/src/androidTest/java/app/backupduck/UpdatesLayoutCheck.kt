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
            val upper=actions.single {it.text.toString()==page.getString(R.string.updates_check)}
            val lower=actions.single {it.text.toString()==page.getString(R.string.official_website)}
            lower.requestRectangleOnScreen(Rect(0,0,lower.width,lower.height),true)
            val top=IntArray(2);val bottom=IntArray(2)
            upper.getLocationOnScreen(top);lower.getLocationOnScreen(bottom)
            check(bottom[1]-(top[1]+upper.height)>=page.dp(8)) {"Update actions touch or overlap"}
            check(top[0]==bottom[0]&&upper.width==lower.width)
            check(upper.height>=page.dp(48)&&lower.height>=page.dp(48))
            check(!upper.isEnabled&&lower.isEnabled) {"Validation app must not download production updates"}
        }}
        result!!.getOrThrow();waitForIdleSync()
        runOnMainSync {views(page.window.decorView).filterIsInstance<android.widget.ScrollView>().single().fullScroll(View.FOCUS_DOWN)}
        waitForIdleSync();Thread.sleep(300)
        val image=checkNotNull(uiAutomation.takeScreenshot())
        File(targetContext.cacheDir,"updates-layout-${if(dark)"dark" else "light"}.png").outputStream().use {image.compress(Bitmap.CompressFormat.PNG,100,it)}
        image.recycle()
        return "PASS: update actions separated by 8dp, equal width, 48dp minimum targets; validation update disabled"
    } finally {
        runOnMainSync {page.finish()}
        if(oldMode<0)prefs.edit().remove("mode").commit() else prefs.edit().putInt("mode",oldMode).commit()
    }
}
