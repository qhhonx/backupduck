package app.backupduck

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.core.widget.NestedScrollView
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentTransaction
import com.google.android.material.appbar.MaterialToolbar

/** I1/A2: page content stays with its existing owner; FragmentManager owns navigation. */
internal open class PageDestination(val activity: BackupDuckActivity, val route: String, title: String) {
    val state = Bundle()
    var saveState: (() -> Bundle)? = null
    var resumed: (() -> Unit)? = null
    private var closed: (() -> Unit)? = null
    internal var fragment: PageFragment? = null
    private var open = false
    val isShowing get() = open
    val root = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        isClickable = true
        setBackgroundColor(activity.getColor(R.color.duck_role_background))
    }
    val body = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    protected val footer = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; visibility = View.GONE }
    init {
        androidx.core.view.ViewCompat.setAccessibilityPaneTitle(root, title)
        root.addView(MaterialToolbar(activity).apply {
            this.title = title
            setNavigationIcon(R.drawable.ic_back)
            setNavigationContentDescription(R.string.nav_back)
            setNavigationOnClickListener { activity.onBackPressedDispatcher.onBackPressed() }
        }, LinearLayout.LayoutParams(-1, -2))
        root.addView(NestedScrollView(activity).apply {
            id = R.id.destination_scroll
            isFillViewport = true
            addView(body)
        }, LinearLayout.LayoutParams(-1, 0, 1f))
        root.addView(footer, LinearLayout.LayoutParams(-1, -2))
    }
    fun setOnDismissListener(listener: (() -> Unit)?) { closed = listener }
    internal fun attached(fragment: PageFragment) { this.fragment = fragment; open = true }
    internal fun removed() { open = false; closed?.invoke() }
    fun show() {
        if (open) return
        check(!activity.supportFragmentManager.isStateSaved)
        val next = PageFragment().also {
            it.arguments = Bundle().apply { putString("route", route); putBundle("state", state) }
            it.page = this
        }
        attached(next)
        activity.pushPage(next)
    }
    fun dismiss() {
        val tag = fragment?.tag ?: return
        activity.supportFragmentManager.popBackStack(tag, androidx.fragment.app.FragmentManager.POP_BACK_STACK_INCLUSIVE)
    }
}

/** Recreated from a route and UI state, never from a retained Activity, View or callback. */
class PageFragment : Fragment() {
    internal var page: PageDestination? = null
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        return prepare(savedInstanceState?.getBundle("state")).root
    }
    internal fun prepare(savedState: Bundle? = null): PageDestination {
        val owner = requireActivity() as BackupDuckActivity
        return (page ?: owner.restorePage(requireArguments().getString("route")!!,
            savedState ?: restoredState ?: requireArguments().getBundle("state") ?: Bundle()).also { page = it })
            .also { it.attached(this) }
    }
    private var restoredState: Bundle? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        restoredState = savedInstanceState?.getBundle("state")
    }
    override fun onResume() { super.onResume(); page?.resumed?.invoke() }
    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        page?.let { outState.putBundle("state", it.saveState?.invoke() ?: it.state) }
    }
    override fun onDestroy() {
        page?.removed()
        page = null
        super.onDestroy()
    }
}

internal fun BackupDuckActivity.pushPage(next: PageFragment) {
    val manager = supportFragmentManager
    manager.executePendingTransactions()
    val previous = manager.primaryNavigationFragment
    manager.beginTransaction().apply {
        setReorderingAllowed(true)
        setTransition(FragmentTransaction.TRANSIT_FRAGMENT_OPEN)
        if (previous != null) {
            hide(previous)
            setMaxLifecycle(previous, androidx.lifecycle.Lifecycle.State.STARTED)
        }
        val tag = java.util.UUID.randomUUID().toString()
        add(R.id.page_destinations, next, tag)
        setPrimaryNavigationFragment(next)
        addToBackStack(tag)
    }.commit()
}
