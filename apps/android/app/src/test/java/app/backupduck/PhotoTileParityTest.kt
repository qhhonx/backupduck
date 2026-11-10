package app.backupduck

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.lifecycle.lifecycleScope
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
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29], application = Application::class, qualifiers = "w411dp-h731dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PhotoTileParityTest {
    private val activity = Robolectric.buildActivity(MainActivity::class.java).get()
    private lateinit var images: PhotoImages
    private val tiles = mutableListOf<PhotoTile>()
    private fun item(phase: String) = HistoryItem(1, UUID.randomUUID().toString(), "synthetic.mp4", "video",
        1, 1, "received", phase, null, false)
    @Before fun prepare() {
        activity.setTheme(R.style.AppTheme)
        PhotoImages.clearCache(); ReceiverEnvironment.allowsPhotoMotion = false
        ReceiverEnvironment.previewImage = { _, _, _ -> null }
        ReceiverEnvironment.videoDuration = { _, _ -> 83_000 }
        images = PhotoImages(activity)
    }
    @After fun cleanup() {
        tiles.forEach { it.cancel() }; activity.lifecycleScope.cancel()
        ReceiverEnvironment.previewImage = null; ReceiverEnvironment.videoDuration = null
        ReceiverEnvironment.allowsPhotoMotion = true; PhotoImages.clearCache()
    }
    private fun settle(condition: () -> Boolean) {
        val deadline = System.nanoTime() + 5_000_000_000L
        while (!condition() && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle(); Thread.sleep(1)
        }
        assertTrue("Receipt preview and metadata must settle", condition())
    }
    private fun badge(tile: PhotoTile) = tile.getChildAt(1) as ImageView
    private fun clock(tile: PhotoTile) = (tile.getChildAt(2) as LinearLayout).getChildAt(0) as TextView
    private fun kind(tile: PhotoTile) = (tile.getChildAt(2) as LinearLayout).getChildAt(1) as ImageView
    private fun tile() = PhotoTile(activity, images).also(tiles::add)

    @Test fun recentAndTimelineKeepTheReceiptCoverAndUpdatePublicationMarksInPlace() {
        val pending = item("pending")
        ReceiptThumbnails.save(activity, pending.id, Bitmap.createBitmap(180, 90, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.BLUE) })
        val actions = ReceivedPhotosPage.Actions({}, {}, {}, { _, done -> done(true) }, {})
        val adapter = PhotoAdapter(activity, images, { _, _ -> }, { _, _ -> }, actions)
        val holder = adapter.onCreateViewHolder(FrameLayout(activity), 5) as PhotoAdapter.TileHolder
        val timeline = (holder.itemView as FrameLayout).getChildAt(0) as PhotoTile
        tiles += timeline
        holder.bind(pending)
        val mosaic = PhotoMosaic(activity)
        mosaic.bind(listOf(pending), images, { it.filename }) { _, _, _ -> }
        val recent = mosaic.getChildAt(0) as PhotoTile; tiles += recent
        settle { recent.image.photoPoster(pending.id) != null && timeline.image.photoPoster(pending.id) != null && clock(recent).text == "1:23" }
        assertEquals(ImageView.ScaleType.CENTER_CROP, recent.image.scaleType)
        assertEquals(timeline.image.scaleType, recent.image.scaleType)
        assertEquals(View.VISIBLE, badge(recent).visibility)
        assertEquals(badge(timeline).drawable.intrinsicWidth, badge(recent).drawable.intrinsicWidth)
        assertEquals(kind(timeline).drawable.intrinsicWidth, kind(recent).drawable.intrinsicWidth)
        val shown = checkNotNull(recent.image.photoPoster(pending.id))
        val saved = pending.copy(processing = "complete")
        mosaic.bind(listOf(saved), images, { it.filename }) { _, _, _ -> }
        assertSame("Progress changes retain the native tile", recent, mosaic.getChildAt(0))
        val retained = recent.image.photoPoster(saved.id)
        assertTrue("Publication must retain the visible receipt pixels until a better cover is available",
            retained != null && shown.sameAs(retained))
        assertEquals(View.GONE, badge(recent).visibility)
        assertEquals(View.VISIBLE, kind(recent).visibility)
    }

    @Test fun unavailableVideoShowsItsTypeOnceAndKeepsKnownDurationAndAttention() {
        val missing = item("failed")
        val recent = tile(); recent.bind(missing, 200)
        settle { recent.image.drawable != null && clock(recent).text == "1:23" }
        assertNull(recent.image.getTag(R.id.photo_transition_ready))
        assertEquals(ImageView.ScaleType.CENTER, recent.image.scaleType)
        assertEquals(View.GONE, kind(recent).visibility)
        assertEquals(View.VISIBLE, clock(recent).visibility)
        assertEquals(View.VISIBLE, badge(recent).visibility)
    }

    @Test fun recentlyReceivedIncludesSavingAndAttentionWithoutImplyingPublication() {
        val saving = item("pending"); val failed = item("failed"); val saved = item("complete")
        val receiving = item("pending").copy(receipt = "receiving")
        assertEquals(listOf(saving, failed, saved), recentlyReceivedPhotos(listOf(receiving, saving, failed, saved)))
        assertEquals(listOf(PhotoMark.PENDING, PhotoMark.NEEDS_YOU, PhotoMark.NONE),
            recentlyReceivedPhotos(listOf(saving, failed, saved)).map { it.mark })
    }
}
