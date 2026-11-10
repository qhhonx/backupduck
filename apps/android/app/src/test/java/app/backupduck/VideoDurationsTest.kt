package app.backupduck

import android.app.Application
import android.content.Context
import android.content.ContentProvider
import android.content.ContentValues
import android.content.pm.ProviderInfo
import android.database.Cursor
import android.database.MatrixCursor
import android.database.sqlite.SQLiteException
import android.content.res.Configuration
import android.net.Uri
import android.os.CancellationSignal
import android.os.OperationCanceledException
import android.provider.MediaStore
import java.util.UUID
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowContentResolver

class DurationIndexProvider : ContentProvider() {
    val entered = CountDownLatch(2)
    val release = CountDownLatch(1)
    val queries = AtomicInteger()
    var waitForCancellation = false
    val cancellations = AtomicInteger()
    override fun onCreate() = true
    override fun getType(uri: Uri) = "video/mp4"
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, args: Array<out String>?, sort: String?): Cursor {
        queries.incrementAndGet(); entered.countDown(); check(release.await(5, TimeUnit.SECONDS))
        return MatrixCursor(arrayOf(MediaStore.Video.Media.DURATION)).apply { addRow(arrayOf<Any>(83_000L)) }
    }
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, args: Array<out String>?, sort: String?, cancellationSignal: CancellationSignal?): Cursor {
        if (!waitForCancellation) return query(uri, projection, selection, args, sort)
        val cancelled = CountDownLatch(1)
        cancellationSignal?.setOnCancelListener { cancellations.incrementAndGet(); cancelled.countDown() }
        try {
            queries.incrementAndGet(); entered.countDown()
            check(cancelled.await(5, TimeUnit.SECONDS)) { "Stopped service must cancel the media-index query" }
            cancellationSignal?.throwIfCanceled()
            error("Cancelled query cannot return metadata")
        } finally { cancellationSignal?.setOnCancelListener(null) }
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = error("Read only fixture")
    override fun delete(uri: Uri, selection: String?, args: Array<out String>?) = error("Read only fixture")
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<out String>?) = error("Read only fixture")
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29], application = Application::class)
class VideoDurationsTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val name = "duration-${UUID.randomUUID()}.db"
    private val stores = mutableListOf<VideoDurationStore>()
    private fun store(limit: Int = 20_000) = VideoDurationStore(context, name, limit).also(stores::add)
    private fun item(id: String = "video") = HistoryItem(1, id, "$id.mp4", "video", 1, 1,
        "received", "complete", null, false)
    @After fun cleanup() { stores.forEach { it.close() }; context.deleteDatabase(name); ReceiverEnvironment.videoDuration = null }

    @Test fun positiveObservationSurvivesRestartAndCopyRemovalWithoutReadingMedia() = runBlocking {
        val original = store()
        val first = VideoDurations(original, { _, _ -> 83_456 })
        assertEquals(83_456L, first.read(item(), CancellationSignal()))
        original.close()
        val restarted = VideoDurations(store(), { _, _ -> error("Copy was removed") })
        assertEquals(83_456L, restarted.read(item().copy(originalsReleased = true), CancellationSignal()))
        assertEquals(83_456L, restarted.cached(item()))
        assertNull(restarted.cached(item("different-core-asset")))
    }

    @Test fun unknownExpiresAndRetriesOnStateChangeWithoutPersistingZero() = runBlocking {
        var now = 0L
        var reads = 0
        val disk = store()
        val reader = VideoDurations(disk, { _, _ -> reads++; if (reads < 3) null else 1_000 }, { now })
        val pending = item().copy(processing = "pending")
        assertNull(reader.read(pending, CancellationSignal()))
        assertNull(reader.read(pending, CancellationSignal()))
        assertEquals(1, reads)
        assertNull(reader.read(item(), CancellationSignal()))
        assertEquals(2, reads)
        now = 30_001
        assertEquals(1_000L, reader.read(item(), CancellationSignal()))
        disk.save("zero", 0); disk.save("negative", -1)
        assertNull(disk.read("zero")); assertNull(disk.read("negative"))
        assertNull(reader.read(item().copy(kind = "motion"), CancellationSignal()))
        assertEquals(3, reads)
    }

    @Test fun cancellationDoesNotPublishOrRetainLateMetadata() = runBlocking {
        val entered = CountDownLatch(1); val release = CountDownLatch(1)
        val disk = store()
        val reader = VideoDurations(disk, { _, _ -> entered.countDown(); check(release.await(5, TimeUnit.SECONDS)); 83_000 })
        val signal = CancellationSignal()
        val result = async(Dispatchers.Default) { runCatching { reader.read(item(), signal) } }
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        signal.cancel(); release.countDown()
        assertTrue(result.await().exceptionOrNull() is OperationCanceledException)
        assertNull(reader.cached(item())); assertNull(disk.read(item().id))
    }

    @Test fun mediaReadsAreLimitedToTwoAndCancelledWaitersNeverRead() = runBlocking {
        val entered = CountDownLatch(2); val release = CountDownLatch(1)
        val active = AtomicInteger(); val maximum = AtomicInteger(); val calls = AtomicInteger()
        val reader = VideoDurations(store(), { _, _ ->
            calls.incrementAndGet()
            val concurrent = active.incrementAndGet(); maximum.updateAndGet { maxOf(it, concurrent) }
            entered.countDown(); check(release.await(5, TimeUnit.SECONDS)); active.decrementAndGet(); 1_000
        })
        val jobs = (0..1).map { index -> async(Dispatchers.Default) { reader.read(item("v$index"), CancellationSignal()) } }
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        val signal = CancellationSignal()
        val waiting = async(Dispatchers.Default) { runCatching { reader.read(item("cancelled"), signal) } }
        signal.cancel(); release.countDown()
        jobs.forEach { assertEquals(1_000L, it.await()) }
        assertTrue(waiting.await().exceptionOrNull() is OperationCanceledException)
        assertEquals(2, maximum.get()); assertEquals(2, calls.get())
    }

    @Test fun diskAndMemoryHaveIndependentCapsAndEvictedObservationsStayUnknown() = runBlocking {
        val disk = store(3)
        disk.save("old", 1); disk.save("middle", 2); disk.save("recent", 3)
        // Stable explicit times make the eviction fixture independent of wall-clock resolution.
        disk.writableDatabase.execSQL("UPDATE durations SET last_used=CASE asset_id WHEN 'old' THEN 1 WHEN 'middle' THEN 2 ELSE 3 END")
        disk.read("old")
        disk.save("new", 4)
        assertNull(disk.read("middle")); assertEquals(1L, disk.read("old"))
        assertEquals(3L, android.database.DatabaseUtils.queryNumEntries(disk.readableDatabase, "durations"))
        val reader = VideoDurations(disk, { _, _ -> null })
        repeat(257) { reader.remember("memory-$it", it + 1L) }
        assertNull(reader.cached(item("memory-0")))
        assertEquals(257L, reader.cached(item("memory-256")))
        assertNull(reader.read(item("middle"), CancellationSignal()))
    }

    @Test fun compactClockUsesApprovedUnitsAndRoundingWithoutOverflow() {
        assertNull(videoDurationLabel(null)); assertNull(videoDurationLabel(0)); assertNull(videoDurationLabel(-1))
        assertEquals("0:00", videoDurationLabel(400))
        assertEquals("0:01", videoDurationLabel(500))
        assertEquals("1:23", videoDurationLabel(83_000))
        assertEquals("1:00", videoDurationLabel(59_500))
        assertEquals("59:59", videoDurationLabel(3_599_499))
        assertEquals("1h00", videoDurationLabel(3_599_500))
        assertEquals("1h02", videoDurationLabel(3_723_000))
        assertEquals("99h59", videoDurationLabel(359_999_499))
        assertEquals("100h", videoDurationLabel(359_999_500))
        assertEquals("100h", videoDurationLabel(360_754_567))
        assertEquals("2562047788015h", videoDurationLabel(Long.MAX_VALUE))
    }

    @Test fun accessibilityRetainsFullDurationInEnglishAndChinese() {
        for (locale in listOf(Locale.US, Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val description = tileDescription(localized, item(), 360_754_567)
            assertTrue(description, description.contains("100:12:34.567"))
            assertFalse(description, description.contains("100h"))
            assertTrue(description, description.contains(if (locale == Locale.US) "Video" else "视频"))
            assertFalse(tileDescription(localized, item(), null).contains("0:00"))
            assertFalse(tileDescription(localized, item(), 0).contains("0:00"))
        }
    }

    @Test fun failedCommitAfterEvictionCannotLeaveAnUndercountedCache() {
        val disk = store(200)
        repeat(200) { disk.save("original-$it", it + 1L) }
        val db = disk.writableDatabase
        db.setForeignKeyConstraintsEnabled(true)
        db.execSQL("CREATE TABLE duration_parents (id INTEGER PRIMARY KEY)")
        db.execSQL("ALTER TABLE durations ADD COLUMN parent_id INTEGER REFERENCES duration_parents(id) DEFERRABLE INITIALLY DEFERRED")
        db.execSQL("CREATE TRIGGER fail_duration_commit AFTER INSERT ON durations WHEN NEW.asset_id='rollback' BEGIN UPDATE durations SET parent_id=999 WHERE asset_id=NEW.asset_id; END")
        // The deferred constraint fails at COMMIT, after eviction and insertion both succeeded.
        assertThrows(SQLiteException::class.java) { disk.save("rollback", 1_000) }
        val restored = disk.writableDatabase
        assertEquals(200L, android.database.DatabaseUtils.queryNumEntries(restored, "durations"))
        assertNull(disk.read("rollback"))
        restored.execSQL("DROP TRIGGER fail_duration_commit")
        disk.save("recovered", 2_000)
        assertTrue(android.database.DatabaseUtils.queryNumEntries(restored, "durations") <= 200)
        assertEquals(2_000L, disk.read("recovered"))
    }

    @Test fun failedAgeUpdateCannotHideARetainedDuration() = runBlocking {
        val disk = store()
        disk.save("retained", 83_456)
        disk.writableDatabase.execSQL("CREATE TRIGGER fail_duration_touch BEFORE UPDATE ON durations BEGIN SELECT RAISE(ABORT, 'synthetic storage write failure'); END")
        val reader = VideoDurations(disk, { _, _ -> error("The gallery copy is gone") })
        assertEquals(83_456L, reader.read(item("retained"), CancellationSignal()))
        assertEquals(83_456L, reader.cached(item("retained")))
    }

    @Test fun publicationHintsReturnWithoutWaitingAndNeverAccumulateABacklog() = runBlocking {
        val provider = DurationIndexProvider().apply { attachInfo(context, ProviderInfo().apply { authority = "media" }) }
        ShadowContentResolver.registerProviderInternal("media", provider)
        val disk = store()
        val reader = VideoDurations(disk, { _, _ -> null })
        val failures = CopyOnWriteArrayList<Throwable>()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO + CoroutineExceptionHandler { _, error -> failures.add(error) })
        try {
            repeat(50) { reader.published(scope, context, "published-$it", "video", "content://media/external/video/media/$it") }
            assertTrue("Publication returns while index reads are blocked", provider.entered.await(5, TimeUnit.SECONDS))
            assertEquals(2, provider.queries.get())
            provider.release.countDown()
            scope.coroutineContext[kotlinx.coroutines.Job]!!.children.toList().forEach { it.join() }
            assertEquals(2, provider.queries.get())
            assertEquals(83_000L, disk.read("published-0")); assertEquals(83_000L, disk.read("published-1"))
            assertNull(disk.read("published-2"))
            assertTrue(failures.toString(), failures.isEmpty())
        } finally { provider.release.countDown(); scope.cancel() }
    }

    private suspend fun assertBothReadersAvailable() {
        val entered = CountDownLatch(2); val release = CountDownLatch(1)
        val reader = VideoDurations(store(), { _, _ -> entered.countDown(); check(release.await(5, TimeUnit.SECONDS)); 1_000 })
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val jobs = (0..1).map { n -> scope.async { reader.read(item("reused-$n"), CancellationSignal()) } }
            assertTrue("Both metadata permits must be reusable", entered.await(5, TimeUnit.SECONDS))
            release.countDown()
            withTimeout(5_000) { jobs.forEach { assertEquals(1_000L, it.await()) } }
        } finally { release.countDown(); scope.cancel() }
    }

    @Test fun alreadyStoppedServiceCannotLeakPublicationReaderPermits() = runBlocking {
        val reader = VideoDurations(store(), { _, _ -> null })
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        scope.cancel()
        repeat(50) { reader.published(scope, context, "never-started-$it", "video", "content://media/external/video/media/$it") }
        scope.coroutineContext[kotlinx.coroutines.Job]!!.join()
        assertBothReadersAvailable()
    }

    @Test fun stoppingServiceCancelsProviderAndReturnsBothPublicationPermits() = runBlocking {
        val provider = DurationIndexProvider().apply {
            waitForCancellation = true
            attachInfo(context, ProviderInfo().apply { authority = "media" })
        }
        ShadowContentResolver.registerProviderInternal("media", provider)
        val disk = store()
        val reader = VideoDurations(disk, { _, _ -> null })
        val failures = CopyOnWriteArrayList<Throwable>()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO + CoroutineExceptionHandler { _, error -> failures.add(error) })
        try {
            repeat(2) { reader.published(scope, context, "cancelled-$it", "video", "content://media/external/video/media/$it") }
            assertTrue(provider.entered.await(5, TimeUnit.SECONDS))
            withTimeout(5_000) { scope.coroutineContext[kotlinx.coroutines.Job]!!.cancelAndJoin() }
            assertEquals(2, provider.cancellations.get())
            assertNull(disk.read("cancelled-0")); assertNull(disk.read("cancelled-1"))
            assertTrue("Android cancellation must not be an uncaught service error: $failures", failures.isEmpty())
            assertBothReadersAvailable()
        } finally { provider.release.countDown(); scope.cancel() }
    }
}
