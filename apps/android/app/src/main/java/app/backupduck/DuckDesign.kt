package app.backupduck

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.*
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.materialswitch.MaterialSwitch

/** Compatibility text helper: legacy roles resolve to the Material type scale. */
internal fun Context.duckText(text: String, size: Int = 16, secondary: Boolean = false, bold: Boolean = false) = lookText(text,
    when {
        size >= 20 -> com.google.android.material.R.style.TextAppearance_Material3_HeadlineSmall
        size >= 16 && bold -> com.google.android.material.R.style.TextAppearance_Material3_TitleMedium
        size >= 16 -> com.google.android.material.R.style.TextAppearance_Material3_BodyLarge
        size >= 13 -> com.google.android.material.R.style.TextAppearance_Material3_BodyMedium
        else -> com.google.android.material.R.style.TextAppearance_Material3_LabelLarge
    }, secondary)
internal fun Context.duckBackground(color: Int = R.color.duck_surface, radius: Int = 12, border: Boolean = true) = GradientDrawable().apply {
    setColor(getColor(color)); cornerRadius = dp(radius).toFloat()
    if (border) setStroke(dp(1), getColor(R.color.duck_border))
}
internal fun Context.duckRule() = View(this).apply { setBackgroundColor(getColor(R.color.duck_border)); layoutParams = LinearLayout.LayoutParams(-1, dp(1)) }
/** A quiet discovery mark; its owner supplies a localized, non-color accessibility label. */
internal fun Context.duckDiscoveryDot() = View(this).apply {
    layoutParams = LinearLayout.LayoutParams(token(R.dimen.duck_space_x_small), token(R.dimen.duck_space_x_small))
    tag = "duck.discovery"
    background = duckBackground(R.color.duck_brand_accent, 4, false)
    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
}
/** Attention and discovery share geometry and placement; their meaning and role differ. */
internal fun View.setDuckEntryMark(attention: Boolean) {
    tag = if (attention) "duck.attention" else "duck.discovery"
    background = context.duckBackground(if (attention) R.color.duck_state_attention else R.color.duck_brand_accent, 4, false)
}
internal fun Context.duckPill(text: String, color: Int = R.color.duck_text_secondary, backgroundColor: Int = R.color.duck_subtle) = duckText(text, 12, bold = true).apply {
    tag = "duck.pill"; gravity = Gravity.CENTER_VERTICAL
    setTextColor(getColor(color)); setPadding(dp(8), dp(5), dp(8), dp(5))
    background = duckBackground(backgroundColor, 6, false)
}
/** Native button roles; callers keep their existing action ownership. */
internal fun Context.duckButton(text: String, primary: Boolean = false, action: () -> Unit) =
    lookButton(text, if (primary) LookButton.FILLED else LookButton.TEXT, action = action)
