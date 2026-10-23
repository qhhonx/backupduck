package app.backupduck

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.text.TextUtils
import android.view.Gravity
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AppCompatDelegate
import androidx.appcompat.widget.SearchView
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import com.google.android.material.R as M

internal data class DiagnosticEntry(val raw: JSONObject) {
    val id = raw.getLong("id")
    val timestamp = raw.optLong("timestamp")
    val code = raw.optString("code")
    fun title(context: android.content.Context): String {
        val resource = context.resources.getIdentifier("diag_event_$code", "string", context.packageName)
        return context.getString(if (resource != 0) resource else R.string.diag_other)
    }
    fun matches(filter: Int): Boolean = when (filter) {
        1 -> code in setOf("network", "capacity", "integrity", "authentication", "storage", "internal") ||
            listOf("fail", "error", "unavailable", "low_space", "interrupted", "blocked").any { code.contains(it) }
        2 -> !raw.isNull("job_id") || listOf("transfer", "publication", "processing", "receiver").any { code.contains(it) }
        3 -> listOf("space", "storage", "capacity", "cache", "original", "archive", "cleanup", "relay").any { code.contains(it) }
        else -> true
    }
    fun fields(): List<Pair<String,String>> {
        val result = mutableListOf<Pair<String,String>>()
        fun visit(key: String, value: Any) {
            if (value is JSONObject && value.length() > 0) value.keys().asSequence().sorted().forEach { visit("$key.$it", value.get(it)) }
            else result += key to value.toString()
        }
        val order = listOf("id", "timestamp", "code", "job_id", "bytes", "context")
        (order.filter(raw::has) + raw.keys().asSequence().filter { it !in order }.sorted().toList()).forEach { visit(it, raw.get(it)) }
        return result
    }
}

