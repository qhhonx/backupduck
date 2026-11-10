package app.backupduck

import android.app.Application
import android.graphics.Rect
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Measures production empty-state views in both native scrolling containers. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29], application = Application::class, qualifiers = "w411dp-h731dp")
class EmptyStateLayoutTest {
    private val activity = Robolectric.buildActivity(MainActivity::class.java).get()
    private val actions = ReceivedPhotosPage.Actions({}, {}, {}, { _, done -> done(true) }, {})

    @Before fun theme() { activity.setTheme(R.style.AppTheme) }

    private fun layout(view: View, height: Int) {
        // Repeat the normal measure/layout pass after viewport dimensions become known.
        repeat(2) {
            view.measure(View.MeasureSpec.makeMeasureSpec(activity.dp(411), View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(activity.dp(height), View.MeasureSpec.EXACTLY))
            view.layout(0, 0, view.measuredWidth, view.measuredHeight)
        }
    }

    private fun photos(rows: List<PhotoRow>): RecyclerView {
        val adapter = PhotoAdapter(activity, PhotoImages(activity), { _, _ -> }, { _, _ -> }, actions)
        adapter.submitList(rows)
        shadowOf(Looper.getMainLooper()).idle()
        return RecyclerView(activity).apply {
            layoutManager = GridLayoutManager(activity, 3)
            this.adapter = adapter
            itemAnimator = null
        }
    }

    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()

    private fun contentBounds(view: View): Rect {
        val image = descendants(view).filterIsInstance<ImageView>().single()
        val box = image.parent as ViewGroup
        val first = Rect(0, 0, image.width, image.height)
        val last = box.getChildAt(box.childCount - 1).let { Rect(0, 0, it.width, it.height) to it }
        (view as ViewGroup).offsetDescendantRectToMyCoords(image, first)
        view.offsetDescendantRectToMyCoords(last.second, last.first)
        return Rect(first.left, first.top, first.right, last.first.bottom)
    }

    @Test fun photosAndReceiveContainersShareTheStandaloneStateCenter() {
        for (height in listOf(500, 731)) for (kind in listOf(StatusKind.EMPTY, StatusKind.FAILED)) {
            val scroll = activity.scrollPage { panel ->
                panel.setPadding(activity.token(R.dimen.duck_space_medium), activity.token(R.dimen.duck_space_x_small),
                    activity.token(R.dimen.duck_space_medium), activity.token(R.dimen.duck_space_large))
                val empty = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
                panel.addView(empty)
                if (kind == StatusKind.EMPTY) {
                    activity.lookEmpty(empty, R.drawable.duck_empty, activity.getString(R.string.photos_empty_title),
                        activity.getString(R.string.photos_empty_note), activity.getString(R.string.rhub_connect) to {},
                        card = false, centered = true)
                } else {
                    activity.lookUnavailable(empty, activity.getString(R.string.nav_photos),
                        activity.getString(R.string.photos_load_failed), activity.getString(R.string.photos_try_again) to {})
                }
            }
            val grid = photos(listOf(PhotoRow.Status(kind)))
            layout(scroll, height); layout(grid, height)
            val reference = contentBounds(scroll)
            val actual = contentBounds(grid)
            assertEquals("Native containers must not move the same empty block: " +
                descendants(scroll).joinToString { "${it.javaClass.simpleName}[${it.top},${it.height};p${it.paddingTop},${it.paddingBottom}]" } +
                " / " + descendants(grid).joinToString { "${it.javaClass.simpleName}[${it.top},${it.height};p${it.paddingTop},${it.paddingBottom}]" }, reference.top, actual.top)
            assertEquals(reference.bottom, actual.bottom)
            assertTrue("The complete state must remain within the viewport", actual.top >= 0 && actual.bottom <= grid.height)
            assertEquals("Empty content belongs at the optical center", grid.height * 0.45f,
                actual.exactCenterY(), activity.dp(10).toFloat())
        }
    }

    @Test fun pagingFailureKeepsItsRecoveryBesideTheExistingContent() {
        val grid = photos(listOf(PhotoRow.Scope, PhotoRow.Status(StatusKind.FAILED)))
        layout(grid, 731)
        val recovery = grid.findViewHolderForAdapterPosition(1)!!.itemView
        assertTrue("A failed later page must not consume another full viewport", recovery.height < grid.height / 2)
        assertTrue("Recovery must remain reachable without scrolling past a blank viewport", recovery.bottom <= grid.height)
    }
}
