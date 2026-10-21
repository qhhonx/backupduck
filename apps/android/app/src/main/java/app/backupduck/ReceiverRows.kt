package app.backupduck
import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView

internal fun Context.receiverVersionLabel():String {
    val info=packageManager.getPackageInfo(packageName,0)
    val version=(info.versionName ?: "—").substringBefore("-ui").removeSuffix("-dev")
    return "$version (${info.longVersionCode})"
}

/** Receiver-only value-row adaptation; Sender/shared contracts are left unchanged. */
internal fun Context.receiverSetting(parent:LinearLayout,title:String,description:String?=null,control:View?=null,leadingIcon:Int?=null,action:(()->Unit)?=null):TextView {
 val accessory=control ?: if(action==null) View(this).apply {visibility=View.GONE} else null
 val heading=duckSetting(parent,title,description,accessory,null,action)
 val valueColumn=control is android.widget.Spinner || (control is TextView&&control !is android.widget.Button&&control !is android.widget.CompoundButton&&control.tag!="duck.pill"&&control.tag!="duck.version"&&control.text.isNotEmpty())
 val stackedAction=resources.configuration.fontScale>1.3f && control!=null && (control.tag=="duck.pill"||control.tag=="duck.version"||control is android.widget.Button&&control !is android.widget.CompoundButton)
 if(control!=null&&(valueColumn||stackedAction)) {
  val words=heading.parent as LinearLayout;val row=words.parent as LinearLayout
  val available=(resources.displayMetrics.widthPixels-dp(64)).coerceAtLeast(dp(160))
  if(resources.configuration.fontScale>1.3f) {
   val leading=if(row.indexOfChild(words)>0)row.getChildAt(0) else null
   row.removeView(words);leading?.let {row.removeView(it)}
   val labelRow=LinearLayout(this).apply {orientation=LinearLayout.HORIZONTAL;gravity=Gravity.TOP;isBaselineAligned=false}
   leading?.let {labelRow.addView(it,LinearLayout.LayoutParams(dp(22),dp(22)).apply {marginEnd=dp(12)})}
   labelRow.addView(words,LinearLayout.LayoutParams(0,-2,1f));row.addView(labelRow,0,LinearLayout.LayoutParams(-1,-2))
   row.orientation=LinearLayout.VERTICAL;row.gravity=Gravity.TOP;row.isBaselineAligned=false
   control.layoutParams=LinearLayout.LayoutParams(if(valueColumn)-1 else -2,-2).apply {topMargin=dp(8);gravity=Gravity.END}
   if(control is TextView) {if(control !is android.widget.Button)control.gravity=Gravity.END or Gravity.CENTER_VERTICAL;control.maxWidth=available}
  } else {
   control.layoutParams=LinearLayout.LayoutParams(dp(112),-2).apply {marginStart=dp(12)}
   if(control is TextView) {control.gravity=Gravity.END or Gravity.CENTER_VERTICAL;control.maxWidth=dp(112)}
  }
 }
 return heading
}

/** A real native picker with a stable right-hand value column and full-row target. */
internal fun Context.receiverSelect(parent:LinearLayout,title:String,values:List<String>,selected:Int):android.widget.Spinner {
 val spinner=android.widget.Spinner(this,android.widget.Spinner.MODE_DROPDOWN).apply {
  contentDescription=title
  gravity=Gravity.END or Gravity.CENTER_VERTICAL
  adapter=object:android.widget.ArrayAdapter<String>(this@receiverSelect,android.R.layout.simple_spinner_dropdown_item,values) {
   override fun getView(position:Int,convert:View?,host:android.view.ViewGroup):View = (super.getView(position,convert,host) as TextView).apply {setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyLarge);includeFontPadding=false;gravity=Gravity.END or Gravity.CENTER_VERTICAL;minimumHeight=dp(48);setPadding(0,0,dp(4),0)}
  }
  setSelection(selected);minimumHeight=dp(48)
 }
 val heading=receiverSetting(parent,title,control=spinner)
 val row=generateSequence(heading.parent as? View) {it.parent as? View}.first {it.tag=="duck.setting"} as LinearLayout
 spinner.layoutParams=LinearLayout.LayoutParams(if(resources.configuration.fontScale>1.3f)-1 else dp(112),-2).apply {if(resources.configuration.fontScale>1.3f)topMargin=dp(8) else marginStart=dp(12)}
 row.setOnClickListener {if(spinner.isEnabled)spinner.performClick()};row.isClickable=true
 return spinner
}