/** Bounded core journal, virtualized native rows and immutable entry detail. */
class ReceiverActivityLogActivity : BackupDuckActivity() {
    private var query = ""
    private var filter = 0
    private var expanded = false
    private var entries = emptyList<DiagnosticEntry>()
    private lateinit var list: RecyclerView
    private lateinit var feedback: LinearLayout
    private lateinit var adapter: JournalAdapter
    private var loading: Job? = null
    private var reading = true
    private var readFailed = false
    private var restoredScroll: android.os.Parcelable? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        val detail = intent.getStringExtra("entry")?.let { DiagnosticEntry(JSONObject(it)) }
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(getColor(R.color.duck_role_background)) }
        val toolbar = MaterialToolbar(this).apply {
            setTitle(if (detail == null) R.string.diag_log else R.string.diag_detail)
            setNavigationIcon(R.drawable.ic_back); setNavigationContentDescription(R.string.nav_back); setNavigationOnClickListener { finish() }
        }
        root.addView(toolbar, LinearLayout.LayoutParams(-1, resources.getDimensionPixelSize(M.dimen.m3_appbar_size_compact)))
        if (detail != null) { detail(detail, toolbar, root); setContentView(root); return }
        query = savedInstanceState?.getString("query").orEmpty(); filter = savedInstanceState?.getInt("filter") ?: 0
        restoredScroll = savedInstanceState?.getParcelable("scroll")
        val choices = ChipGroup(this).apply { isSingleSelection = true; isSelectionRequired = true; isSingleLine = true }
        listOf(R.string.diag_all, R.string.diag_problems, R.string.diag_transfers, R.string.diag_storage).forEachIndexed { index, title ->
            choices.addView(Chip(this).apply {
                id = View.generateViewId(); setText(title); isCheckable = true; isChecked = index == filter
                setOnCheckedChangeListener { _, checked -> if (checked && filter != index) { filter = index; render(); list.scrollToPosition(0) } }
            })
        }
        root.addView(HorizontalScrollView(this).apply { isHorizontalScrollBarEnabled = false; addView(choices); setPadding(token(R.dimen.duck_space_medium),0,token(R.dimen.duck_space_medium),0) })
        feedback = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            setPadding(token(R.dimen.duck_space_large),token(R.dimen.duck_space_large),token(R.dimen.duck_space_large),token(R.dimen.duck_space_large))
        }
        root.addView(feedback, LinearLayout.LayoutParams(-1, -2))
        adapter = JournalAdapter()
        list = RecyclerView(this).apply { layoutManager = LinearLayoutManager(this@ReceiverActivityLogActivity); adapter = this@ReceiverActivityLogActivity.adapter; itemAnimator = null }
        root.addView(list, LinearLayout.LayoutParams(-1,0,1f))
        val search = SearchView(this).apply {
            queryHint = getString(R.string.diag_search); setIconifiedByDefault(false); maxWidth = Int.MAX_VALUE
            setOnQueryTextListener(object : SearchView.OnQueryTextListener {
                override fun onQueryTextSubmit(text: String?): Boolean { clearFocus(); return true }
                override fun onQueryTextChange(text: String?): Boolean { this@ReceiverActivityLogActivity.query = text.orEmpty(); render(); list.scrollToPosition(0); return true }
            })
        }
        toolbar.menu.add(0,1,0,R.string.diag_search).apply {
            setIcon(androidx.appcompat.R.drawable.abc_ic_search_api_material); icon?.setTint(getColor(R.color.duck_role_primary_text))
            actionView = search; setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS or MenuItem.SHOW_AS_ACTION_COLLAPSE_ACTION_VIEW)
            setOnActionExpandListener(object : MenuItem.OnActionExpandListener {
                override fun onMenuItemActionExpand(item: MenuItem): Boolean { expanded = true; return true }
                override fun onMenuItemActionCollapse(item: MenuItem): Boolean { expanded = false; search.setQuery("",false); search.clearFocus(); return true }
            })
        }
        toolbar.menu.add(R.string.diag_refresh).setOnMenuItemClickListener { load(); true }
        setContentView(root)
        if (savedInstanceState?.getBoolean("expanded") == true) { toolbar.menu.findItem(1).expandActionView(); search.setQuery(savedInstanceState.getString("query").orEmpty(),false); search.clearFocus() }
        load()
    }
    override fun onSaveInstanceState(out: Bundle) {
        out.putString("query",query); out.putInt("filter",filter); out.putBoolean("expanded",expanded)
        if (::list.isInitialized) out.putParcelable("scroll",list.layoutManager?.onSaveInstanceState())
        super.onSaveInstanceState(out)
    }
    private fun load() {
        loading?.cancel(); reading = true; readFailed = false
        loading = lifecycleScope.launch {
            val hint = launch { delay(180); if (entries.isEmpty()) state(R.string.diag_loading, null, false) }
            val result = withContext(Dispatchers.IO) { runCatching {
                val raw = ReceiverLogPolicy.read("$filesDir/receiver")
                (0 until raw.length()).map { DiagnosticEntry(raw.getJSONObject(it)) }.sortedWith(compareByDescending<DiagnosticEntry> { it.timestamp }.thenByDescending { it.id })
            } }
            hint.cancel(); ensureActive(); reading = false
            result.onSuccess { loaded ->
                entries = loaded
                render()
                restoredScroll?.let { list.layoutManager?.onRestoreInstanceState(it); restoredScroll = null }
                if (intent.getBooleanExtra("detail",false) && entries.isNotEmpty()) { intent.removeExtra("detail"); open(entries.first()) }
            }.onFailure { readFailed = true; state(R.string.diag_read_failed,R.string.diag_read_failed_note,true) }
        }
    }
    private fun state(title: Int, note: Int?, retry: Boolean) {
        feedback.removeAllViews(); feedback.visibility = View.VISIBLE
        val empty = adapter.itemCount == 0
        feedback.layoutParams = LinearLayout.LayoutParams(-1,if(empty)0 else -2,if(empty)1f else 0f)
        list.visibility = if(empty)View.GONE else View.VISIBLE
        if (title == R.string.diag_loading) {
            feedback.addView(com.google.android.material.progressindicator.CircularProgressIndicator(this).apply { isIndeterminate = true })
            feedback.addView(lookText(getString(title), M.style.TextAppearance_Material3_BodyMedium,secondary=true).apply { gravity = Gravity.CENTER })
        } else lookEmpty(feedback,if(retry)R.drawable.ic_alert else R.drawable.ic_document,getString(title),note?.let(::getString),
            if(retry)getString(R.string.duck_retry) to {load()} else null,card=false,centered=true)
    }

    private fun render() {
        if (!::adapter.isInitialized) return
        feedback.visibility = View.GONE; list.visibility = View.VISIBLE
        val filtered = entries.filter { it.matches(filter) && (it.title(this)+" "+it.raw).contains(query.trim(),true) }
        adapter.rows = buildList {
            var previous: String? = null
            filtered.forEach { entry ->
                val day = if (entry.timestamp > 0) format(entry.timestamp,"yyyy-MM-dd") else getString(R.string.diag_unknown_time)
                if (day != previous) { add(day); previous = day }
                add(entry)
            }
        }
        adapter.notifyDataSetChanged()
        if (readFailed) state(R.string.diag_read_failed,R.string.diag_read_failed_note,true)
        else if (reading && entries.isEmpty()) state(R.string.diag_loading,null,false)
        else if (filtered.isEmpty()) state(if(entries.isEmpty())R.string.diag_empty else R.string.diag_no_matches,
            if(entries.isEmpty())R.string.diag_empty_note else R.string.diag_no_matches_note,false)
    }
    private fun format(timestamp: Long, pattern: String) = SimpleDateFormat(pattern, resources.configuration.locales[0]).format(Date(timestamp*1000))
    private fun open(entry: DiagnosticEntry) { startActivity(Intent(this,ReceiverActivityLogActivity::class.java).putExtra("entry",entry.raw.toString())) }
    private inner class JournalAdapter : RecyclerView.Adapter<JournalHolder>() {
        var rows = emptyList<Any>()
        init { setHasStableIds(true) }
        override fun getItemCount() = rows.size
        override fun getItemId(position: Int) = (rows[position] as? DiagnosticEntry)?.id ?: Long.MIN_VALUE + rows[position].hashCode().toLong()
        override fun getItemViewType(position: Int) = if (rows[position] is String) 0 else 1
        override fun onCreateViewHolder(parent: ViewGroup, type: Int): JournalHolder {
            val row = LinearLayout(this@ReceiverActivityLogActivity).apply {
                gravity = Gravity.CENTER_VERTICAL; isBaselineAligned = true
                minimumHeight = token(R.dimen.duck_space_xx_large)
                setPadding(token(R.dimen.duck_space_medium),token(R.dimen.duck_space_x_small),token(R.dimen.duck_space_medium),token(R.dimen.duck_space_x_small))
                layoutParams = RecyclerView.LayoutParams(-1,-2)
            }
            if (type == 0) row.addView(lookText("",M.style.TextAppearance_Material3_LabelLarge,secondary=true).apply { isAccessibilityHeading = true })
            else {
                row.isFocusable = true; row.isClickable = true; row.background = selectableBackground()
                row.addView(lookText("",M.style.TextAppearance_Material3_BodySmall,secondary=true).apply { typeface=Typeface.MONOSPACE; setSingleLine() })
                row.addView(lookText("",M.style.TextAppearance_Material3_BodyMedium).apply { setSingleLine(); ellipsize=TextUtils.TruncateAt.END },LinearLayout.LayoutParams(0,-2,1f).apply { leftMargin=token(R.dimen.duck_space_small); rightMargin=token(R.dimen.duck_space_small) })
                row.addView(lookText("",M.style.TextAppearance_Material3_LabelSmall,secondary=true).apply {
                    typeface=Typeface.MONOSPACE; setSingleLine(); ellipsize=TextUtils.TruncateAt.MIDDLE
                    maxWidth=token(R.dimen.duck_space_xx_large)*3
                })
            }
            return JournalHolder(row)
        }
        override fun onBindViewHolder(holder: JournalHolder, position: Int) {
            val item=rows[position]; val row=holder.itemView as LinearLayout
            if(item is String) (row.getChildAt(0) as TextView).text=item
            else { item as DiagnosticEntry
                val time=if(item.timestamp>0)format(item.timestamp,"HH:mm:ss") else "—"
                (row.getChildAt(0) as TextView).text=time
                (row.getChildAt(1) as TextView).text=item.title(this@ReceiverActivityLogActivity)
                (row.getChildAt(2) as TextView).text=item.code
                row.contentDescription="$time, ${item.title(this@ReceiverActivityLogActivity)}, ${item.code}"
                row.setOnClickListener { open(item) }
            }
        }
    }
    private class JournalHolder(view: View): RecyclerView.ViewHolder(view)
    private fun detail(entry: DiagnosticEntry, toolbar: MaterialToolbar, root: LinearLayout) {
        val body = LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; setPadding(token(R.dimen.duck_space_medium),token(R.dimen.duck_space_small),token(R.dimen.duck_space_medium),token(R.dimen.duck_space_large)) }
        root.addView(androidx.core.widget.NestedScrollView(this).apply { defaultFocusHighlightEnabled=false; addView(body) },LinearLayout.LayoutParams(-1,0,1f))
        body.addView(lookText(entry.title(this),M.style.TextAppearance_Material3_TitleMedium))
        fun copy(value:String) { getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText(getString(R.string.diag_detail),value)) }
        toolbar.menu.add(R.string.diag_copy_all).apply {
            setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
            setOnMenuItemClickListener { copy(entry.raw.toString(2)); setTitle(R.string.diag_copied); true }
        }
        entry.fields().forEach { (key,value) ->
            val row=LinearLayout(this).apply { gravity=Gravity.TOP; setPadding(0,token(R.dimen.duck_space_small),0,token(R.dimen.duck_space_small)) }
            val texts=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL }
            val label=resources.getIdentifier("diag_field_${key.substringAfterLast('.')}","string",packageName)
            texts.addView(lookText(if(label!=0)getString(label) else key.substringAfterLast('.').replace('_',' '),M.style.TextAppearance_Material3_LabelLarge))
            texts.addView(lookText(key,M.style.TextAppearance_Material3_LabelSmall,secondary=true).apply { typeface=Typeface.MONOSPACE })
            texts.addView(lookText(value,M.style.TextAppearance_Material3_BodyMedium).apply { typeface=Typeface.MONOSPACE; setTextIsSelectable(true) })
            row.addView(texts,LinearLayout.LayoutParams(0,-2,1f))
            lateinit var action: com.google.android.material.button.MaterialButton
            action=lookButton(getString(R.string.diag_copy),LookButton.TEXT) { copy(value); action.setText(R.string.diag_copied) }
            action.contentDescription=getString(R.string.diag_copy)+" "+(if(label!=0)getString(label) else key)
            row.addView(action)
            body.addView(row,LinearLayout.LayoutParams(-1,-2))
        }
    }
}
