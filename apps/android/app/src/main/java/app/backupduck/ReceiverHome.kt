package app.backupduck

import android.view.Gravity
import android.view.View
import android.widget.*
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

internal class ReceiverHome(private val activity: MainActivity, connect: () -> Unit, iphone: () -> Unit, mac: () -> Unit,
    private val records: () -> Unit, private val toggleReceive: () -> Unit, recovery: () -> Unit) {
    private val title = activity.duckText("", 20, bold = true)
    private val subtitle = activity.duckText("", 13, true).apply {maxLines=1;ellipsize=android.text.TextUtils.TruncateAt.END}
    private val badge = activity.duckPill("")
    private val art = ImageView(activity)
    private lateinit var connection: com.google.android.material.button.MaterialButton
    private lateinit var pairOptions: LinearLayout
    private lateinit var pairExplanation: View
    private lateinit var batchSection: View
    private lateinit var recentList: RecyclerView
    private lateinit var pause: com.google.android.material.button.MaterialButton
    private lateinit var problemPanel: LinearLayout
    private lateinit var problemText:TextView
    private lateinit var problemAction: com.google.android.material.button.MaterialButton
    private val counts = DuckReadings(activity, listOf(activity.getString(R.string.duck_saved), activity.getString(R.string.duck_active), activity.getString(R.string.duck_failed)))
    private val readings = DuckReadings(activity, listOf(activity.getString(R.string.duck_battery_temp),activity.getString(R.string.duck_free),activity.getString(R.string.duck_battery)))
    private val adapter = TransferAdapter(activity)
    private var saved = 0; private var total = 0; private var failed = 0
    val view = activity.scrollPage { panel ->
        panel.setPadding(activity.dp(16), activity.dp(16), activity.dp(16), activity.dp(24))
        val hero = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL; background = activity.duckBackground(R.color.duck_subtle,16)
            setPadding(activity.dp(16),activity.dp(16),activity.dp(16),activity.dp(16))
        }
        panel.addView(hero)
        val large=activity.resources.configuration.fontScale>1.3f
        val heading = LinearLayout(activity).apply {orientation=if(large)LinearLayout.VERTICAL else LinearLayout.HORIZONTAL;gravity=Gravity.CENTER_VERTICAL}
        val line=if(large)LinearLayout(activity).apply {gravity=Gravity.CENTER_VERTICAL;heading.addView(this,LinearLayout.LayoutParams(-1,-2))} else heading
        hero.addView(heading, LinearLayout.LayoutParams(-1,-2))
        art.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        line.addView(art,LinearLayout.LayoutParams(activity.dp(44),activity.dp(44)).apply { marginEnd=activity.dp(10) })
        val words = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; addView(title); addView(subtitle,LinearLayout.LayoutParams(-1,-2).apply { topMargin=activity.dp(6) }) }
        line.addView(words,LinearLayout.LayoutParams(0,-2,1f));heading.addView(badge,LinearLayout.LayoutParams(-2,-2).apply {if(large) {marginStart=activity.dp(56);topMargin=activity.dp(8)}})
        connection = activity.duckButton(activity.getString(R.string.design_connect_device),true,connect).apply { setIconResource(R.drawable.ic_plus); iconSize=activity.dp(18); iconGravity=com.google.android.material.button.MaterialButton.ICON_GRAVITY_TEXT_START }
        hero.addView(connection,LinearLayout.LayoutParams(-1,activity.dp(48)).apply { topMargin=activity.dp(18) })
        problemPanel = LinearLayout(activity).apply { orientation=LinearLayout.VERTICAL; background=activity.duckBackground(R.color.duck_attention_background); setPadding(activity.dp(14),activity.dp(12),activity.dp(14),activity.dp(12)); visibility=View.GONE }
        val message=activity.duckMessageRow("",icon=R.drawable.ic_alert,iconColor=R.color.duck_attention)
        problemText=((message.getChildAt(1) as LinearLayout).getChildAt(0) as TextView)
        problemPanel.addView(message)
        problemAction=activity.duckLink(activity.getString(R.string.receiver_help_title),recovery); problemPanel.addView(problemAction)
        panel.addView(problemPanel,LinearLayout.LayoutParams(-1,-2).apply { topMargin=activity.dp(16) })
        batchSection = LinearLayout(activity).apply { orientation=LinearLayout.VERTICAL }.also { panel.addView(it) }
        val batch = batchSection as LinearLayout
        activity.duckSection(batch,activity.getString(R.string.duck_batch),activity.getString(R.string.duck_all_records),records)
        batch.addView(counts.view,LinearLayout.LayoutParams(-1,-2).apply { bottomMargin=activity.dp(12) })
        recentList=RecyclerView(activity).apply { layoutManager=LinearLayoutManager(activity); adapter=this@ReceiverHome.adapter; itemAnimator=null; isNestedScrollingEnabled=false }
        batch.addView(recentList,LinearLayout.LayoutParams(-1,-2))
        pause=activity.duckLink(activity.getString(R.string.duck_pause),toggleReceive)
        batch.addView(pause,LinearLayout.LayoutParams(-2,activity.dp(48)))
        pairOptions=LinearLayout(activity).apply { orientation=LinearLayout.VERTICAL }
        panel.addView(pairOptions)
        activity.duckSection(pairOptions,activity.getString(R.string.duck_how_pair))
        val options=activity.duckGroup(pairOptions)
        fun option(title:Int,note:Int,icon:Int,action:()->Unit) {
            activity.duckSetting(options,activity.getString(title),activity.getString(note),leadingIcon=icon,action=action)
        }
        option(R.string.duck_pair_iphone,R.string.duck_pair_iphone_note,R.drawable.ic_qr,iphone)
        option(R.string.duck_pair_mac,R.string.duck_pair_mac_note,R.drawable.ic_scan,mac)
        pairExplanation=LinearLayout(activity).apply { orientation=LinearLayout.VERTICAL }.also { panel.addView(it); activity.duckNotice(it,activity.getString(R.string.duck_pair_auto)) }
        panel.addView(readings.view,LinearLayout.LayoutParams(-1,-2).apply { topMargin=activity.dp(12) })
        activity.duckNotice(panel,activity.getString(R.string.duck_cloud_title),activity.getString(R.string.duck_cloud_unknown))
    }
    fun history(state: HistoryState) { adapter.submitList(state.items.take(3)) }
    fun totals(saved: Int,total: Int,failed: Int) { this.saved=saved;this.total=total;this.failed=failed;counts.render("$saved","${(total-saved-failed).coerceAtLeast(0)}","$failed") }
    fun render(state: ReceiverSnapshot,name: String?,pending: Boolean) = with(activity) {
        val enabled=ReceiverPreferences.enabled(this); val idle=!enabled; val paused=ReceiverPreferences.paused(this)
        if(state.phase=="ready") totals(state.published,state.total,state.failed)
        this@ReceiverHome.title.text=getString(when { state.thermalHeld -> R.string.duck_cooling; paused -> R.string.duck_reception_paused; pending||state.phase=="starting" -> R.string.receiver_starting; idle -> R.string.duck_ready_connect; state.phase=="ready" && state.total==0 -> R.string.duck_wait_receive; state.phase=="ready" && state.published==state.total && state.failed==0 -> R.string.duck_receive_done; state.phase=="ready" -> R.string.duck_receiving; else -> R.string.receiver_waiting })
        subtitle.text=if(idle) getString(R.string.duck_not_started,name ?: android.os.Build.MODEL) else if(state.thermalHeld) getString(R.string.receiver_thermal_cooling) else getString(R.string.duck_local_receiver,name ?: android.os.Build.MODEL)
        badge.text=getString(if(idle) R.string.duck_stopped else if(state.thermalHeld||paused||state.phase!="ready") R.string.duck_paused else R.string.duck_online)
        badge.setTextColor(getColor(if(idle) R.color.duck_text_secondary else if(state.thermalHeld||paused||state.phase!="ready") R.color.duck_attention else R.color.duck_saved))
        badge.background=duckBackground(if(idle) R.color.duck_subtle else if(state.thermalHeld||paused||state.phase!="ready") R.color.duck_attention_background else R.color.duck_saved_background,6,false)
        art.setImageResource(if(idle) R.drawable.ic_launcher_duck else R.drawable.ic_receiver)
        art.setPadding(dp(if(idle) 5 else 10),dp(if(idle) 5 else 10),dp(if(idle) 5 else 10),dp(if(idle) 5 else 10))
        art.imageTintList=if(idle) null else android.content.res.ColorStateList.valueOf(getColor(R.color.duck_action))
        art.background=duckBackground(if(idle) R.color.duck_brand_accent_background else R.color.duck_action_background,14,false)
        connection.isEnabled=!pending
        connection.backgroundTintList=android.content.res.ColorStateList.valueOf(getColor(if(idle) R.color.duck_action else R.color.duck_surface))
        connection.setTextColor(getColor(if(idle) R.color.duck_surface else R.color.duck_text));connection.iconTint=android.content.res.ColorStateList.valueOf(getColor(if(idle) R.color.duck_surface else R.color.duck_text))
        pairOptions.visibility=if(idle) View.VISIBLE else View.GONE; pairExplanation.visibility=pairOptions.visibility
        batchSection.visibility=if(idle) View.GONE else View.VISIBLE
        pause.text=getString(if(paused) R.string.duck_resume else R.string.duck_pause)
        val problem=receiverProblem(state)
        problemPanel.visibility=if(problem!=null||state.thermalHeld) View.VISIBLE else View.GONE
        if(problem!=null) { problemText.setText(problem.message);problemAction.setText(problem.action) }
        else if(state.thermalHeld) { problemText.text=getString(R.string.receiver_thermal_reading,state.temperatureDeciCelsius?.let { String.format(java.util.Locale.getDefault(),"%.1f",it/10.0) } ?: "—");problemAction.setText(R.string.receiver_thermal_threshold) }
        val reading=readThermal(this)
        readings.caption(2,getString(if(reading.charging==true) R.string.duck_battery_charging else R.string.duck_battery))
        readings.render(reading.deciCelsius?.let { String.format(java.util.Locale.getDefault(),"%.1f °C",it/10.0) } ?: "—",android.text.format.Formatter.formatShortFileSize(this,android.os.StatFs(filesDir.path).availableBytes),reading.batteryPercent?.let { "$it%" } ?: "—")
    }
}
