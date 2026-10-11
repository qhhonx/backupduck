package app.backupduck

import android.content.Context
import android.view.View
import android.view.Gravity
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.snackbar.Snackbar

/** v1.2: brief acknowledgements use a snackbar; actionable failures stay in their source. */
internal fun AppCompatActivity.duckAcknowledge(message:String,host:View=findViewById(android.R.id.content)):Snackbar {
    return Snackbar.make(host,message,Snackbar.LENGTH_LONG).apply {
        setBackgroundTint(getColor(R.color.duck_text));setTextColor(getColor(R.color.duck_surface))
        host.rootView.findViewById<View>(R.id.main_navigation)?.takeIf {it.isShown}?.let {anchorView=it}
        show()
    }
}
internal fun Context.duckError(message:String):View = duckMessageRow(getString(R.string.duck_operation_failed),message,
    R.drawable.ic_alert,R.color.duck_failure,R.color.duck_failure).apply {
    visibility=View.GONE
    background=duckBackground(R.color.duck_failure_background,12,false)
    setPadding(dp(12),dp(12),dp(12),dp(12));accessibilityLiveRegion=View.ACCESSIBILITY_LIVE_REGION_POLITE
}
internal fun Context.duckFailure(parent:LinearLayout,message:String):View = duckError(message).also {
    parent.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(12);bottomMargin=dp(12)})
}
internal class DuckConfirmation(private val activity:AppCompatActivity,title:Int,message:Int,positive:Int,danger:Boolean=false,
    notice:Int?=null,private val busyNotice:Int?=null,messageText:String?=null,confirmed:(DuckConfirmation)->Unit):androidx.appcompat.app.AppCompatDialog(activity) {
    val failure=activity.duckError(activity.getString(R.string.duck_access_change_failed))
    val confirm=activity.duckButton(activity.getString(positive),true) {confirmed(this)}
    private val cancel=activity.duckButton(activity.getString(R.string.device_cancel)) {dismiss()}
    private val idleLabel=activity.getString(positive)
    private var information:View?=null
    private var working:View?=null
    private val retry=activity.duckButton(activity.getString(R.string.duck_retry)) {confirmed(this)}
    init {
        val panel=object:LinearLayout(activity) {
            override fun onMeasure(width:Int,height:Int) {
                val maximum=(activity.resources.displayMetrics.heightPixels*.88f).toInt()
                super.onMeasure(width,View.MeasureSpec.makeMeasureSpec(maximum,View.MeasureSpec.AT_MOST))
            }
        }.apply {orientation=LinearLayout.VERTICAL}
        panel.addView(activity.duckText(activity.getString(title),20,bold=true).apply {
            minimumHeight=(20*resources.displayMetrics.scaledDensity*1.35f).toInt()
        },LinearLayout.LayoutParams(-1,-2).apply {setMargins(activity.dp(20),activity.dp(20),activity.dp(20),0)})
        val words=LinearLayout(activity).apply {orientation=LinearLayout.VERTICAL;setPadding(activity.dp(20),activity.dp(12),activity.dp(20),activity.dp(20))}
        words.addView(activity.duckParagraph(messageText ?: activity.getString(message)),LinearLayout.LayoutParams(-1,-2).apply {topMargin=activity.dp(8);bottomMargin=activity.dp(16)})
        information=notice?.let {activity.duckNotice(words,activity.getString(it)).duckMargins(bottom=16)}
        working=busyNotice?.let {activity.duckNotice(words,activity.getString(it)).duckMargins(bottom=16).apply {visibility=View.GONE}}
        words.addView(failure,LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=activity.dp(16)})
        words.addView(retry,LinearLayout.LayoutParams(-2,-2).apply {bottomMargin=activity.dp(16)});retry.visibility=View.GONE
        panel.addView(androidx.core.widget.NestedScrollView(activity).apply {addView(words)},LinearLayout.LayoutParams(-1,-2,1f))
        panel.addView(activity.duckRule())
        val stacked=activity.resources.configuration.fontScale>1.3f
        val actions=LinearLayout(activity).apply {
            orientation=if(stacked) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
            isBaselineAligned=false;gravity=Gravity.CENTER_VERTICAL
            setPadding(activity.dp(20),activity.dp(12),activity.dp(20),activity.dp(20))
        }
        actions.addView(cancel,if(stacked) LinearLayout.LayoutParams(-1,-2) else LinearLayout.LayoutParams(0,-2,1f))
        actions.addView(confirm,(if(stacked) LinearLayout.LayoutParams(-1,-2) else LinearLayout.LayoutParams(0,-2,1f)).apply {if(stacked) topMargin=activity.dp(8) else marginStart=activity.dp(8)})
        panel.addView(actions)
        if(danger) confirm.backgroundTintList=android.content.res.ColorStateList.valueOf(activity.getColor(R.color.duck_failure))
        setContentView(panel)
        window?.setBackgroundDrawable(activity.duckBackground(R.color.duck_surface,20,false))
        window?.setDimAmount(.24f)
    }
    fun busy(value:Boolean) {
        confirm.isEnabled=!value;cancel.isEnabled=!value;setCancelable(!value)
        failure.visibility=View.GONE;retry.visibility=View.GONE
        information?.visibility=if(value) View.GONE else View.VISIBLE
        working?.visibility=if(value) View.VISIBLE else View.GONE
        confirm.text=if(value&&busyNotice!=null) activity.getString(busyNotice) else idleLabel
    }
    fun showFailure(message:Int=R.string.duck_access_change_failed) {
        val words=(failure as LinearLayout).getChildAt(1) as LinearLayout
        (words.getChildAt(1) as android.widget.TextView).setText(message)
        information?.visibility=View.GONE;working?.visibility=View.GONE;failure.visibility=View.VISIBLE;retry.visibility=View.VISIBLE
    }
    override fun show() {
        super.show()
        window?.setLayout(activity.resources.displayMetrics.widthPixels-activity.dp(48),android.view.ViewGroup.LayoutParams.WRAP_CONTENT)
    }
}
internal fun AppCompatActivity.duckConfirm(title:Int,message:Int,positive:Int,danger:Boolean=false,notice:Int?=null,busyNotice:Int?=null,messageText:String?=null,
    confirmed:(DuckConfirmation)->Unit):DuckConfirmation = DuckConfirmation(this,title,message,positive,danger,notice,busyNotice,messageText,confirmed).also {it.show()}
