package app.backupduck

import android.app.Application
import android.graphics.Bitmap
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.ImageView
import androidx.lifecycle.lifecycleScope
import java.time.Duration
import java.util.UUID
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Synthetic viewer state and native gesture dispatch; no device or gallery content. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29], application = Application::class)
class PhotoUnavailableDetailTest {
    private val activity = Robolectric.buildActivity(MainActivity::class.java).get()
    private val contents = mutableListOf<PhotoDetail.Content>()

    @Before fun prepare() {
        activity.setTheme(R.style.AppTheme)
        PhotoImages.clearCache()
        ReceiverEnvironment.allowsPhotoMotion = false
        ReceiverEnvironment.previewImage = { _, _, _ -> null }
    }

    @After fun cleanup() {
        contents.forEach { it.cancel() }
        activity.lifecycleScope.cancel()
        ReceiverEnvironment.previewImage = null
        ReceiverEnvironment.allowsPhotoMotion = true
        PhotoImages.clearCache()
    }

    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()

    private fun detail(poster: Bitmap? = null): PhotoDetail.Content {
        val item = HistoryItem(1, UUID.randomUUID().toString(), "synthetic.video", "video", 1, 0,
            "receiving", "complete", null, false)
        val actions = ReceivedPhotosPage.Actions({}, {}, {}, { _, done -> done(true) }, {})
        return PhotoDetail(activity, PhotoImages(activity), actions).content(item, {}, { true }, poster = poster)
            .also(contents::add)
    }

    private fun settle(condition: () -> Boolean) {
        val deadline = System.nanoTime() + 5_000_000_000L
        while (!condition() && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle(); Thread.sleep(1)
        }
        assertTrue("Viewer preview must settle", condition())
    }

    private fun doubleTap(image: ImageView) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400))
        val start = SystemClock.uptimeMillis()
        for ((offset, action) in listOf(0L to MotionEvent.ACTION_DOWN, 40L to MotionEvent.ACTION_UP,
            120L to MotionEvent.ACTION_DOWN, 160L to MotionEvent.ACTION_UP)) {
            val event = MotionEvent.obtain(start, start + offset, action, 120f, 160f, 0)
            image.dispatchTouchEvent(event); event.recycle()
        }
    }

    @Test fun unavailableVideoKeepsGalleryActionWithoutCentralPlay() {
        val content = detail()
        val openLabel = activity.getString(R.string.viewer_open_photos)
        val controls = descendants(content.root).filter { it.contentDescription == openLabel }
        val play = controls.filterIsInstance<ImageButton>().single()
        assertEquals("Loading does not promise a usable preview", View.GONE, play.visibility)
        settle { content.preview.drawable != null }
        assertEquals(activity.getString(R.string.photos_preview_unavailable), content.preview.contentDescription)
        assertEquals(View.GONE, play.visibility)
        val gallery = controls.single { it !is ImageButton }
        assertEquals(View.VISIBLE, gallery.visibility)
        assertTrue(gallery.isClickable)
        val intrinsicWidth = content.preview.drawable.intrinsicWidth
        repeat(5) {
            content.reset()
            assertEquals(ImageView.ScaleType.CENTER, content.preview.scaleType)
            assertEquals(intrinsicWidth, content.preview.drawable.intrinsicWidth)
        }
    }

    @Test fun decodedVideoCoverShowsCentralActionRegardlessOfFilenameExtension() {
        val content = detail(Bitmap.createBitmap(640, 480, Bitmap.Config.ARGB_8888))
        val play = descendants(content.root).filterIsInstance<ImageButton>()
            .single { it.contentDescription == activity.getString(R.string.viewer_open_photos) }
        assertEquals(View.VISIBLE, play.visibility)
        repeat(3) { content.reset(); assertEquals(ImageView.ScaleType.FIT_CENTER, content.preview.scaleType) }
    }

    @Test fun unavailableGlyphCannotZoomButDecodedMediaStillCan() {
        val image = ImageView(activity)
        image.layout(0, 0, 400, 600)
        image.setImageDrawable(PhotoGlyphs.drawable(activity, R.drawable.ic_video, 56))
        var hasMedia = false
        val zoom = PhotoZoom(image, {}, {}, {}, { true }, { hasMedia })
        repeat(3) {
            zoom.reset(); doubleTap(image)
            assertEquals(ImageView.ScaleType.CENTER, image.scaleType)
        }
        image.setImageBitmap(Bitmap.createBitmap(800, 600, Bitmap.Config.ARGB_8888))
        hasMedia = true
        zoom.refresh()
        assertEquals(ImageView.ScaleType.FIT_CENTER, image.scaleType)
        doubleTap(image)
        assertEquals(ImageView.ScaleType.MATRIX, image.scaleType)
        zoom.reset()
        assertEquals(ImageView.ScaleType.FIT_CENTER, image.scaleType)
    }
}
