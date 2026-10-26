package app.backupduck

import android.app.Application
import android.content.ContentProvider
import android.content.ContentValues
import android.content.pm.ProviderInfo
import android.database.Cursor
import android.database.MatrixCursor
import android.provider.MediaStore
import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import android.os.CancellationSignal
import android.os.Looper
import android.os.OperationCanceledException
import android.widget.ImageView
import androidx.appcompat.app.AppCompatActivity
import java.io.File
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.Job
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
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowContentResolver
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration

/** Synthetic provider thumbnail: real Android bitmaps, no gallery or native core. */
@Implements(ContentResolver::class)
class TileThumbnailResolver : ShadowContentResolver() {
    companion object {
        var reads = AtomicInteger()
        var fail = false
    }
    @Implementation
    protected fun loadThumbnail(uri: Uri, size: android.util.Size, signal: CancellationSignal?): Bitmap {
        signal?.throwIfCanceled()
        reads.incrementAndGet()
        if (fail) throw IOException("Synthetic unreadable thumbnail")
        return Bitmap.createBitmap(size.width, size.height, Bitmap.Config.ARGB_8888)
    }
}

class TileEvidenceProvider : ContentProvider() {
    var queries = 0
    override fun onCreate() = true
    override fun getType(uri: Uri) = "image/jpeg"
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
        args: Array<out String>?, sort: String?): Cursor {
        queries++
        return MatrixCursor(arrayOf(MediaStore.MediaColumns.MIME_TYPE, MediaStore.MediaColumns.IS_PENDING,
            MediaStore.MediaColumns.SIZE)).apply { addRow(arrayOf<Any>("image/jpeg", 0, 100)) }
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = error("Read only fixture")
    override fun delete(uri: Uri, selection: String?, args: Array<out String>?) = error("Read only fixture")
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<out String>?) = error("Read only fixture")
}

