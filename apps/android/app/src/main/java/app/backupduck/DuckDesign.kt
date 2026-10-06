package app.backupduck

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.*
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.materialswitch.MaterialSwitch

/** Native equivalents of the approved prototype's rows, readings, groups and sheets. */
internal fun Context.duckText(text: String, size: Int = 16, secondary: Boolean = false, bold: Boolean = false) = TextView(this).apply {
    this.text = text; textSize = size.toFloat(); includeFontPadding = false
    setTextColor(getColor(if (secondary) R.color.duck_text_secondary else R.color.duck_text))
    if (bold) typeface = Typeface.create("sans-serif", Typeface.BOLD)
}
internal fun Context.duckBackground(color: Int = R.color.duck_surface, radius: Int = 12, border: Boolean = true) = GradientDrawable().apply {
    setColor(getColor(color)); cornerRadius = dp(radius).toFloat()
    if (border) setStroke(dp(1), getColor(R.color.duck_border))
}
internal fun Context.duckRule() = View(this).apply { setBackgroundColor(getColor(R.color.duck_border)); layoutParams = LinearLayout.LayoutParams(-1, dp(1)) }
internal fun Context.duckPill(text: String, color: Int = R.color.duck_text_secondary, backgroundColor: Int = R.color.duck_subtle) = duckText(text, 12, bold = true).apply {
    setTextColor(getColor(color)); setPadding(dp(8), dp(5), dp(8), dp(5))
    background = duckBackground(backgroundColor, 6, false)
}
internal fun Context.duckButton(text: String, primary: Boolean = false, action: () -> Unit) = MaterialButton(this, null,
    if (primary) com.google.android.material.R.attr.materialButtonStyle else com.google.android.material.R.attr.materialButtonOutlinedStyle).apply {
    this.text = text; isAllCaps = false; textSize = 14f; cornerRadius = dp(24); minimumHeight = dp(48)
    elevation=0f;stateListAnimator=null
    backgroundTintList=android.content.res.ColorStateList.valueOf(getColor(if(primary) R.color.duck_action else R.color.duck_surface))
    setTextColor(getColor(if(primary) if(resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK == android.content.res.Configuration.UI_MODE_NIGHT_YES) R.color.duck_canvas else R.color.duck_surface else R.color.duck_text))
    strokeWidth=if(primary) 0 else dp(1);strokeColor=android.content.res.ColorStateList.valueOf(getColor(R.color.duck_border))
    insetTop = 0; insetBottom = 0; setOnClickListener { action() }
}
internal fun Context.duckLink(text: String, action: () -> Unit) = MaterialButton(this, null, com.google.android.material.R.attr.borderlessButtonStyle).apply {
    this.text = text; isAllCaps = false; textSize = 13f; minimumHeight = dp(48)
    insetTop = 0; insetBottom = 0; setPadding(0, 0, 0, 0); setOnClickListener { action() }
}
internal fun Context.duckSection(parent: LinearLayout, title: String, link: String? = null, action: () -> Unit = {}) {
    val row = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
    row.addView(duckText(title, 16, bold = true), LinearLayout.LayoutParams(0, -2, 1f))
    if (link != null) row.addView(duckLink(link, action), LinearLayout.LayoutParams(-2, dp(48)))
    row.minimumHeight=dp(56);parent.addView(row, LinearLayout.LayoutParams(-1,-2))
}
internal fun Context.duckGroup(parent: LinearLayout, title: String? = null): LinearLayout {
    val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    val container = MaterialCardView(this).apply {
        radius = dp(12).toFloat(); cardElevation = 0f; setCardBackgroundColor(getColor(R.color.duck_surface))
        strokeWidth = dp(1); strokeColor = getColor(R.color.duck_border); clipToOutline=true; addView(body)
    }
    parent.addView(container, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(20) })
    if (title != null) body.addView(duckText(title, 13, true, true).apply {
        setPadding(dp(14), dp(10), dp(14), dp(10)); setBackgroundColor(getColor(R.color.duck_subtle))
    }, LinearLayout.LayoutParams(-1, -2))
    return body
}
internal fun Context.duckSetting(parent: LinearLayout, title: String, description: String? = null, control: View? = null, leadingIcon:Int?=null, action: (() -> Unit)? = null): TextView {
    if (parent.childCount > 0 && parent.getChildAt(parent.childCount-1).tag == "duck.setting") parent.addView(duckRule())
    val row = LinearLayout(this).apply { tag = "duck.setting"; gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(64); setPadding(dp(14), dp(8), dp(14), dp(8)) }
    if(leadingIcon!=null) row.addView(ImageView(this).apply {setImageResource(leadingIcon);imageTintList=android.content.res.ColorStateList.valueOf(getColor(R.color.duck_text_secondary))},LinearLayout.LayoutParams(dp(22),dp(22)).apply {marginEnd=dp(12)})
    val words = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    val heading = duckText(title, 16, bold = true)
    words.addView(heading)
    if (!description.isNullOrEmpty()) words.addView(duckText(description, 13, true).apply { setPadding(0, dp(5), 0, 0) })
    row.addView(words, LinearLayout.LayoutParams(0, -2, 1f))
    val accessory = control ?: ImageView(this).apply {setImageResource(R.drawable.ic_chevron);imageTintList=android.content.res.ColorStateList.valueOf(getColor(R.color.duck_action));layoutParams=LinearLayout.LayoutParams(dp(22),dp(22))}
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
        if(description!=null) addView(duckParagraph(description).apply {if(iconColor==R.color.duck_failure)setTextColor(getColor(iconColor))},LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(8)})
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
        gravity = Gravity.CENTER_VERTICAL; setPadding(context.dp(8), context.dp(16), context.dp(8), context.dp(16))
        background = context.duckBackground()
    }
    private val captions = mutableListOf<TextView>()
    private val values = labels.mapIndexed { index, label ->
        if (index > 0) view.addView(View(context).apply { setBackgroundColor(context.getColor(R.color.duck_border)) }, LinearLayout.LayoutParams(context.dp(1), context.dp(42)))
        val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER }
        val value = context.duckText("—", 16, bold = true).apply { fontFeatureSettings = "tnum";gravity=Gravity.CENTER }
        column.addView(value); val caption=context.duckText(label,11,true).apply {gravity=Gravity.CENTER;setPadding(0,context.dp(7),0,0)}; captions+=caption;column.addView(caption)
        view.addView(column, LinearLayout.LayoutParams(0, -2, 1f)); value
    }
    fun caption(index:Int,text:String) {captions[index].text=text}
    fun render(vararg readings: String) { values.forEachIndexed { index, text -> text.text = readings[index] } }
}
internal class DuckSheet(context: Context, title: String) : BottomSheetDialog(context,R.style.DuckBottomSheetDialog) {
    private var canClose=true
    override fun setCancelable(cancelable:Boolean) {canClose=cancelable;super.setCancelable(cancelable)}
    val body = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; setPadding(context.dp(20), context.dp(8), context.dp(20), context.dp(20)) }
    val footer = LinearLayout(context).apply {
        orientation=if(context.resources.configuration.fontScale>1.3f)LinearLayout.VERTICAL else LinearLayout.HORIZONTAL; visibility=View.GONE
        isBaselineAligned=false;gravity=Gravity.CENTER_VERTICAL
        setPadding(context.dp(20),context.dp(12),context.dp(20),context.dp(20))
    }
    init {
        val content=object:LinearLayout(context) {
            override fun onMeasure(width:Int,height:Int) {
                val available=View.MeasureSpec.getSize(height)
                val limit=(context.resources.displayMetrics.heightPixels*.88f).toInt()
                super.onMeasure(width,View.MeasureSpec.makeMeasureSpec(if(available>0) minOf(limit,available) else limit,View.MeasureSpec.AT_MOST))
            }
        }.apply {orientation=LinearLayout.VERTICAL}
        content.addView(View(context).apply { background = context.duckBackground(R.color.duck_border, 2, false) }, LinearLayout.LayoutParams(context.dp(36), context.dp(4)).apply { gravity = Gravity.CENTER; topMargin=context.dp(12);bottomMargin=context.dp(16) })
        val header = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL;setPadding(context.dp(20),0,context.dp(8),context.dp(4)) }
        header.addView(context.duckText(title, 20, bold = true), LinearLayout.LayoutParams(0, -2, 1f))
        header.addView(ImageButton(context).apply {
            contentDescription=context.getString(R.string.receiver_close);setImageResource(R.drawable.ic_close)
            imageTintList=android.content.res.ColorStateList.valueOf(context.getColor(R.color.duck_text_secondary))
            background=context.duckBackground(R.color.duck_surface,24,false);setPadding(context.dp(13),context.dp(13),context.dp(13),context.dp(13));setOnClickListener {if(canClose)dismiss()}
        },LinearLayout.LayoutParams(context.dp(48),context.dp(48)))
        content.addView(header)
        content.addView(androidx.core.widget.NestedScrollView(context).apply {addView(body);isFillViewport=false},LinearLayout.LayoutParams(-1,-2,1f))
        val footerContainer=LinearLayout(context).apply {orientation=LinearLayout.VERTICAL;visibility=View.GONE}
        footerContainer.addView(context.duckRule());footerContainer.addView(footer)
        footer.tag=footerContainer
        content.addView(footerContainer,LinearLayout.LayoutParams(-1,-2))
        setContentView(content,android.view.ViewGroup.LayoutParams(-1,-2))
        window?.setDimAmount(.24f)
        window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    }
    fun addAction(label:String,primary:Boolean=false,action:()->Unit):MaterialButton {
        footer.visibility=View.VISIBLE;(footer.tag as View).visibility=View.VISIBLE
        return context.duckButton(label,primary,action).also {
            val stacked=footer.orientation==LinearLayout.VERTICAL
            footer.addView(it,(if(stacked)LinearLayout.LayoutParams(-1,-2) else LinearLayout.LayoutParams(0,-2,1f)).apply {
                if(footer.childCount>0) {if(stacked)topMargin=context.dp(8) else marginStart=context.dp(8)}
            })
        }
    }
    private var dimMotion:ValueAnimator?=null
    override fun show() {
        super.show(); window?.setWindowAnimations(0)
        dimMotion?.cancel()
        if(ValueAnimator.areAnimatorsEnabled()) {
            window?.setDimAmount(0f)
            dimMotion=ValueAnimator.ofFloat(0f,.24f).apply {duration=140;addUpdateListener {window?.setDimAmount(it.animatedValue as Float)};start()}
        } else window?.setDimAmount(.24f)
        val sheet = findViewById<android.widget.FrameLayout>(com.google.android.material.R.id.design_bottom_sheet)
        sheet?.backgroundTintList=null
        sheet?.background = context.duckBackground(R.color.duck_surface, 20, false)
        behavior.maxHeight = (context.resources.displayMetrics.heightPixels * .88f).toInt()
        behavior.isFitToContents = true
        behavior.peekHeight = com.google.android.material.bottomsheet.BottomSheetBehavior.PEEK_HEIGHT_AUTO
        behavior.state = com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_EXPANDED
        if (ValueAnimator.areAnimatorsEnabled()) { body.alpha = 0f; body.translationY = context.dp(12).toFloat(); body.animate().alpha(1f).translationY(0f).setDuration(220).setInterpolator(android.view.animation.PathInterpolator(.2f,.8f,.2f,1f)).start() }
    }
    override fun dismiss() {
        dimMotion?.cancel()
        if (isShowing && ValueAnimator.areAnimatorsEnabled()) {
            dimMotion=ValueAnimator.ofFloat(.24f,0f).apply {duration=160;addUpdateListener {window?.setDimAmount(it.animatedValue as Float)};start()}
            body.animate().alpha(0f).translationY(context.dp(8).toFloat()).setDuration(160).withEndAction { super.dismiss() }.start()
        } else super.dismiss()
    }
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
internal fun Context.duckTimeline(parent:LinearLayout,title:String,note:String,confirmed:Boolean,color:Int=R.color.duck_saved,last:Boolean=false) {
    val row=LinearLayout(this).apply {minimumHeight=dp(60);gravity=Gravity.TOP}
    row.addView(object:View(this) {
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
internal fun Context.duckParagraph(text:String):TextView=duckText(text,13,true).apply {
    setLineHeight((13*resources.displayMetrics.scaledDensity*1.5f).toInt())
    minimumHeight=(13*resources.displayMetrics.scaledDensity*1.5f).toInt()
}

/** Full native secondary page: toolbar, scrollable body and optional fixed action footer. */
internal class DuckPage(val activity:androidx.appcompat.app.AppCompatActivity,title:String):androidx.appcompat.app.AppCompatDialog(activity,R.style.DuckFullPage) {
    val body=LinearLayout(activity).apply {orientation=LinearLayout.VERTICAL;setPadding(activity.dp(16),activity.dp(20),activity.dp(16),activity.dp(24))}
    private val footer=LinearLayout(activity).apply {orientation=LinearLayout.VERTICAL;setPadding(activity.dp(16),activity.dp(12),activity.dp(16),activity.dp(20));visibility=View.GONE}
    init {
        val root=LinearLayout(activity).apply {orientation=LinearLayout.VERTICAL;setBackgroundColor(activity.getColor(R.color.duck_surface))}
        val toolbar=com.google.android.material.appbar.MaterialToolbar(activity).apply {
            this.title=title;setTitleTextAppearance(activity,R.style.DuckToolbarTitle)
            setNavigationIcon(R.drawable.ic_back);setNavigationIconTint(activity.getColor(R.color.duck_text_secondary))
            setNavigationContentDescription(R.string.nav_back);setNavigationOnClickListener {dismiss()}
        }
        root.addView(toolbar,LinearLayout.LayoutParams(-1,activity.dp(56)));root.addView(activity.duckRule())
        root.addView(androidx.core.widget.NestedScrollView(activity).apply {addView(body)},LinearLayout.LayoutParams(-1,0,1f))
        root.addView(footer,LinearLayout.LayoutParams(-1,-2));setContentView(root)
        window?.setBackgroundDrawableResource(R.color.duck_surface)
        window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    }
    fun addAction(label:String,primary:Boolean=false,action:()->Unit):MaterialButton {
        if(footer.childCount==0) footer.addView(activity.duckRule(),LinearLayout.LayoutParams(-1,activity.dp(1)).apply {bottomMargin=activity.dp(12)})
        footer.visibility=View.VISIBLE
        return activity.duckButton(label,primary,action).also {footer.addView(it,LinearLayout.LayoutParams(-1,-2).apply {topMargin=activity.dp(8)})}
    }
    override fun show() {super.show();window?.setLayout(-1,-1)}
}

internal class DuckField(context:Context,label:String,value:String="",numeric:Boolean=false,maxLength:Int?=null) {
    val view=LinearLayout(context).apply {orientation=LinearLayout.VERTICAL}
    val box=com.google.android.material.textfield.TextInputLayout(context,null,com.google.android.material.R.attr.textInputOutlinedStyle).apply {
        isHintEnabled=false;boxBackgroundMode=com.google.android.material.textfield.TextInputLayout.BOX_BACKGROUND_OUTLINE
        setBoxCornerRadii(context.dp(8).toFloat(),context.dp(8).toFloat(),context.dp(8).toFloat(),context.dp(8).toFloat())
        boxStrokeColor=context.getColor(R.color.duck_border)
    }
    val input=com.google.android.material.textfield.TextInputEditText(box.context).apply {
        setText(value);textSize=16f;isSingleLine=true;includeFontPadding=false
        setPadding(context.dp(12),context.dp(12),context.dp(12),context.dp(12));minimumHeight=context.dp(56)
        inputType=if(numeric) android.text.InputType.TYPE_CLASS_NUMBER else android.text.InputType.TYPE_CLASS_TEXT
        if(maxLength!=null) filters=arrayOf(android.text.InputFilter.LengthFilter(maxLength))
    }
    init {
        val name=context.duckParagraph(label);name.labelFor=View.generateViewId().also {input.id=it}
        view.addView(name,LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=context.dp(8)})
        box.addView(input,LinearLayout.LayoutParams(-1,-2));view.addView(box,LinearLayout.LayoutParams(-1,-2))
    }
}
internal fun Context.duckSelect(parent:LinearLayout,title:String,values:List<String>,selected:Int):Spinner {
    parent.addView(duckParagraph(title),LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(16);bottomMargin=dp(8)})
    val container=FrameLayout(this).apply {background=duckBackground(radius=8)}
    val spinner=Spinner(this,Spinner.MODE_DROPDOWN).apply {
        contentDescription=title;adapter=ArrayAdapter(this@duckSelect,android.R.layout.simple_spinner_dropdown_item,values)
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
