package app.backupduck

import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceivedPhotosTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private fun at(day: Int, hour: Int) = LocalDateTime.of(2026, 10, day, hour, 0).atZone(zone).toInstant().toEpochMilli()
    private val now = at(18, 15)

    private fun item(cursor: Long, processing: String = "complete", error: String? = null, receipt: String = "received",
        received: Long? = at(18, 10), published: Long? = if (processing == "complete") at(18, 11) else null, sender: String = "Lin's iPhone") =
        HistoryItem(cursor, "id-$cursor", "IMG_$cursor.HEIC", "photo", 100, if (receipt == "received") 100 else 40, receipt,
            processing, error, false, senderNames = sender, receivedAtMs = received, publishedAtMs = published)

    @Test fun marksFollowTheGalleryState() {
        assertEquals(PhotoMark.NONE, item(1).mark)
        assertEquals(PhotoMark.PENDING, item(2, processing = "pending").mark)
        assertEquals(PhotoMark.PENDING, item(3, processing = "not_requested", receipt = "receiving", received = null).mark)
        assertEquals(PhotoMark.NEEDS_YOU, item(4, processing = "failed", error = "gallery_write_failed").mark)
    }

    @Test fun causesSplitLivePhotosFromOtherSaveFailures() {
        assertEquals(PhotoCause.LIVE_PHOTO, item(1, processing = "failed", error = "conversion_required").cause)
        assertEquals(PhotoCause.NOT_SAVED, item(2, processing = "failed", error = "storage").cause)
        assertEquals(PhotoCause.NOT_SAVED, item(3, processing = "failed").cause)
        assertNull(item(4).cause)
        assertNull(item(5, processing = "pending").cause)
    }

    @Test fun cardsFollowTheContractOrderAndSkipEmptyCauses() {
        val attention = listOf(item(5, processing = "failed", error = "storage"), item(4, processing = "failed", error = "conversion_required"),
            item(3, processing = "failed", error = "storage"), item(2))
        val groups = needsYou(attention, more = true)
        assertEquals(listOf(PhotoCause.LIVE_PHOTO, PhotoCause.NOT_SAVED), groups.map { it.cause })
        assertEquals(listOf(5L, 3L), groups[1].items.map { it.cursor })
        assertTrue(groups.all { it.more })
        assertEquals(listOf(PhotoCause.NOT_SAVED), needsYou(attention.take(1), more = false).map { it.cause })
        assertTrue(needsYou(listOf(item(1)), more = false).isEmpty())
    }

    @Test fun daysUseTheLatestChangeNewestFirst() {
        // Taken long ago but saved today: it belongs under today.
        val items = listOf(item(9, received = at(18, 9)), item(8, received = at(17, 22), published = at(18, 0)),
            item(7, received = at(17, 8), published = at(17, 9)), item(6, received = at(14, 8), published = at(14, 9)))
        val rows = photoRows(items, emptyList(), now, zone, loading = false, failed = false, hasMore = false)
        val days = rows.filterIsInstance<PhotoRow.Day>().map { it.epochDay }
        val today = epochDay(now, zone)
        assertEquals(listOf(today, today - 1, today - 4), days)
        val firstDay = rows.indexOfFirst { it is PhotoRow.Day }
        assertEquals(listOf(9L, 8L), rows.drop(firstDay + 1).takeWhile { it is PhotoRow.Tile }.map { (it as PhotoRow.Tile).item.cursor })
    }

    @Test fun anOutOfOrderSaveMovesIntoItsDayWithoutRepeatingHeaders() {
        // Arrival order 9, 8, 7, but 7 was saved again today after a retry.
        val items = listOf(item(9), item(8, received = at(16, 8), published = at(16, 9)), item(7, received = at(15, 8), published = at(18, 12)))
        val rows = photoRows(items, emptyList(), now, zone, loading = false, failed = false, hasMore = false)
        val days = rows.filterIsInstance<PhotoRow.Day>().map { it.epochDay }
        assertEquals(days.distinct(), days)
        assertEquals(listOf(9L, 7L, 8L), rows.filterIsInstance<PhotoRow.Tile>().map { it.item.cursor })
    }

    @Test fun aPhotoStillArrivingBelongsToToday() {
        val rows = photoRows(listOf(item(3, processing = "not_requested", receipt = "receiving", received = null, published = null)),
            emptyList(), now, zone, loading = false, failed = false, hasMore = false)
        assertEquals(epochDay(now, zone), rows.filterIsInstance<PhotoRow.Day>().single().epochDay)
    }

    @Test fun sendersAppearOnDaysOnlyWhenMoreThanOneSenderAppears() {
        val one = photoRows(listOf(item(2), item(1)), emptyList(), now, zone, false, false, false)
        assertTrue(one.filterIsInstance<PhotoRow.Day>().all { it.senders.isEmpty() })
        val two = photoRows(listOf(item(3), item(2, sender = "Lin's MacBook Air"), item(1, received = at(16, 8), published = at(16, 9))),
            emptyList(), now, zone, false, false, false)
        assertEquals(listOf(listOf("Lin's iPhone", "Lin's MacBook Air"), listOf("Lin's iPhone")), two.filterIsInstance<PhotoRow.Day>().map { it.senders })
    }

    @Test fun needsYouComesBeforeTheTimelineAndStatusRowsAreExclusive() {
        val failed = item(4, processing = "failed", error = "storage")
        val rows = photoRows(listOf(failed, item(3)), needsYou(listOf(failed), false), now, zone, loading = true, failed = false, hasMore = true)
        assertEquals(PhotoRow.Scope, rows[0])
        assertEquals(PhotoRow.NeedsHeader, rows[1])
        assertTrue(rows[2] is PhotoRow.Cause)
        assertEquals(PhotoRow.TimelineHeader, rows[3])
        assertEquals(PhotoRow.Status(StatusKind.LOADING), rows.last())
        assertFalse(rows.contains(PhotoRow.CloudFooter))
        assertEquals(listOf(PhotoRow.Status(StatusKind.EMPTY)), photoRows(emptyList(), emptyList(), now, zone, false, false, false))
        assertEquals(listOf(PhotoRow.Status(StatusKind.FAILED)), photoRows(emptyList(), emptyList(), now, zone, true, true, false))
        assertFalse(photoRows(listOf(item(1)), emptyList(), now, zone, true, false, false).any { it is PhotoRow.Status })
    }

    @Test fun theCloudFooterEndsTheLastPageOnly() {
        assertEquals(PhotoRow.CloudFooter, photoRows(listOf(item(2), item(1)), emptyList(), now, zone, false, false, false).last())
        assertFalse(photoRows(listOf(item(1)), emptyList(), now, zone, false, false, true).contains(PhotoRow.CloudFooter))
        assertFalse(photoRows(emptyList(), emptyList(), now, zone, false, false, false).contains(PhotoRow.CloudFooter))
    }

    @Test fun rowKeysAreStableAndUnique() {
        val failed = item(4, processing = "failed", error = "conversion_required")
        val items = listOf(failed, item(3), item(2, received = at(16, 8), published = at(16, 9)))
        val rows = photoRows(items, needsYou(listOf(failed, item(5, processing = "failed")), true), now, zone, true, false, true)
        assertEquals(rows.size, rows.map { it.key }.distinct().size)
        assertEquals(rows.map { it.key }, photoRows(items, needsYou(listOf(failed, item(5, processing = "failed")), true), now, zone, true, false, true).map { it.key })
    }

    @Test fun liveProgressAdvancesWithoutUndoingASavedPhoto() {
        val arriving = item(1, processing = "not_requested", receipt = "receiving", received = null)
        val live = arriving.withLive(ReceiverByteProgress(confirmed = 100, total = 100, received = true, processing = "pending"))
        assertEquals("received", live.receipt)
        assertEquals(PhotoMark.PENDING, live.mark)
        assertEquals(PhotoMark.NONE, item(2).withLive(ReceiverByteProgress(100, 100, true, "failed", "storage")).mark)
        assertEquals(PhotoMark.NEEDS_YOU, arriving.withLive(ReceiverByteProgress(100, 100, true, "failed", "storage")).mark)
    }

    @Test fun scopeNamesTheSenderOnlyWhenItIsTheOnlyOne() {
        val items = listOf(item(2), item(1))
        assertEquals("Lin's iPhone", photoScope(HistoryCounts(1284, 1280, 4), items, 0, listOf("Lin's iPhone")).sender)
        assertNull(photoScope(HistoryCounts(1284, 1280, 4), items, 0, listOf("Lin's iPhone", "Lin's MacBook Air")).sender)
        assertNull(photoScope(null, items + item(0, sender = "Lin's MacBook Air"), 0, emptyList()).sender)
        assertTrue(photoScope(HistoryCounts(2, 2, 0), items, 0, emptyList()).allSaved)
        assertFalse(photoScope(HistoryCounts(0, 0, 0), emptyList(), 0, emptyList()).allSaved)
    }
}