class TileTestActivity : AppCompatActivity() {
    override fun onCreate(state: android.os.Bundle?) {
        setTheme(R.style.AppTheme)
        super.onCreate(state)
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29], application = Application::class, shadows = [TileThumbnailResolver::class])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PhotoImagesTest {
    private val controller by lazy { Robolectric.buildActivity(TileTestActivity::class.java).setup() }
    private val activity get() = controller.get()
    private fun item(id: String = "tile-test") = HistoryItem(1, id, "synthetic.jpg", "photo", 1, 1,
        "received", "complete", null, false)
    @Before fun prepare() {
        PhotoImages.clearCache()
        TileThumbnailResolver.reads.set(0)
        TileThumbnailResolver.fail = false
        ReceiverEnvironment.previewImage = null
    }
    @After fun cleanup() {
        ReceiverEnvironment.previewImage = null
        ReceiverEnvironment.allowsPhotoMotion = true
        PhotoImages.clearCache()
        activity.filesDir.resolve("receipt-thumbnails").deleteRecursively()
        controller.pause().stop().destroy()
    }
    private fun finish(job: Job) {
        val deadline = System.nanoTime() + 10_000_000_000L
        while (!job.isCompleted && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(1)
        }
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue("Cancellable image job must finish", job.isCompleted)
    }
    private fun receipt(id: String) = Bitmap.createBitmap(320, 320, Bitmap.Config.ARGB_8888).also {
        it.eraseColor(Color.RED)
        ReceiptThumbnails.save(activity, id, it)
    }
    @Test fun receiptPaintsBeforeRefinementAndBothStagesAreCached() {
        val item = item()
        receipt(item.id)
        val events = mutableListOf<String>()
        ReceiverEnvironment.previewImage = { _, _, _ ->
            synchronized(events) { events.add("refinement-read") }
            Bitmap.createBitmap(360, 360, Bitmap.Config.ARGB_8888)
        }
        val images = PhotoImages(activity)
        val shown = mutableListOf<Bitmap>()
        finish(images.load(item, 360, 360, CancellationSignal()) {
            if (it != null) { shown.add(it); synchronized(events) { events.add("paint-${it.width}") } }
        })
        assertEquals(listOf(320, 360), shown.map { it.width })
        assertTrue(events.indexOf("paint-320") < events.indexOf("refinement-read"))
        assertSame(shown.last(), images.cached(item, 360, 360))
        ReceiverEnvironment.previewImage = { _, _, _ -> error("Memory hit must not decode") }
        finish(images.load(item, 360, 360, CancellationSignal()) { assertSame(shown.last(), it) })
        // A different target can reuse the separately cached first stage even after its file is removed.
        activity.filesDir.resolve("receipt-thumbnails/${item.id}.webp").delete()
        val other = mutableListOf<Int>()
        finish(images.load(item, 200, 200, CancellationSignal()) { if (it != null) other.add(it.width) })
        assertEquals(listOf(320), other)
    }
    @Test fun sufficientReceiptSkipsSecondStageAndRemovedCopyRetainsReceipt() {
        val item = item("sufficient")
        receipt(item.id)
        val reads = AtomicInteger()
        ReceiverEnvironment.previewImage = { _, _, _ -> reads.incrementAndGet(); null }
        val images = PhotoImages(activity)
        val small = mutableListOf<Int>()
        finish(images.load(item, 200, 200, CancellationSignal()) { if (it != null) small.add(it.width) })
        assertEquals(listOf(320), small)
        assertEquals(0, reads.get())
        val large = mutableListOf<Int>()
        finish(images.load(item, 360, 360, CancellationSignal()) { if (it != null) large.add(it.width) })
        assertEquals(listOf(320), large)
        assertEquals(1, reads.get())
    }
    @Test fun recycleCancellationAfterReceiptSuppressesRefinement() {
        val item = item("cancelled")
        receipt(item.id)
        ReceiverEnvironment.previewImage = { _, _, _ -> error("Cancelled binding must not refine") }
        val signal = CancellationSignal()
        var paints = 0
        finish(PhotoImages(activity).load(item, 360, 360, signal) { paints++; signal.cancel() })
        assertEquals(1, paints)
    }
    @Test fun smallRequestsUseSystemThumbnailAndViewerUsesOriginal() {
        val file = File(activity.cacheDir, "synthetic-original.png")
        val source = Bitmap.createBitmap(1200, 900, Bitmap.Config.ARGB_8888)
        file.outputStream().use { source.compress(Bitmap.CompressFormat.PNG, 100, it) }
        val copy = GalleryPreviewCopy(Uri.fromFile(file), "image/png", null)
        val small = GalleryPreview.decode(activity, copy, android.util.Size(360, 360), CancellationSignal())
        assertEquals(360, small.width)
        assertEquals(1, TileThumbnailResolver.reads.get())
        val viewer = GalleryPreview.decode(activity, copy, android.util.Size(900, 900), CancellationSignal())
        assertEquals(1200, viewer.width)
        assertEquals(1, TileThumbnailResolver.reads.get())
        TileThumbnailResolver.fail = true
        val fallback = GalleryPreview.decode(activity, copy, android.util.Size(360, 360), CancellationSignal())
        assertEquals(480, fallback.width)
        assertEquals(360, fallback.height)
        val cancelled = CancellationSignal().apply { cancel() }
        assertThrows(OperationCanceledException::class.java) {
            GalleryPreview.decode(activity, copy, android.util.Size(360, 360), cancelled)
        }
        file.delete()
    }
    @Test fun resolvedCopySurvivesRepeatedLoadsAndInvalidatesOnStateChangeOrFailedRead() {
        val provider = TileEvidenceProvider().apply {
            attachInfo(activity, ProviderInfo().apply { authority = "media" })
        }
        ShadowContentResolver.registerProviderInternal("media", provider)
        val item = item("resolved-copy")
        val uri = Uri.parse("content://media/external/images/media/42")
        val first = GalleryPreview.resolve(activity, item, uri, CancellationSignal())
        assertNotNull(first)
        // A cached resolve must return before reaching the native gallery-evidence request.
        assertSame(first, GalleryPreview.resolve(activity, item, null, CancellationSignal()))
        assertEquals(1, provider.queries)
        GalleryPreview.observe(item.copy(processing = "pending"))
        val second = GalleryPreview.resolve(activity, item, uri, CancellationSignal())
        assertNotSame(first, second)
        assertEquals(2, provider.queries)
        TileThumbnailResolver.fail = true
        assertThrows(Exception::class.java) {
            GalleryPreview.decode(activity, second!!, android.util.Size(360, 360), CancellationSignal())
        }
        assertNotNull(GalleryPreview.resolve(activity, item, uri, CancellationSignal()))
        assertEquals(3, provider.queries)
    }
    @Test fun bitmapBudgetUsesMemoryClassWithMinimumAndAllocationAccounting() {
        PhotoImages(activity)
        val field = PhotoImages::class.java.getDeclaredField("nativeCache").apply { isAccessible = true }
        @Suppress("UNCHECKED_CAST")
        val cache = field.get(null) as android.util.LruCache<String, Bitmap>
        val memory = (activity.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager).memoryClass
        assertEquals((memory * 1024 * 1024 / 8).coerceAtLeast(32 * 1024 * 1024), cache.maxSize())
        val bitmap = Bitmap.createBitmap(17, 23, Bitmap.Config.ARGB_8888)
        cache.put("accounting-fixture", bitmap)
        assertEquals(bitmap.allocationByteCount, cache.size())
    }
    @Test fun refinementHasNoBlankFrameAndPreservesPosterContract() {
        val old = Bitmap.createBitmap(20, 20, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.RED) }
        val next = Bitmap.createBitmap(20, 20, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.BLUE) }
        val image = ImageView(activity)
        image.showPhotoBitmap(old)
        image.showPhotoBitmap(next)
        assertTrue(image.drawable is BitmapDrawable)
        fun pixel(): Int {
            val output = Bitmap.createBitmap(20, 20, Bitmap.Config.ARGB_8888)
            image.drawable.setBounds(0, 0, 20, 20)
            image.drawable.draw(Canvas(output))
            return output.getPixel(10, 10)
        }
        assertEquals(Color.RED, pixel())
        ShadowSystemClock.advanceBy(Duration.ofMillis(60))
        val middle = pixel()
        assertEquals(255, Color.alpha(middle))
        assertTrue(Color.red(middle) > 0 && Color.blue(middle) > 0)
        ShadowSystemClock.advanceBy(Duration.ofMillis(60))
        assertEquals(Color.BLUE, pixel())
        ReceiverEnvironment.allowsPhotoMotion = false
        image.showPhotoBitmap(old)
        assertEquals(Color.RED, pixel())
        ReceiverEnvironment.allowsPhotoMotion = true
    }
}
