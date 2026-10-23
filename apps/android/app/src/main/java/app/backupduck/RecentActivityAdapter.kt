package app.backupduck

import android.content.Context
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import org.json.JSONObject
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Date
import com.google.android.material.R as M

internal data class DiagnosticEntry(val raw: JSONObject) {
    val id = raw.getLong("id")
    val timestamp = raw.optLong("timestamp")
    fun title(context: Context): String {
        val resource = context.resources.getIdentifier("diag_event_${raw.optString("code")}", "string", context.packageName)
        return context.getString(if (resource != 0) resource else R.string.diag_other)
    }
}

/** A bounded, read-only summary; the export retains the complete journal. */
internal class RecentActivityAdapter(private val context: Context) : RecyclerView.Adapter<RecentActivityAdapter.Holder>() {
    private var rows = emptyList<Any>()
    private val locale get() = context.resources.configuration.locales[0]
    init { setHasStableIds(true) }
    fun submit(entries: List<DiagnosticEntry>) {
        rows = buildList {
            var previous: String? = null
            entries.forEach { entry ->
                val day = if (entry.timestamp > 0) DateFormat.getDateInstance(DateFormat.MEDIUM, locale).format(Date(entry.timestamp * 1000))
                    else context.getString(R.string.diag_unknown_time)
                if (day != previous) { add(day); previous = day }
                add(entry)
            }
        }
        notifyDataSetChanged()
    }
    override fun getItemCount() = rows.size
    override fun getItemId(position: Int) = (rows[position] as? DiagnosticEntry)?.id ?: Long.MIN_VALUE + rows[position].hashCode().toLong()
    override fun getItemViewType(position: Int) = if (rows[position] is String) 0 else 1
    override fun onCreateViewHolder(parent: ViewGroup, type: Int): Holder = with(context) {
        val row = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            isBaselineAligned = false
            minimumHeight = token(R.dimen.duck_space_xx_large)
            setPadding(0, token(R.dimen.duck_space_x_small), 0, token(R.dimen.duck_space_x_small))
            layoutParams = RecyclerView.LayoutParams(-1, -2)
        }
        if (type == 0) row.addView(lookText("", M.style.TextAppearance_Material3_LabelLarge, secondary = true).apply { isAccessibilityHeading = true })
        else {
            row.addView(lookText("", M.style.TextAppearance_Material3_BodyMedium), LinearLayout.LayoutParams(0, -2, 1f))
            row.addView(lookText("", M.style.TextAppearance_Material3_BodySmall, secondary = true).apply { setSingleLine() },
                LinearLayout.LayoutParams(-2, -2).apply { marginStart = token(R.dimen.duck_space_medium) })
        }
        Holder(row)
    }
    override fun onBindViewHolder(holder: Holder, position: Int) {
        val row = holder.itemView as LinearLayout
        val item = rows[position]
        if (item is String) (row.getChildAt(0) as TextView).text = item
        else {
            item as DiagnosticEntry
            (row.getChildAt(0) as TextView).text = item.title(context)
            (row.getChildAt(1) as TextView).text = if (item.timestamp > 0) SimpleDateFormat("HH:mm", locale).format(Date(item.timestamp * 1000)) else "—"
        }
    }
    internal class Holder(row: LinearLayout) : RecyclerView.ViewHolder(row)
}