internal fun Context.duckLink(text: String, action: () -> Unit) = lookButton(text, LookButton.TEXT, action = action)
internal fun Context.duckSection(parent: LinearLayout, title: String, link: String? = null, action: () -> Unit = {}) {
    val row = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
    row.addView(duckText(title, 16, bold = true), LinearLayout.LayoutParams(0, -2, 1f))
    if (link != null) row.addView(duckLink(link, action), LinearLayout.LayoutParams(-2, dp(48)))
    row.minimumHeight=dp(56);parent.addView(row, LinearLayout.LayoutParams(-1,-2))
}
internal fun Context.duckGroup(parent: LinearLayout, title: String? = null): LinearLayout {
    val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    val container = MaterialCardView(this).apply {
        radius = token(R.dimen.duck_radius_card).toFloat(); cardElevation = 0f; setCardBackgroundColor(getColor(R.color.duck_role_grouped_surface))
        strokeWidth = 0; clipToOutline=true; addView(body)
    }
    parent.addView(container, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(20) })
    if (title != null) body.addView(duckText(title, 13, true, true).apply {
        setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_LabelLarge)
        setPadding(dp(16), dp(12), dp(16), dp(12))
    }, LinearLayout.LayoutParams(-1, -2))
    return body
}
internal fun Context.duckSetting(parent: LinearLayout, title: String, description: String? = null, control: View? = null, leadingIcon:Int?=null, action: (() -> Unit)? = null): TextView {
    if (parent.childCount > 0 && parent.getChildAt(parent.childCount-1).tag == "duck.setting") parent.addView(duckRule())
    val row = LinearLayout(this).apply { tag = "duck.setting"; gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(if (description.isNullOrEmpty()) 56 else 72); setPadding(dp(16), dp(8), dp(16), dp(8)) }
    // Settings are identified by their text; decorative leading icons do not
    // distinguish repeated configuration rows. Media/status icons live elsewhere.
    val words = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    val heading = duckText(title, 16, bold = true)
    words.addView(heading)
    if (!description.isNullOrEmpty()) words.addView(duckText(description, 13, true).apply { setPadding(0, dp(5), 0, 0) })
    row.addView(words, LinearLayout.LayoutParams(0, -2, 1f))
    val accessory = control ?: if (action != null) ImageView(this).apply {setImageResource(R.drawable.ic_chevron);imageTintList=android.content.res.ColorStateList.valueOf(getColor(R.color.duck_action));layoutParams=LinearLayout.LayoutParams(dp(22),dp(22))}
        else View(this).apply {visibility=View.GONE}
    row.addView(accessory, LinearLayout.LayoutParams(if(control==null) dp(22) else -2, if(control==null) dp(22) else -2).apply { marginStart = dp(12) })
    if (action != null) {
        val out = android.util.TypedValue(); theme.resolveAttribute(android.R.attr.selectableItemBackground, out, true)
        row.foreground = getDrawable(out.resourceId); row.isFocusable = true; row.setOnClickListener { action() }
    }
    parent.addView(row, LinearLayout.LayoutParams(-1, -2))
    return heading
}
internal fun Context.duckSwitch(on: Boolean, changed: (Boolean) -> Unit) = MaterialSwitch(this).apply {
    isChecked = on; minimumHeight = dp(48); minimumWidth = dp(48)
    setOnCheckedChangeListener { _, value -> changed(value) }
}
internal fun Context.duckNote(parent: LinearLayout, text: String, icon: Int = R.drawable.ic_info) {
    parent.addView(duckMessageRow(text,icon=icon,titleColor=R.color.duck_text_secondary,bold=false).apply {setPadding(0,dp(12),0,dp(16))})
}
internal fun Context.duckNotice(parent:LinearLayout,title:String,description:String?=null):View {
    val row=duckMessageRow(title,description).apply {setPadding(dp(12),dp(12),dp(12),dp(12));background=duckBackground(R.color.duck_subtle,12,false)}
    parent.addView(row,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16);bottomMargin=dp(16)})
    return row
}
/** Align the optical icon centre to the first rendered line, including fallback CJK fonts.
 * A fixed top margin aligns neither small Latin labels nor large/multiline Chinese labels. */
internal fun Context.duckMessageRow(title:String,description:String?=null,icon:Int=R.drawable.ic_info,
    iconColor:Int=R.color.duck_text_secondary,titleColor:Int=R.color.duck_text,bold:Boolean=true):LinearLayout {
    val symbol=ImageView(this).apply {setImageResource(icon);imageTintList=android.content.res.ColorStateList.valueOf(getColor(iconColor));importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO}
    val heading=duckParagraph(title).apply {setTextColor(getColor(titleColor));if(bold) typeface=Typeface.create("sans-serif",Typeface.BOLD)}
    val words=LinearLayout(this).apply {
        orientation=LinearLayout.VERTICAL;addView(heading)
        if(description!=null) addView(duckParagraph(description),LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(8)})
    }
    return object:LinearLayout(this) {
        private val ink=android.graphics.Rect()
        override fun onLayout(changed:Boolean,left:Int,top:Int,right:Int,bottom:Int) {
            super.onLayout(changed,left,top,right,bottom)
            val lines=heading.layout?:return
            if(lines.lineCount==0)return
            val text=heading.text.subSequence(lines.getLineStart(0),lines.getLineEnd(0)).toString().trimEnd()
            heading.paint.getTextBounds(text,0,text.length,ink)
            val centre=words.top+heading.top+heading.totalPaddingTop+lines.getLineBaseline(0)+(ink.top+ink.bottom)/2f
            symbol.translationY=centre-(symbol.top+symbol.height/2f)
        }
    }.apply {
        tag="duck.message";orientation=LinearLayout.HORIZONTAL;gravity=Gravity.TOP
        addView(symbol,LinearLayout.LayoutParams(dp(18),dp(18)).apply {marginEnd=dp(8)})
        addView(words,LinearLayout.LayoutParams(0,-2,1f))
    }
}
internal class DuckReadings(private val context: Context, labels: List<String>) {
    val view = LinearLayout(context).apply {
        gravity = Gravity.TOP; setPadding(context.dp(8), context.dp(16), context.dp(8), context.dp(16))
        background = context.duckBackground()
    }
    private val captions = mutableListOf<TextView>()
    private val values = labels.mapIndexed { index, label ->
        if (index > 0) view.addView(View(context).apply { setBackgroundColor(context.getColor(R.color.duck_border)) }, LinearLayout.LayoutParams(context.dp(1), context.dp(42)))
        val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL }
        val value = context.duckText("—", 16, bold = true).apply { fontFeatureSettings = "tnum";gravity=Gravity.CENTER }
        column.addView(value); val caption=context.duckText(label,11,true).apply {gravity=Gravity.CENTER;setPadding(0,context.dp(7),0,0)}; captions+=caption;column.addView(caption)
        view.addView(column, LinearLayout.LayoutParams(0, -2, 1f)); value
    }
    fun caption(index:Int,text:String) {if(captions[index].text.toString()!=text)captions[index].text=text}
    fun render(vararg readings: String) { values.forEachIndexed { index, text -> if(text.text.toString()!=readings[index])text.text = readings[index] } }
}
internal class DuckSheet(context: Context, title: String) : BottomSheetDialog(context) {
    init { context.trackNotificationWindow(this) }
    val body = LinearLayout(this.context).apply {
        orientation = LinearLayout.VERTICAL
        val padding = context.token(R.dimen.duck_space_medium)
        setPadding(padding, 0, padding, padding)
    }
    // Compatibility action region is ordinary scrolling content, never sheet chrome.
    val footer = LinearLayout(this.context).apply { orientation = LinearLayout.VERTICAL; visibility = View.GONE }
    init {
        val content = LinearLayout(this.context).apply { orientation = LinearLayout.VERTICAL }
        content.addView(com.google.android.material.bottomsheet.BottomSheetDragHandleView(this.context), LinearLayout.LayoutParams(-1, -2))
        val heading = this.context.lookText(title, com.google.android.material.R.style.TextAppearance_Material3_HeadlineSmall).apply {
            isAccessibilityHeading = true
        }
        val scrollBody = LinearLayout(this.context).apply {
            orientation = LinearLayout.VERTICAL
            addView(heading, LinearLayout.LayoutParams(-1, -2).apply {
                val padding = context.token(R.dimen.duck_space_medium)
                setMargins(padding, 0, padding, padding)
            })
            addView(body); addView(footer)
        }
        content.addView(androidx.core.widget.NestedScrollView(this.context).apply { addView(scrollBody) }, LinearLayout.LayoutParams(-1, -2))
        setContentView(content)
        window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    }
    fun addAction(label: String, primary: Boolean = false, action: () -> Unit): MaterialButton {
        footer.visibility = View.VISIBLE
        return context.lookButton(label, LookButton.TEXT, action = action).also {
            footer.addView(it, LinearLayout.LayoutParams(-2, -2).apply { gravity = Gravity.END })
        }
    }
    fun dismissImmediately() = dismiss()
}

