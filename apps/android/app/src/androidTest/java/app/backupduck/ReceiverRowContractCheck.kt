package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.*
import java.io.File

/** Synthetic controls only: no service, receipt or reclamation operation. */
internal fun Instrumentation.checkReceiverRowContract(args:Bundle):String {
    check(targetContext.packageName.endsWith(".validation"))
    check(android.os.Build.MODEL.contains("sdk_gphone"))
    val enabled=ReceiverPreferences.enabled(targetContext)
    ReceiverPreferences.setEnabled(targetContext,false)
    val activity=startActivitySync(Intent(targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    fun descendants(v:View):List<View> = listOf(v)+if(v is ViewGroup)(0 until v.childCount).flatMap {descendants(v.getChildAt(it))} else emptyList()
    var sheet:DuckSheet?=null
    lateinit var value:Spinner;lateinit var field:Spinner;lateinit var badge:TextView;lateinit var button:com.google.android.material.button.MaterialButton
    try {
        runOnMainSync {
            val current=DuckSheet(activity,"Row layout check");sheet=current
            val group=activity.duckGroup(current.body)
            value=activity.receiverSelect(group,"Space limit",listOf("1.5 GB","20 GB"),0)
            field=activity.duckSelect(current.body,"Log retention",listOf("14 days","90 days"),0)
            badge=activity.duckPill("0 items",R.color.duck_attention,R.color.duck_attention_background)
            activity.receiverSetting(group,"Pending files",control=badge)
            button=activity.duckButton("Enable receiving") {}
            activity.receiverSetting(group,"Sender",control=button)
            current.show()
        }
        waitForIdleSync();Thread.sleep(250)
        runOnMainSync {
            for(spinner in listOf(value,field)) {
                val label=spinner.selectedView as TextView
                val ink=Rect();label.paint.getTextBounds(label.text.toString(),0,label.text.length,ink)
                val inkCenter=label.baseline+(ink.top+ink.bottom)/2f
                check(kotlin.math.abs(inkCenter-label.height/2f)<=activity.dp(5)) {"Selected value is off-centre: $inkCenter/${label.height}"}
            }
            val ink=badge.paint.measureText(badge.text.toString())
            check(badge.width<=ink+badge.paddingLeft+badge.paddingRight+activity.dp(3)) {"Badge is stretched into the numeric column"}
            check(button.layoutParams.width==ViewGroup.LayoutParams.WRAP_CONTENT) {"Action stretched into numeric column"}
            val rows=descendants(checkNotNull(sheet).body).filter {it.tag=="duck.setting"}.filterIsInstance<LinearLayout>()
            check(rows.none {row -> (0 until row.childCount).any {row.getChildAt(it) is ImageView}}) {"Decorative settings icon remains"}
        }
        val image=checkNotNull(uiAutomation.takeScreenshot())
        File(targetContext.cacheDir,"receiver-row-contract.png").outputStream().use {image.compress(Bitmap.CompressFormat.PNG,100,it)};image.recycle()
        return "PASS: selected value ink centred; content-width badge/action; settings have no leading decoration"
    } finally {
        runOnMainSync {sheet?.dismiss();activity.finish()};ReceiverPreferences.setEnabled(targetContext,enabled)
    }
}
