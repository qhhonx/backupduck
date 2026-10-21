package app.backupduck

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

/** Every receiver activity uses the same generated fixed Material scheme. */
open class BackupDuckActivity : AppCompatActivity() {
    internal open fun restorePage(route: String, state: Bundle): PageDestination = error("Unknown page: $route")

    override fun setContentView(view: android.view.View?) {
        val content = requireNotNull(view)
        val root = android.widget.FrameLayout(this)
        root.addView(content, android.widget.FrameLayout.LayoutParams(-1, -1))
        root.addView(androidx.fragment.app.FragmentContainerView(this).apply { id = R.id.page_destinations },
            android.widget.FrameLayout.LayoutParams(-1, -1))
        super.setContentView(root)
        fun updateAccessibility() {
            content.importantForAccessibility = if (supportFragmentManager.backStackEntryCount == 0)
                android.view.View.IMPORTANT_FOR_ACCESSIBILITY_AUTO else android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        supportFragmentManager.addOnBackStackChangedListener { updateAccessibility() }
        updateAccessibility()
    }

    override fun onStart() {
        // Activity-result callbacks run at STARTED. Rebind their page before those callbacks.
        supportFragmentManager.fragments.filterIsInstance<PageFragment>().forEach { it.prepare() }
        super.onStart()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        DuckLook.applyScheme(this)
    }
}