internal class DuckProgress(context:Context):ProgressBar(context,null,android.R.attr.progressBarStyleHorizontal) {
    private var motion:ValueAnimator?=null
    init {max=1000}
    fun render(value:Int) {
        if(value==progress) return
        motion?.cancel()
        if(!ValueAnimator.areAnimatorsEnabled()||!isShown) {progress=value;return}
        motion=ValueAnimator.ofInt(progress,value).apply {
            duration=320;interpolator=android.view.animation.PathInterpolator(.2f,.8f,.2f,1f)
            addUpdateListener {progress=it.animatedValue as Int};start()
        }
    }
    override fun onDetachedFromWindow() {motion?.cancel();super.onDetachedFromWindow()}
}

internal fun Context.duckDefinition(parent:LinearLayout,label:String,value:String):TextView {
    val row=LinearLayout(this).apply {gravity=Gravity.TOP;setPadding(0,dp(8),0,dp(8))}
    row.addView(duckText(label,13,true),LinearLayout.LayoutParams(dp(88),-2))
    val content=duckText(value,13)
    row.addView(content,LinearLayout.LayoutParams(0,-2,1f));parent.addView(row);return content
}
internal fun Context.duckTimeline(parent:LinearLayout,title:String,note:String,confirmed:Boolean,color:Int=R.color.duck_saved,last:Boolean=false,glyph:Int?=null) {
    val row=LinearLayout(this).apply {minimumHeight=dp(60);gravity=Gravity.TOP}
    if (glyph != null) row.addView(ImageView(this).apply {
        setImageResource(glyph)
        imageTintList = ColorStateList.valueOf(getColor(if (confirmed) color else R.color.duck_text_secondary))
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        setPadding(0, 0, token(R.dimen.duck_space_x_small), 0)
    }, LinearLayout.LayoutParams(dp(24), dp(24)))
    else row.addView(object:View(this) {
        private val paint=android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
        override fun onDraw(canvas:android.graphics.Canvas) {
            if(!last) {paint.color=getColor(R.color.duck_border);paint.strokeWidth=dp(1).toFloat();canvas.drawLine(dp(5).toFloat(),dp(16).toFloat(),dp(5).toFloat(),height.toFloat(),paint)}
            paint.color=getColor(if(confirmed) color else R.color.duck_text_secondary);paint.style=if(confirmed) android.graphics.Paint.Style.FILL else android.graphics.Paint.Style.STROKE;paint.strokeWidth=dp(1).toFloat()
            canvas.drawCircle(dp(5).toFloat(),dp(8).toFloat(),dp(4).toFloat(),paint);paint.style=android.graphics.Paint.Style.FILL
        }
    },LinearLayout.LayoutParams(dp(24),-1))
    val words=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setPadding(0,0,0,dp(16))}
    words.addView(duckText(title,15,bold=true));words.addView(duckText(note,13,true).apply {setPadding(0,dp(5),0,0)})
    row.addView(words,LinearLayout.LayoutParams(0,-2,1f));parent.addView(row)
}

