package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import kotlinx.coroutines.delay
import org.json.JSONObject
import java.io.File

/** Stateful UI checks with injected failures, isolated from real users and credentials. */
internal fun Instrumentation.checkComponentFlow(args:Bundle):String {
    check(targetContext.packageName.endsWith(".validation"))
    check(android.os.Build.FINGERPRINT.contains("generic")||android.os.Build.MODEL.contains("sdk_gphone"))
    ReceiverPreferences.setEnabled(targetContext,false)
    val dark=args.getString("dark")=="true"
    targetContext.getSharedPreferences("appearance",0).edit().putInt("mode",if(dark) 2 else 1).commit()
    uiAutomation.executeShellCommand("input keyevent 224").close()
    uiAutomation.executeShellCommand("wm dismiss-keyguard").close()
    val activity=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    fun views(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {views(v.getChildAt(it))} else emptyList()
    fun capture(name:String,view:View) {var bitmap:Bitmap?=null;runOnMainSync {bitmap=Bitmap.createBitmap(view.width,view.height,Bitmap.Config.ARGB_8888);view.draw(android.graphics.Canvas(bitmap!!))};File(targetContext.cacheDir,"component-$name-${if(dark) "dark" else "light"}.png").outputStream().use {bitmap!!.compress(Bitmap.CompressFormat.PNG,100,it)};bitmap?.recycle()}
    // The compositor can retain the previous secure layer for a few frames after dismissal.
    fun windowScreenshot():Bitmap {
        repeat(20) {uiAutomation.takeScreenshot()?.let {return it};Thread.sleep(200)}
        error("No screenshot after secure layer was removed")
    }
    // Inspect rendered ink, not just equal View rectangles: CJK fallback glyphs have
    // different ascenders from Latin and a constant top margin can still look crooked.
    fun checkMessageAlignment(root:View) = runOnMainSync {
        for(row in views(root).filterIsInstance<ViewGroup>().filter {it.tag=="duck.message"&&it.isShown&&it.width>0}) {
            val symbol=row.getChildAt(0)
            val heading=(row.getChildAt(1) as ViewGroup).getChildAt(0) as TextView
            val lines=checkNotNull(heading.layout)
            val bitmap=Bitmap.createBitmap(row.width,row.height,Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(activity.getColor(R.color.duck_surface));row.draw(android.graphics.Canvas(bitmap))
            fun area(view:View):Rect=Rect(0,0,view.width,view.height).also {
                row.offsetDescendantRectToMyCoords(view,it)
                // offsetDescendantRectToMyCoords supplies layout positions, not draw translations.
                it.offset(kotlin.math.round(view.translationX).toInt(),kotlin.math.round(view.translationY).toInt())
            }
            val iconArea=area(symbol)
            val titleArea=area(heading).apply {top+=heading.totalPaddingTop;bottom=top+lines.getLineBottom(0)}
            fun centre(region:Rect):Float {
                val bg=bitmap.getPixel((region.left-activity.dp(2)).coerceAtLeast(0),region.top.coerceIn(0,bitmap.height-1))
                var first=bitmap.height;var last=-1
                for(y in region.top.coerceAtLeast(0) until region.bottom.coerceAtMost(bitmap.height)) {
                    for(x in region.left.coerceAtLeast(0) until region.right.coerceAtMost(bitmap.width)) {
                        val pixel=bitmap.getPixel(x,y)
                        val diff=kotlin.math.abs(android.graphics.Color.red(pixel)-android.graphics.Color.red(bg))+kotlin.math.abs(android.graphics.Color.green(pixel)-android.graphics.Color.green(bg))+kotlin.math.abs(android.graphics.Color.blue(pixel)-android.graphics.Color.blue(bg))
                        if(diff>100) {first=minOf(first,y);last=maxOf(last,y)}
                    }
                }
                check(last>=first) {"Message ink was not found: ${heading.text}"}
                return (first+last)/2f
            }
            val difference=kotlin.math.abs(centre(iconArea)-centre(titleArea));bitmap.recycle()
            check(difference<=activity.dp(1)) {"Icon is misaligned by $difference px: ${heading.text}"}
        }
    }
    var calls=0;var fail=true
    var sheet:DuckSheet?=null
    var editDialog:DuckEditDialog?=null
    var browserHost:BrowserManagementActivity?=null
    try {
        Thread.sleep(900)
        val nav=views(activity.window.decorView).filterIsInstance<BottomNavigationView>().single()
        runOnMainSync {
            nav.selectedItemId=4
            val icons=views(nav).filter {it.id==com.google.android.material.R.id.navigation_bar_item_icon_view}
            check(icons.size==4)
            for(icon in icons) {
                var item=icon.parent as ViewGroup
                while(views(item).filterIsInstance<TextView>().none {it.text.isNotEmpty()} && item.parent is ViewGroup && item.parent!==nav) item=item.parent as ViewGroup
                val labels=views(item).filterIsInstance<TextView>().filter {it.visibility==View.VISIBLE&&it.alpha>.1f&&it.text.isNotEmpty()}
                check(labels.isNotEmpty()) {"Navigation label not found"}
                val ir=Rect();icon.getGlobalVisibleRect(ir)
                for(label in labels) {val lr=Rect();label.getGlobalVisibleRect(lr);check(lr.top>=ir.bottom) {"Navigation icon overlaps ${label.text}: $ir vs $lr"}}
            }
        }
        capture("navigation",activity.window.decorView)
        browserHost=startActivitySync(Intent(targetContext,BrowserManagementActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as BrowserManagementActivity
        Thread.sleep(400);waitForIdleSync()
        val ui=DashboardAccessUI(checkNotNull(browserHost)) {request ->
            calls++;delay(200)
            check(request.getString("op")=="dashboard_access")
            if(fail) error("injected_failure")
            JSONObject().put("code","0123456789")
        }
        runOnMainSync {editDialog=ui.code()};waitForIdleSync();Thread.sleep(350)
        val form=checkNotNull(editDialog)
        val edit=views(form.body).filterIsInstance<TextInputEditText>().single()
        check(form.window!!.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_SECURE==0) {"Masked validation form cannot be captured"}
        check(edit.transformationMethod is AlwaysMaskedPassword) {"Access-code input lost its password mask"}
        val field=views(form.body).filterIsInstance<TextInputLayout>().single()
        val save=form.save
        runOnMainSync {
            check(field.isHintEnabled && field.hint.toString()==activity.getString(R.string.duck_new_access_code)) {"Native field label missing"}
            check(views(form.body).filterIsInstance<TextView>().any {it.isShown&&it.text.toString()==activity.getString(R.string.browser_preserved_note)}) {"Code information missing"}
        }
        val formScreen=windowScreenshot()
        checkMessageAlignment(form.body)
        File(targetContext.cacheDir,"component-code-default-${if(dark) "dark" else "light"}.png").outputStream().use {formScreen.compress(Bitmap.CompressFormat.PNG,100,it)};formScreen.recycle()
        runOnMainSync {
            edit.setText("123")
            views(form.body).filterIsInstance<com.google.android.material.button.MaterialButton>().single {it.text.toString()==activity.getString(R.string.duck_reset_random_code)}.performClick()
        }
        Thread.sleep(300);waitForIdleSync()
        runOnMainSync {check(!form.window!!.decorView.isShown) {"Reset confirmation was stacked over the code sheet"}}
        sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        Thread.sleep(350);waitForIdleSync()
        runOnMainSync {check(form.window!!.decorView.isShown&&edit.text.toString()=="123") {"Cancel reset lost the access-code draft"}}
        runOnMainSync {edit.setText("123");check(edit.transformationMethod.getTransformation(edit.text,edit).toString()=="•••");save.performClick()}
        check(calls==0) {"Invalid code reached backend"}
        runOnMainSync {check(!field.error.isNullOrEmpty())}
        capture("code-invalid",form.body.rootView)
        runOnMainSync {
            val button=Rect();check(save.getGlobalVisibleRect(button));check(button.height()==save.height) {"Sheet action was clipped"}
        }
        runOnMainSync {edit.setText("0123456789");save.performClick();check(!save.isEnabled)}
        Thread.sleep(700);waitForIdleSync()
        runOnMainSync {check(form.isShowing&&save.isEnabled);check(views(form.body).filterIsInstance<TextView>().any {it.visibility==View.VISIBLE&&it.text.toString().contains(activity.getString(R.string.duck_code_save_failed))})}
        check(calls==1)
        capture("code-failure",form.body.rootView)
        fail=false
        runOnMainSync {save.performClick()};Thread.sleep(700);waitForIdleSync()
        check(calls==2);check(!form.isShowing) {"Successful save did not dismiss"}
        var confirm:DuckConfirmation?=null
        runOnMainSync {confirm=ui.revoke()}
        Thread.sleep(250);capture("confirmation",confirm!!.window!!.decorView)
        checkMessageAlignment(confirm!!.window!!.decorView)
        runOnMainSync {check(views(confirm!!.window!!.decorView).filterIsInstance<TextView>().any {it.isShown&&it.text.toString().contains(activity.getString(R.string.browser_preserved_note))}) {"Revoke information missing"}}
        val revokeScreen=windowScreenshot()
        File(targetContext.cacheDir,"component-revoke-default-${if(dark) "dark" else "light"}.png").outputStream().use {revokeScreen.compress(Bitmap.CompressFormat.PNG,100,it)};revokeScreen.recycle()
        runOnMainSync {
            val button=Rect();check(confirm!!.confirm.getGlobalVisibleRect(button));check(button.height()==confirm!!.confirm.height) {"Confirmation action was clipped"}
            check(confirm!!.window!!.decorView.height<=activity.resources.displayMetrics.heightPixels) {"Confirmation exceeds display"}
        }
        runOnMainSync {confirm?.dismiss();confirm=ui.reset()}
        Thread.sleep(250)
        checkMessageAlignment(confirm!!.window!!.decorView)
        runOnMainSync {check(views(confirm!!.window!!.decorView).filterIsInstance<TextView>().any {it.isShown&&it.text.toString().contains(activity.getString(R.string.browser_preserved_note))}) {"Reset information missing"}}
        val resetScreen=windowScreenshot()
        File(targetContext.cacheDir,"component-reset-default-${if(dark) "dark" else "light"}.png").outputStream().use {resetScreen.compress(Bitmap.CompressFormat.PNG,100,it)};resetScreen.recycle()
        fail=true
        runOnMainSync {confirm!!.confirm.performClick();check(!confirm!!.confirm.isEnabled)}
        Thread.sleep(700);waitForIdleSync()
        runOnMainSync {
            check(confirm!!.isShowing&&confirm!!.confirm.isEnabled)
            check(views(confirm!!.window!!.decorView).filterIsInstance<TextView>().any {
                it.isShown && it.text.toString().contains(activity.getString(R.string.duck_access_change_failed))
            }) {"Confirmation failure did not remain actionable"}
            fail=false;confirm!!.confirm.performClick()
        }
        Thread.sleep(700);waitForIdleSync()
        check(!confirm!!.isShowing) {"Confirmation retry did not complete"}
        runOnMainSync {confirm?.dismiss()}
        // Browser startup and protected hold-to-reveal are covered by Catalog device scenarios.
        val browserPage=startActivitySync(Intent(targetContext,BrowserManagementActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as BrowserManagementActivity
        try {
            waitForIdleSync();Thread.sleep(400)
            val screenshot=windowScreenshot()
            File(targetContext.cacheDir,"component-browser-page-${if(dark) "dark" else "light"}.png").outputStream().use {screenshot.compress(Bitmap.CompressFormat.PNG,100,it)}
            screenshot.recycle()
        } finally {runOnMainSync {browserPage.finish()}}
        return "PASS: shared confirmation and credential edit validation/failure/retry; Material navigation and browser page capture. Browser state/hold verification uses Catalog scenarios."
    } finally {runOnMainSync {editDialog?.dismiss();sheet?.dismiss();browserHost?.finish();activity.finish()}}
}
