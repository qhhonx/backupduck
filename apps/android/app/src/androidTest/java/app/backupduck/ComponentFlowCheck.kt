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
        runOnMainSync {sheet=ui.code()};waitForIdleSync();Thread.sleep(350)
        val form=checkNotNull(sheet)
        val edit=views(form.body).filterIsInstance<TextInputEditText>().single()
        check(form.window!!.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_SECURE==0) {"Masked validation form cannot be captured"}
        check(edit.transformationMethod is AlwaysMaskedPassword) {"Access-code input lost its password mask"}
        val field=views(form.body).filterIsInstance<TextInputLayout>().single()
        val save=form.footer.getChildAt(0) as com.google.android.material.button.MaterialButton
        runOnMainSync {
            val label=views(form.body).filterIsInstance<TextView>().single {it.labelFor==edit.id}
            check(!field.isHintEnabled&&field.hint==null) {"Code field used a floating placeholder"}
            check(label.bottom<field.top) {"Code label is not outside the field"}
            check(kotlin.math.abs(field.top-label.bottom-activity.dp(8))<=2) {"Code label-to-input spacing drift"}
            val reset=views(form.body).filterIsInstance<com.google.android.material.button.MaterialButton>().single {it.text.toString()==activity.getString(R.string.duck_reset_random_code)}
            check(reset.strokeWidth>=activity.dp(1)) {"Reset action is not outlined"}
            check(views(form.body).filterIsInstance<TextView>().any {it.isShown&&it.text.toString()==activity.getString(R.string.duck_code_tasks_unchanged)}) {"Code information missing"}
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
        runOnMainSync {check(views(confirm!!.window!!.decorView).filterIsInstance<TextView>().any {it.isShown&&it.text.toString()==activity.getString(R.string.duck_revoke_sign_in)}) {"Revoke information missing"}}
        val revokeScreen=windowScreenshot()
        File(targetContext.cacheDir,"component-revoke-default-${if(dark) "dark" else "light"}.png").outputStream().use {revokeScreen.compress(Bitmap.CompressFormat.PNG,100,it)};revokeScreen.recycle()
        runOnMainSync {
            val button=Rect();check(confirm!!.confirm.getGlobalVisibleRect(button));check(button.height()==confirm!!.confirm.height) {"Confirmation action was clipped"}
            check(confirm!!.window!!.decorView.height<=activity.resources.displayMetrics.heightPixels) {"Confirmation exceeds display"}
        }
        runOnMainSync {confirm?.dismiss();confirm=ui.reset()}
        Thread.sleep(250)
        checkMessageAlignment(confirm!!.window!!.decorView)
        runOnMainSync {check(views(confirm!!.window!!.decorView).filterIsInstance<TextView>().any {it.isShown&&it.text.toString()==activity.getString(R.string.duck_reset_unchanged)}) {"Reset information missing"}}
        val resetScreen=windowScreenshot()
        File(targetContext.cacheDir,"component-reset-default-${if(dark) "dark" else "light"}.png").outputStream().use {resetScreen.compress(Bitmap.CompressFormat.PNG,100,it)};resetScreen.recycle()
        fail=true
        runOnMainSync {confirm!!.confirm.performClick();check(!confirm!!.confirm.isEnabled)}
        Thread.sleep(700);waitForIdleSync()
        runOnMainSync {
            check(confirm!!.isShowing&&confirm!!.confirm.isEnabled)
            check(confirm!!.failure.isShown) {"Confirmation failure did not remain actionable"}
            val retry=views(confirm!!.window!!.decorView).filterIsInstance<TextView>().single {it.isShown&&it.text.toString()==activity.getString(R.string.duck_retry)}
            check(retry.isEnabled)
            fail=false;retry.performClick()
        }
        Thread.sleep(700);waitForIdleSync()
        check(!confirm!!.isShowing) {"Confirmation retry did not complete"}
        runOnMainSync {confirm?.dismiss()}
        // Exercise the real shared startup controls: click, asynchronous error, auto retry,
        // manual retry and successful dashboard confirmation. No service or real port is used.
        val phases=kotlinx.coroutines.flow.MutableStateFlow(ReceiverSnapshot())
        var starts=0;var dashboardStarts=0
        var startup:BrowserStartupUI?=null
        runOnMainSync {
            sheet=DuckSheet(activity,activity.getString(R.string.dashboard_section))
            startup=BrowserStartupUI(activity,sheet!!.body,phases,startReceiver={starts++},request={dashboardStarts++;delay(100)})
            sheet!!.show()
        }
        Thread.sleep(300);waitForIdleSync()
        fun visibleText(value:String):Boolean=views(sheet!!.body).filterIsInstance<TextView>().any {it.text.toString()==value&&it.isShown}
        fun click(value:String)=runOnMainSync {views(sheet!!.body).filterIsInstance<TextView>().single {it.text.toString()==value&&it.isShown}.performClick();Unit}
        click(activity.getString(R.string.receiver_start))
        runOnMainSync {check(starts==1);check(visibleText(activity.getString(R.string.duck_browser_starting)))}
        phases.value=ReceiverSnapshot(phase="waiting",error="receiver_port_in_use")
        Thread.sleep(150);waitForIdleSync()
        checkMessageAlignment(sheet!!.body)
        runOnMainSync {check(visibleText(activity.getString(R.string.duck_start_port_busy)))}
        capture("startup-failed",sheet!!.body.rootView)
        phases.value=ReceiverSnapshot(phase="starting")
        Thread.sleep(150);waitForIdleSync()
        runOnMainSync {check(visibleText(activity.getString(R.string.duck_start_port_busy)))}
        click(activity.getString(R.string.duck_retry))
        runOnMainSync {check(starts==2);check(visibleText(activity.getString(R.string.duck_browser_starting)))}
        capture("startup-starting",sheet!!.body.rootView)
        phases.value=ReceiverSnapshot(phase="ready")
        Thread.sleep(250);waitForIdleSync()
        runOnMainSync {check(dashboardStarts==1&&startup!!.ready&&startup!!.view.visibility==View.GONE);startup!!.close();sheet!!.dismiss()}
        Thread.sleep(250)
        val previous=ReceiverState.mutable.value
        ReceiverState.mutable.value=ReceiverSnapshot(phase="ready")
        val accessUI=DashboardAccessUI(checkNotNull(browserHost)) {req ->
            when(req.getString("op")) {
                "start_dashboard" -> JSONObject()
                "dashboard_info" -> JSONObject().put("url","http://192.0.2.10:8485").put("code","0123456789")
                else -> error("Unexpected access operation")
            }
        }
        try {
            runOnMainSync {sheet=accessUI.access()};Thread.sleep(450);waitForIdleSync()
            runOnMainSync {
                check(sheet!!.window!!.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_SECURE==0)
                check(views(sheet!!.body).filterIsInstance<TextView>().none {it.text.toString().contains("0123456789")}) {"Credential leaked in review hierarchy"}
                check(visibleText("••••••••••"))
                val card=views(sheet!!.body).filterIsInstance<com.google.android.material.card.MaterialCardView>().single()
                val copy=views(sheet!!.body).filterIsInstance<TextView>().single {it.text.toString()==activity.getString(R.string.duck_copy_management_address)}
                val noticeTitle=views(sheet!!.body).filterIsInstance<TextView>().single {it.text.toString()==activity.getString(R.string.duck_code_private)}
                val notice=noticeTitle.parent.parent as View
                check(copy.parent===sheet!!.body && sheet!!.footer.visibility==View.GONE) {"Copy action moved to the footer"}
                check(kotlin.math.abs(copy.top-card.bottom-activity.dp(20))<=2) {"Address card-to-copy spacing drift"}
                check(kotlin.math.abs(notice.top-copy.bottom-activity.dp(16))<=2) {"Copy-to-notice spacing drift"}
            }
            val screen=windowScreenshot()
            runOnMainSync {
                val card=views(sheet!!.body).filterIsInstance<com.google.android.material.card.MaterialCardView>().single()
                val origin=IntArray(2);card.getLocationOnScreen(origin)
                val pixel=screen.getPixel(origin[0]+activity.dp(8),origin[1]+card.height/4)
                val expected=activity.getColor(R.color.duck_surface)
                check(kotlin.math.abs(android.graphics.Color.red(pixel)-android.graphics.Color.red(expected))<=2 &&
                    kotlin.math.abs(android.graphics.Color.green(pixel)-android.graphics.Color.green(expected))<=2 &&
                    kotlin.math.abs(android.graphics.Color.blue(pixel)-android.graphics.Color.blue(expected))<=2) {"Sheet card was tinted away from the design surface"}
            }
            File(targetContext.cacheDir,"component-access-masked-${if(dark) "dark" else "light"}.png").outputStream().use {screen.compress(Bitmap.CompressFormat.PNG,100,it)};screen.recycle()
            checkMessageAlignment(sheet!!.body)
            runOnMainSync {views(sheet!!.body).filterIsInstance<TextView>().single {it.text.toString()==activity.getString(R.string.duck_copy_management_address)}.performClick()}
            // Wait for the real snackbar enter animation to finish. A fixed
            // sleep can sample an intermediate frame on a busy emulator.
            var feedbackVisible=false
            val feedbackDeadline=android.os.SystemClock.uptimeMillis()+2500
            while(!feedbackVisible&&android.os.SystemClock.uptimeMillis()<feedbackDeadline) {
                runOnMainSync {
                    val feedback=views(sheet!!.window!!.decorView).filterIsInstance<TextView>().firstOrNull {it.text.toString()==activity.getString(R.string.duck_address_copied)}
                    val visible=Rect()
                    feedbackVisible=feedback!=null&&feedback.isShown&&feedback.getGlobalVisibleRect(visible)&&visible.height()==feedback.height
                }
                if(!feedbackVisible)Thread.sleep(40)
            }
            waitForIdleSync()
            runOnMainSync {
                val feedback=views(sheet!!.window!!.decorView).filterIsInstance<TextView>().single {it.text.toString()==activity.getString(R.string.duck_address_copied)}
                val shown=Rect();check(feedback.isShown&&feedback.getGlobalVisibleRect(shown)&&shown.height()==feedback.height) {"Copy acknowledgement hidden under dialog: shown=$shown height=${feedback.height} translation=${feedback.translationY} parent=${feedback.parent}"}
                val copied=(browserHost!!.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager).primaryClip?.getItemAt(0)?.text
                check(copied.toString()=="http://192.0.2.10:8485") {"Wrong management address copied"}
            }
            val copiedScreen=windowScreenshot()
            File(targetContext.cacheDir,"component-access-copied-${if(dark) "dark" else "light"}.png").outputStream().use {copiedScreen.compress(Bitmap.CompressFormat.PNG,100,it)};copiedScreen.recycle()
            runOnMainSync {views(sheet!!.body).single {it.contentDescription?.toString()==activity.getString(R.string.duck_show_access_code)}.performClick()}
            runOnMainSync {check(sheet!!.window!!.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_SECURE!=0);check(visibleText("0123456789"))}
            runOnMainSync {views(sheet!!.body).single {it.contentDescription?.toString()==activity.getString(R.string.duck_hide_access_code)}.performClick()}
            runOnMainSync {check(sheet!!.window!!.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_SECURE==0);check(!visibleText("0123456789"))}
            val hiddenAgain=windowScreenshot();hiddenAgain.recycle()
            runOnMainSync {sheet!!.dismiss()}
        } finally {ReceiverState.mutable.value=previous}
        Thread.sleep(250)
        val browserPage=startActivitySync(Intent(targetContext,BrowserManagementActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as BrowserManagementActivity
        try {
            waitForIdleSync();Thread.sleep(400)
            val screenshot=windowScreenshot()
            File(targetContext.cacheDir,"component-browser-page-${if(dark) "dark" else "light"}.png").outputStream().use {screenshot.compress(Bitmap.CompressFormat.PNG,100,it)}
            screenshot.recycle()
        } finally {runOnMainSync {browserPage.finish()}}
        return "PASS: rendered message icon/first-line alignment; copy clipboard and visible feedback in dialog window; prototype modal order/gaps/external label/outlined reset/reset and revoke information; startup click/error/sticky auto-retry/manual retry/ready; masked credential screenshot and protected reveal; native navigation has separate icon/label bounds; invalid input makes no request; failed write stays editable; retry succeeds; confirmation and form components. ${activity.resources.configuration.screenWidthDp}dp/font=${activity.resources.configuration.fontScale}"
    } finally {runOnMainSync {sheet?.dismiss();browserHost?.finish();activity.finish()}}
}
