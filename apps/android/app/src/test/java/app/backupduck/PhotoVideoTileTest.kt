package app.backupduck

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.os.CancellationSignal
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.lifecycle.lifecycleScope
import java.util.UUID
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Job
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

/** Production RecyclerView holders, synthetic media only; no activity/network/service startup. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29], application = Application::class, qualifiers = "w411dp-h731dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PhotoVideoTileTest {
    private val activity = Robolectric.buildActivity(MainActivity::class.java).get()
    private lateinit var images: PhotoImages
    private lateinit var adapter: PhotoAdapter
    private val holders = mutableListOf<PhotoAdapter.TileHolder>()
    private val prefix = UUID.randomUUID().toString()
    private fun item(suffix: String, kind: String = "video", received: Boolean = true) = HistoryItem(1, "$prefix-$suffix", "synthetic.mp4", kind,
        1, 1, if (received) "received" else "receiving", if (received) "complete" else "pending", null, false)
    @Before fun prepare() {
        activity.setTheme(R.style.AppTheme)
        PhotoImages.clearCache()
        ReceiverEnvironment.allowsPhotoMotion = false
        ReceiverEnvironment.previewImage = { _, width, height -> Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.DKGRAY) } }
        images = PhotoImages(activity)
        adapter = PhotoAdapter(activity, images, { _, _ -> }, { _, _ -> }, ReceivedPhotosPage.Actions({}, {}, {}, { _, done -> done(true) }, {}))
    }
    @After fun cleanup() {
        holders.forEach { it.cancel() }
        activity.lifecycleScope.cancel()
        ReceiverEnvironment.previewImage = null; ReceiverEnvironment.videoDuration = null
        ReceiverEnvironment.allowsPhotoMotion = true; PhotoImages.clearCache()
    }
    private fun holder() = (adapter.onCreateViewHolder(FrameLayout(activity), 5) as PhotoAdapter.TileHolder).also(holders::add)
    private fun finish(condition: () -> Boolean) {
        val deadline = System.nanoTime() + 10_000_000_000L
        while (!condition() && System.nanoTime() < deadline) { shadowOf(Looper.getMainLooper()).idle(); Thread.sleep(1) }
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue("Visible metadata must settle", condition())
    }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
    private fun duration(holder: PhotoAdapter.TileHolder) = descendants(holder.itemView).filterIsInstance<TextView>().single()

    @Test fun thumbnailMemoryHitStillLoadsDurationAndAccessibleDescription() {
        val item = item("cached")
        val size = (activity.resources.displayMetrics.widthPixels / 4).coerceIn(160, 384)
        val imageJob: Job = images.load(item, size, size, CancellationSignal()) {}
        finish { imageJob.isCompleted }
        val cached = images.cached(item, size, size)
        assertNotNull(cached)
        ReceiverEnvironment.previewImage = { _, _, _ -> error("A tile memory hit must not decode") }
        var reads = 0
        ReceiverEnvironment.videoDuration = { _, _ -> reads++; 3_723_456 }
        val holder = holder(); holder.bind(item)
        finish { duration(holder).text.toString() == "1h02" }
        assertEquals(1, reads)
        assertTrue(holder.itemView.contentDescription.toString().contains("1:02:03.456"))
        assertEquals(View.VISIBLE, duration(holder).visibility)
        assertSame(cached, images.cached(item, size, size))
    }

    @Test fun unavailablePosterDoesNotHideKnownDurationOrInventUnknownValue() {
        ReceiverEnvironment.videoDuration = { item, _ -> if (item.id.endsWith("known")) 83_000 else null }
        val known = holder(); known.bind(item("known", received = false))
        finish { duration(known).text.toString() == "1:23" && known.image.drawable != null }
        assertEquals(View.VISIBLE, duration(known).visibility)
        assertNull(known.image.getTag(R.id.photo_transition_ready))
        val unknown = holder(); unknown.bind(item("missing", received = false))
        finish { unknown.image.drawable != null }
        assertEquals(View.GONE, duration(unknown).visibility)
        assertFalse(unknown.itemView.contentDescription.toString().contains("0:00"))
    }

    @Test fun recyclingCancelsIndependentMetadataAndNeverPaintsTheNextAsset() {
        val entered = CountDownLatch(1); val release = CountDownLatch(1)
        ReceiverEnvironment.videoDuration = { _, _ -> entered.countDown(); check(release.await(5, TimeUnit.SECONDS)); 83_000 }
        val holder = holder(); holder.bind(item("first"))
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        holder.bind(item("second", kind = "photo"))
        release.countDown()
        finish { holder.image.getTag(R.id.photo_transition_ready) == item("second").id }
        assertEquals(View.GONE, duration(holder).visibility)
        assertFalse(holder.itemView.contentDescription.toString().contains("1:23"))
        assertFalse(holder.itemView.contentDescription.toString().contains("Video"))
    }

    @Test fun compactDurationFitsSelectingAndBrowsingAtDefaultAndLargerFonts() {
        val report = File("build/reports/video-duration-tiles").apply { mkdirs() }
        val observations = mutableListOf<String>()
        val clockValues = listOf(754_000L, 3_723_000L, 36_723_000L, 360_754_567L)
        for (scale in listOf(1f, 1.15f)) {
            activity.resources.displayMetrics.scaledDensity = activity.resources.displayMetrics.density * scale
            ReceiverEnvironment.videoDuration = { item, _ -> clockValues[item.id.substringAfterLast('-').toInt()] }
            val size = activity.dp(103)
            val output = Bitmap.createBitmap(size * 4, size * 3, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val initialLeft = mutableMapOf<Int, Int>()
            for (row in 0..2) {
                val tiles = clockValues.indices.map { n -> holder().also { it.bind(item("composition-$row-$n")) } }
                finish { tiles.all { duration(it).visibility == View.VISIBLE && it.image.getTag(R.id.photo_transition_ready) != null } }
                tiles.forEachIndexed { index, tile ->
                    val selection = tile.itemView.findViewWithTag<NativePhotoSelectionMark>("photo-selection")
                    selection.bind(selected = row == 2, selecting = row > 0)
                    tile.itemView.measure(View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY))
                    tile.itemView.layout(0, 0, size, size)
                    val text = duration(tile)
                    val textBounds = Rect(0, 0, text.width, text.height)
                    (tile.itemView as ViewGroup).offsetDescendantRectToMyCoords(text, textBounds)
                    assertEquals(videoDurationLabel(clockValues[index]), text.text.toString())
                    assertEquals(0, text.layout.getEllipsisCount(0))
                    assertEquals(size, tile.itemView.height)
                    if (row == 0) initialLeft[index] = textBounds.left
                    else {
                        assertTrue("Duration must not overlap the selection mark: font=$scale clock=${text.text}", textBounds.left >= selection.right)
                        assertEquals("Selection cannot move duration", initialLeft[index], textBounds.left)
                    }
                    assertTrue(tile.itemView.contentDescription.toString().contains(photoDuration(clockValues[index])))
                    observations.add("font=$scale row=$row clock=${text.text} text=$textBounds selectionRight=${selection.right} clearance=${textBounds.left-selection.right} width=$size")
                    canvas.save(); canvas.translate((index * size).toFloat(), (row * size).toFloat())
                    canvas.drawRect(0f, 0f, size.toFloat(), size.toFloat(), android.graphics.Paint().apply { color = Color.DKGRAY })
                    tile.itemView.draw(canvas); canvas.restore()
                }
            }
            File(report, "compact-font-$scale.png").outputStream().use { output.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        File(report, "compact-layout.txt").writeText(observations.joinToString("\n"))
    }
}