/** A single, measured sibling gap. Do not add two CSS margins together in a native column. */
internal fun View.duckMargins(top:Int=0,bottom:Int=0):View = apply {
    layoutParams=(layoutParams as LinearLayout.LayoutParams).apply {topMargin=context.dp(top);bottomMargin=context.dp(bottom)}
}
internal fun Context.duckParagraph(text:String):TextView=lookText(text, com.google.android.material.R.style.TextAppearance_Material3_BodyMedium, secondary = true)

/** Full native secondary page: toolbar, scrollable body and optional fixed action footer. */
internal class DuckPage(activity: BackupDuckActivity, title: String, route: String) : PageDestination(activity, route, title) {
    init {
        body.setPadding(activity.dp(16), activity.dp(20), activity.dp(16), activity.dp(24))
        footer.setPadding(activity.dp(16), activity.dp(12), activity.dp(16), activity.dp(20))
    }
    fun addAction(label: String, primary: Boolean = false, action: () -> Unit): MaterialButton {
        footer.visibility = View.VISIBLE
        return activity.duckButton(label, primary, action).also {
            footer.addView(it, LinearLayout.LayoutParams(-1, -2).apply { topMargin = activity.dp(8) })
        }
    }
}

internal class DuckField(context:Context,label:String,value:String="",numeric:Boolean=false,maxLength:Int?=null) {
    val view=LinearLayout(context).apply {orientation=LinearLayout.VERTICAL}
    val box=com.google.android.material.textfield.TextInputLayout(context,null,com.google.android.material.R.attr.textInputOutlinedStyle).apply {
        hint = label
    }
    val input=com.google.android.material.textfield.TextInputEditText(box.context).apply {
        setText(value);isSingleLine=true
        setPadding(context.dp(12),context.dp(12),context.dp(12),context.dp(12));minimumHeight=context.dp(56)
        inputType=if(numeric) android.text.InputType.TYPE_CLASS_NUMBER else android.text.InputType.TYPE_CLASS_TEXT
        if(maxLength!=null) filters=arrayOf(android.text.InputFilter.LengthFilter(maxLength))
    }
    init {
        box.addView(input,LinearLayout.LayoutParams(-1,-2));view.addView(box,LinearLayout.LayoutParams(-1,-2))
    }
}
internal fun Context.duckSelect(parent:LinearLayout,title:String,values:List<String>,selected:Int):Spinner {
    parent.addView(duckParagraph(title),LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16);bottomMargin=dp(8)})
    val container=FrameLayout(this).apply {background=duckBackground(radius=8)}
    val spinner=Spinner(this,Spinner.MODE_DROPDOWN).apply {
        contentDescription=title
        adapter=object:ArrayAdapter<String>(this@duckSelect,android.R.layout.simple_spinner_dropdown_item,values) {
            override fun getView(position:Int,convert:View?,host:android.view.ViewGroup):View = (super.getView(position,convert,host) as TextView).apply {
                gravity=Gravity.START or Gravity.CENTER_VERTICAL;includeFontPadding=false;minimumHeight=dp(56)
                setPadding(0,0,0,0)
            }
        }
        setSelection(selected);background=null;setPadding(dp(12),0,dp(40),0)
    }
    container.addView(spinner,FrameLayout.LayoutParams(-1,-1))
    container.addView(ImageView(this).apply {setImageResource(R.drawable.ic_chevron);rotation=90f;imageTintList=android.content.res.ColorStateList.valueOf(getColor(R.color.duck_text_secondary));importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO},FrameLayout.LayoutParams(dp(20),dp(20),Gravity.END or Gravity.CENTER_VERTICAL).apply {marginEnd=dp(12)})
    parent.addView(container,LinearLayout.LayoutParams(-1,dp(56)))
    return spinner
}
internal fun Context.duckWarning(parent:LinearLayout,title:String,description:String?=null):View = duckMessageRow(title,description,R.drawable.ic_alert,R.color.duck_attention).apply {
    background=duckBackground(R.color.duck_attention_background,12,false);setPadding(dp(12),dp(12),dp(12),dp(12))
    parent.addView(this,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16);bottomMargin=dp(16)})
}
internal fun Context.duckProblem(parent:LinearLayout,message:String):View=duckFailure(parent,message).apply {visibility=View.VISIBLE}
