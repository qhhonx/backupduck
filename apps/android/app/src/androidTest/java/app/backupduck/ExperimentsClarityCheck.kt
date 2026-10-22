package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import com.google.android.material.materialswitch.MaterialSwitch
import org.json.JSONObject
import java.io.File

/** Synthetic UI states only; never connects Accessibility or runs Google Photos cleanup. */
internal fun Instrumentation.checkExperimentsClarity(args:Bundle):String {
    check(targetContext.packageName.endsWith(".validation")&&android.os.Build.MODEL.contains("sdk_gphone"))
    val dark=args.getString("dark")=="true"
    val localeManager=targetContext.getSystemService(android.app.LocaleManager::class.java)
    val oldLocales=localeManager.applicationLocales
    val prefs=targetContext.getSharedPreferences("photos_cleanup",0)
    val old=prefs.all
    val discoveries=targetContext.getSharedPreferences("feature_discovery",0)
    val previousDiscovery=discoveries.all[FeatureDiscovery.PHOTOS_CLEANUP]
    discoveries.edit().remove(FeatureDiscovery.PHOTOS_CLEANUP).commit()
    val oldTheme=targetContext.getSharedPreferences("appearance",0).getInt("mode",-1)
    targetContext.getSharedPreferences("appearance",0).edit().putInt("mode",if(dark)2 else 1).commit()
    prefs.edit().remove("account").putBoolean("enabled",false).putString("state","{}").putString("reason","ready").commit()
    fun <T> main(f:()->T):T {var r:Result<T>?=null;runOnMainSync {r=runCatching(f)};return r!!.getOrThrow()}
    localeManager.applicationLocales=android.os.LocaleList.forLanguageTags("zh-CN")
    fun all(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {all(v.getChildAt(it))} else emptyList()
    fun settle(){waitForIdleSync();Thread.sleep(500)}
    fun texts(a:android.app.Activity,id:Int)=all(a.window.decorView).filterIsInstance<TextView>().filter {it.isShown&&it.text.toString()==a.getString(id)}
    fun shot(name:String){settle();var activePackage:String?=null
        for(attempt in 0 until 30) {activePackage=uiAutomation.rootInActiveWindow?.packageName?.toString();if(activePackage==targetContext.packageName)break;Thread.sleep(100)}
        check(activePackage==targetContext.packageName) {"Screenshot is obscured by another window: $activePackage"};val b=checkNotNull(uiAutomation.takeScreenshot());File(targetContext.cacheDir,"experiments-$name-${if(dark)"dark" else "light"}.png").outputStream().use {b.compress(Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
    val pages=mutableListOf<android.app.Activity>()
    try {
        val home=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        pages+=home;settle()
        val navigation=home.findViewById<com.google.android.material.bottomnavigation.BottomNavigationView>(R.id.main_navigation)
        main {
            check(navigation.getBadge(4)?.isVisible==true)
            navigation.selectedItemId=4
            check(FeatureDiscovery(targetContext).isUnseen(FeatureDiscovery.PHOTOS_CLEANUP))
            val dot=all(home.window.decorView).single {it.tag=="duck.discovery"}
            check(dot.visibility==View.VISIBLE)
        };settle();main {
            val dot=all(home.window.decorView).single {it.tag=="duck.discovery"}
            check(dot.width>0&&dot.height>0)
            val row=dot.parent as View
            row.requestRectangleOnScreen(Rect(0,0,row.width,row.height),true)
        };settle();main {
            val dot=all(home.window.decorView).single {it.tag=="duck.discovery"}
            val row=dot.parent as View
            val visible=Rect()
            check(row.getGlobalVisibleRect(visible)&&visible.height()==row.height&&visible.width()==row.width)
        };shot("discovery-settings")
        main { home.openCleanup() };settle()
        main {
            check(texts(home,R.string.storage_automatic).size==1)
            check(!FeatureDiscovery(targetContext).isUnseen(FeatureDiscovery.PHOTOS_CLEANUP))
            check(!PhotosCleanup(targetContext).enabled)
            check(navigation.getBadge(4)==null)
            val screen=MainActivity::class.java.getDeclaredField("storageScreen").apply {isAccessible=true}.get(home) as StorageScreen
            screen.showCleanupConsent()
            val sheet=StorageScreen::class.java.getDeclaredField("consentSheet").apply {isAccessible=true}.get(screen) as LookSheet
            val labels=all(sheet.window!!.decorView).filterIsInstance<TextView>()
            check(labels.count {it.text.toString()==home.getString(R.string.storage_cleanup_consent_access)}==1)
            check(labels.none {it.text.toString()==home.getString(R.string.photos_probe_start)})
            labels.single {it.text.toString()==home.getString(R.string.onb_later)}.performClick()
            check(!PhotosCleanup(targetContext).enabled)
            home.onBackPressedDispatcher.onBackPressed()
        };settle()
        main {
            check(all(home.window.decorView).single {it.tag=="duck.discovery"}.visibility==View.GONE)
            home.finish()
        }
        val reopened=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        pages+=reopened;settle();main {check(reopened.findViewById<com.google.android.material.bottomnavigation.BottomNavigationView>(R.id.main_navigation).getBadge(4)==null);check(!PhotosCleanup(targetContext).enabled);reopened.finish()}
        val page=startActivitySync(Intent(targetContext,PhotosProbeActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as PhotosProbeActivity
        pages+=page;settle()
        fun render(s:PhotosProbeState)=main {PhotosProbeActivity::class.java.getDeclaredMethod("render",PhotosProbeState::class.java).apply {isAccessible=true}.invoke(page,s);Unit}
        fun reveal(id:Int)=main {val v=texts(page,id).single();v.requestRectangleOnScreen(Rect(0,0,v.width,v.height),true)}
        main {check(texts(page,R.string.experiment_permission_off).isNotEmpty());check(texts(page,R.string.cleanup_now).isEmpty());check(all(page.window.decorView).filterIsInstance<MaterialSwitch>().isEmpty())}
        shot("setup")
        val cleanup=PhotosCleanup(targetContext);cleanup.account="synthetic-account-fingerprint";cleanup.report("bound")
        render(PhotosProbeState(connected=true));main {check(texts(page,R.string.experiment_account_on).size==1);check(all(page.window.decorView).filterIsInstance<MaterialSwitch>().isEmpty())}
        reveal(R.string.cleanup_now);shot("ready")
        render(PhotosProbeState(connected=true,running=true,observation="opening_cleanup",mode="cleanup"))
        main {check(texts(page,R.string.cleanup_stop).size==1);check(!(texts(page,R.string.experiment_account).single().parent.parent as View).isEnabled)}
        reveal(R.string.cleanup_stop);shot("running")
        cleanup.report("account_changed");render(PhotosProbeState(connected=true))
        main {check(texts(page,R.string.experiment_account_changed).size==1);check(texts(page,R.string.cleanup_now).isEmpty());check(all(page.window.decorView).filterIsInstance<MaterialSwitch>().isEmpty())}
        reveal(R.string.experiment_account_changed);shot("account-changed")
        cleanup.save(JSONObject().put("phase","pending"),"pending");render(PhotosProbeState(connected=true))
        main {check(texts(page,R.string.cleanup_check_pending).size==1);check(texts(page,R.string.cleanup_reviewed).size==1)}
        reveal(R.string.cleanup_reviewed);shot("pending")
        val bindRow=main {texts(page,R.string.experiment_account).single().parent.parent as View}
        main {check(bindRow.isEnabled);check(texts(page,R.string.experiment_account_pending).size==1)}
        reveal(R.string.photos_diagnostics_title);shot("troubleshoot")
        main {page.finish()}
        val diagnostic=startActivitySync(Intent(targetContext,PhotosProbeActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("diagnostics",true)).also {pages+=it}
        settle();main {check(texts(diagnostic,R.string.photos_probe_steps).size==1);check(texts(diagnostic,R.string.experiment_probe_intro).size==1)};shot("diagnostics")
        main {diagnostic.finish()}
        cleanup.save(JSONObject().put("phase","finished"),"nothing_to_free")
        val progress=startActivitySync(Intent(targetContext,PhotosProbeActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("route","progress")) as PhotosProbeActivity
        pages+=progress;settle()
        main {
            PhotosProbeActivity::class.java.getDeclaredMethod("render",PhotosProbeState::class.java).apply {isAccessible=true}.invoke(progress,PhotosProbeState(connected=true,observation="nothing_to_free",mode="cleanup"))
            check(texts(progress,R.string.cleanup_result_nothing_to_free).size==1)
            check(texts(progress,R.string.cleanup_now).size==2) // navigation title and action
            check(all(progress.window.decorView).filterIsInstance<TextView>().none {it.isShown&&it.text.contains("回执")})
            check(texts(progress,R.string.cleanup_reviewed).isEmpty())
        }
        shot("result-empty")
        return "PASS: Storage acknowledges discovery across restart without enabling cleanup; shared consent cancels without granting access; Storage owns the sole switch; technical setup retains account checks, running stop, changed-account recovery, pending review and probe/result pages. No Google Photos operation executed."
    } finally {
        main {pages.forEach {it.finish()};localeManager.applicationLocales=oldLocales}
        val e=prefs.edit();for(key in listOf("account","enabled","state","reason")){e.remove(key);when(val value=old[key]){is String->e.putString(key,value);is Boolean->e.putBoolean(key,value)}};e.commit()
        targetContext.getSharedPreferences("appearance",0).edit().putInt("mode",oldTheme).commit()
        discoveries.edit().apply {if(previousDiscovery is Boolean)putBoolean(FeatureDiscovery.PHOTOS_CLEANUP,previousDiscovery) else remove(FeatureDiscovery.PHOTOS_CLEANUP)}.commit()
    }
}
