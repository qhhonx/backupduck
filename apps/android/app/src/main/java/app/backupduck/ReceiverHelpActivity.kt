package app.backupduck

import android.content.Intent
import android.os.Bundle
import android.view.MenuItem
import android.view.View
import android.widget.LinearLayout
import androidx.appcompat.widget.SearchView
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.widget.NestedScrollView
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.R as M

/** Stable keys retain the five existing help links while the articles follow the task contract. */
internal enum class ReceiverHelpTopic(val key: String, val title: Int, val icon: Int, val paragraphs: List<Int>) {
    RESULTS("results", R.string.help2_results_title, R.drawable.ic_check, listOf(R.string.help2_results_p1, R.string.help2_results_p2, R.string.help2_results_p3)),
    BACKGROUND("background", R.string.help2_background_title, R.drawable.ic_bell, listOf(R.string.help2_background_p1, R.string.help2_background_p2, R.string.help2_background_p3)),
    STORAGE("storage", R.string.help2_storage_title, R.drawable.ic_storage, listOf(R.string.help2_storage_p1, R.string.help2_storage_p2, R.string.help2_storage_p3)),
    CONNECT("connect", R.string.help2_connect_title, R.drawable.ic_qr, listOf(R.string.help2_connect_p1, R.string.help2_connect_p2, R.string.help2_connect_p3)),
    CONNECTION("connection", R.string.help2_connection_title, R.drawable.ic_wifi, listOf(R.string.help2_connection_p1, R.string.help2_connection_p2)),
    RECOVERY("recovery", R.string.help2_recovery_title, R.drawable.ic_photo, listOf(R.string.help2_recovery_p1, R.string.help2_recovery_p2, R.string.help2_recovery_p3)),
    FULL("full", R.string.help2_full_title, R.drawable.ic_storage, listOf(R.string.help2_full_p1, R.string.help2_full_p2, R.string.help2_full_p3)),
    STOPPED("stopped", R.string.help2_stopped_title, R.drawable.ic_receiver, listOf(R.string.help2_stopped_p1, R.string.help2_stopped_p2, R.string.help2_stopped_p3)),
    CLEANUP("cleanup", R.string.help2_cleanup_title, R.drawable.ic_bolt, listOf(R.string.help2_cleanup_p1, R.string.help2_cleanup_p2, R.string.help2_cleanup_p3));

    companion object {
        val tasks = listOf(RESULTS, BACKGROUND, STORAGE, CONNECT)
        val problems = listOf(CONNECTION, RECOVERY, FULL, STOPPED, CLEANUP)
        fun fromKey(key: String?) = entries.firstOrNull { it.key == key }
    }
}

/** Packaged, read-only guidance. */
class ReceiverHelpActivity : BackupDuckActivity() {
    private var query = ""
    private var searchExpanded = false
    private lateinit var scroll: NestedScrollView

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("query", query)
        outState.putBoolean("search-expanded", searchExpanded)
        outState.putInt("scroll", scroll.scrollY)
        super.onSaveInstanceState(outState)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        query = savedInstanceState?.getString("query").orEmpty()
        val topic = ReceiverHelpTopic.fromKey(intent.getStringExtra("topic"))
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(getColor(R.color.duck_role_background))
        }
        val toolbar = MaterialToolbar(this).apply {
            if (topic == null) setTitle(R.string.pref_help)
            setNavigationIcon(R.drawable.ic_back)
            setNavigationContentDescription(R.string.nav_back)
            setNavigationOnClickListener { finish() }
        }
        root.addView(toolbar, LinearLayout.LayoutParams(-1, resources.getDimensionPixelSize(M.dimen.m3_appbar_size_compact)))
        val body = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val inset = token(R.dimen.duck_space_large)
            setPadding(inset, token(R.dimen.duck_space_small), inset, inset)
        }
        scroll = NestedScrollView(this).apply {
            isFillViewport = true
            // The reading surface can take keyboard focus without painting the whole canvas.
            defaultFocusHighlightEnabled = false
            addView(body)
        }
        root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        if (topic == null) index(toolbar, body) else article(topic, body)
        setContentView(root)
        if (topic == null && savedInstanceState?.getBoolean("search-expanded") == true) {
            toolbar.menu.findItem(1).expandActionView()
            (toolbar.menu.findItem(1).actionView as SearchView).apply {
                setQuery(savedInstanceState.getString("query").orEmpty(), false)
                clearFocus()
            }
        }
        scroll.post { scroll.scrollTo(0, savedInstanceState?.getInt("scroll") ?: 0) }
    }

    private fun index(toolbar: MaterialToolbar, body: LinearLayout) {
        fun render() {
            body.removeAllViews()
            var count = 0
            listOf(R.string.help_tasks to ReceiverHelpTopic.tasks, R.string.help_problems to ReceiverHelpTopic.problems).forEach { (heading, topics) ->
                val matches = topics.filter { topic ->
                    (listOf(topic.title) + topic.paragraphs).any { getString(it).contains(query.trim(), ignoreCase = true) }
                }
                if (matches.isNotEmpty()) {
                    count += matches.size
                    lookSection(body, getString(heading))
                    val group = lookGroup(body)
                    matches.forEach { entry ->
                        lookRow(group, entry.icon, getString(entry.title)) {
                            startActivity(Intent(this, ReceiverHelpActivity::class.java).putExtra("topic", entry.key))
                        }
                    }
                }
            }
            if (count == 0) body.addView(lookText(getString(R.string.help_no_results), M.style.TextAppearance_Material3_BodyLarge, secondary = true))
        }
        val search = SearchView(this).apply {
            queryHint = getString(R.string.help_search)
            maxWidth = Int.MAX_VALUE
            setIconifiedByDefault(false)
            setQuery(this@ReceiverHelpActivity.query, false)
            setOnQueryTextListener(object : SearchView.OnQueryTextListener {
                override fun onQueryTextSubmit(text: String?): Boolean { clearFocus(); return true }
                override fun onQueryTextChange(text: String?): Boolean {
                    this@ReceiverHelpActivity.query = text.orEmpty(); render(); scroll.scrollTo(0, 0); return true
                }
            })
        }
        toolbar.menu.add(0, 1, 0, R.string.help_search).apply {
            setIcon(androidx.appcompat.R.drawable.abc_ic_search_api_material)
            icon?.setTint(getColor(R.color.duck_role_primary_text))
            actionView = search
            setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS or MenuItem.SHOW_AS_ACTION_COLLAPSE_ACTION_VIEW)
            setOnActionExpandListener(object : MenuItem.OnActionExpandListener {
                override fun onMenuItemActionExpand(item: MenuItem): Boolean { searchExpanded = true; return true }
                override fun onMenuItemActionCollapse(item: MenuItem): Boolean {
                    searchExpanded = false; search.setQuery("", false); search.clearFocus(); return true
                }
            })
        }
        render()
    }

    private fun article(topic: ReceiverHelpTopic, body: LinearLayout) {
        body.addView(lookText(getString(topic.title), M.style.TextAppearance_Material3_HeadlineSmall).apply { isAccessibilityHeading = true },
            LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = token(R.dimen.duck_space_large) })
        topic.paragraphs.forEach { text ->
            body.addView(lookText(getString(text), M.style.TextAppearance_Material3_BodyLarge),
                LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = token(R.dimen.duck_space_medium) })
        }

    }
}
