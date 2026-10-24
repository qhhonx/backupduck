package app.backupduck

import java.time.Instant
import java.time.ZoneId

/**
 * What the Received photos page shows (design/records.md): a tile mark per
 * photo, problems grouped by cause, and the timeline grouped by the day of each
 * photo's latest change. Pure, so the rules are unit tested.
 */
internal enum class PhotoMark { NONE, PENDING, NEEDS_YOU }

/** Causes the Pixel can act on, in the order the page lists them. */
internal enum class PhotoCause { LIVE_PHOTO, NOT_SAVED }

internal val HistoryItem.mark: PhotoMark get() = when {
    processing == "complete" -> PhotoMark.NONE
    processing == "failed" -> PhotoMark.NEEDS_YOU
    else -> PhotoMark.PENDING
}

internal val HistoryItem.cause: PhotoCause? get() = when {
    processing != "failed" -> null
    processingError == "conversion_required" -> PhotoCause.LIVE_PHOTO
    else -> PhotoCause.NOT_SAVED
}

/** The last time anything happened to the photo, when the core recorded it. */
internal val HistoryItem.latestChangeMs: Long? get() = stateChangedAtMs ?: listOfNotNull(publishedAtMs, receivedAtMs).maxOrNull()

internal val HistoryItem.senders: List<String> get() = senderNames.split(" · ").map { it.trim() }.filter { it.isNotEmpty() }

/** Applies live progress the core has not paged yet, as the item rows do. */
internal fun HistoryItem.withLive(live: ReceiverByteProgress?): HistoryItem {
    if (live == null) return this
    val phase = if (processing == "complete") "complete" else live.processing ?: processing
    return copy(receipt = if (receipt == "received" || live.received) "received" else receipt,
        confirmedBytes = maxOf(confirmedBytes, live.confirmed).coerceAtMost(totalBytes), processing = phase,
        processingError = if (phase == "complete") null else if (live.processing != null) live.error else processingError)
}

/**
 * One problem card. [items] are the loaded attention items of this cause;
 * [more] is true when the core has more attention items than it returned, so
 * the count is a lower bound ("100+").
 */
internal data class CauseGroup(val cause: PhotoCause, val items: List<HistoryItem>, val more: Boolean)

internal fun needsYou(attention: List<HistoryItem>, more: Boolean): List<CauseGroup> =
    PhotoCause.values().mapNotNull { cause ->
        attention.filter { it.cause == cause }.takeIf { it.isNotEmpty() }?.let { CauseGroup(cause, it, more) }
    }

/** A row of the page's grid. Everything except [Tile] spans the full width. */
internal sealed class PhotoRow {
    abstract val key: Long
    object Scope : PhotoRow() { override val key = -1L }
    object NeedsHeader : PhotoRow() { override val key = -2L }
    data class Cause(val group: CauseGroup) : PhotoRow() { override val key = -10L - group.cause.ordinal }
    object TimelineHeader : PhotoRow() { override val key = -3L }
    /** [epochDay] is the local day; [senders] is empty unless more than one sender appears. */
    data class Day(val epochDay: Long, val senders: List<String>) : PhotoRow() { override val key = if (epochDay == Long.MIN_VALUE) Long.MIN_VALUE else -1_000L - epochDay }
    data class Tile(val item: HistoryItem) : PhotoRow() { override val key = item.cursor }
    data class Status(val kind: StatusKind) : PhotoRow() { override val key = -4L }
    /** Said once for the whole page: BackupDuck cannot see Google Photos' cloud backup. */
    object CloudFooter : PhotoRow() { override val key = -5L }
}

internal enum class StatusKind { LOADING, FAILED, EMPTY }

internal fun epochDay(ms: Long, zone: ZoneId): Long = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate().toEpochDay()

/**
 * The page's rows. The core pages a fixed snapshot by latest change, newest first, with a
 * stable row ID tie-breaker. Each photo goes under that change’s local day;
 * order within a day is the exact core order across every loaded page. A legacy photo with no recorded change time belongs to the final unknown-date
 * group; browsing must not invent a change time. The Google Photos footer closes the last page.
 */
internal fun photoRows(items: List<HistoryItem>, attention: List<CauseGroup>, nowMs: Long, zone: ZoneId,
    loading: Boolean, failed: Boolean, hasMore: Boolean): List<PhotoRow> {
    val rows = mutableListOf<PhotoRow>()
    if (items.isEmpty()) {
        rows += PhotoRow.Status(when { failed -> StatusKind.FAILED; loading -> StatusKind.LOADING; else -> StatusKind.EMPTY })
        return rows
    }
    rows += PhotoRow.Scope
    if (attention.isNotEmpty()) {
        rows += PhotoRow.NeedsHeader
        attention.forEach { rows += PhotoRow.Cause(it) }
        rows += PhotoRow.TimelineHeader
    }
    val today = epochDay(nowMs, zone)
    val manySenders = items.flatMap { it.senders }.distinct().size > 1
    items.groupBy { item -> item.latestChangeMs?.let { epochDay(it, zone) }?.coerceAtMost(today) ?: Long.MIN_VALUE }
        .toSortedMap(compareByDescending { it })
        .forEach { (day, photos) ->
            rows += PhotoRow.Day(day, if (manySenders) photos.flatMap { it.senders }.distinct() else emptyList())
            photos.forEach { rows += PhotoRow.Tile(it) }
        }
    if (hasMore && (loading || failed)) rows += PhotoRow.Status(if (failed) StatusKind.FAILED else StatusKind.LOADING)
    // The footer belongs to the end of the page, so it waits until every page is loaded.
    if (!hasMore) rows += PhotoRow.CloudFooter
    return rows
}

/** How the scope line reads: every photo saved, or how many of them are. */
internal data class PhotoScope(val total: Int, val saved: Int, val sender: String?, val pending: Int = 0) {
    val allSaved get() = total > 0 && saved >= total
}

/**
 * The count covers every photo this Pixel holds. It names the sender only when
 * one device sent everything loaded and no other device is paired, so a count
 * never claims a single source it cannot know.
 */
internal fun photoScope(counts: HistoryCounts?, items: List<HistoryItem>, fallbackTotal: Int, paired: List<String>): PhotoScope {
    val senders = items.flatMap { it.senders }.distinct()
    val sender = senders.singleOrNull()?.takeIf { paired.isEmpty() || paired == listOf(it) }
    return PhotoScope(counts?.total ?: fallbackTotal, counts?.published ?: items.count { it.processing == "complete" }, sender,
        counts?.let { (it.total - it.published - it.failed).coerceAtLeast(0) }
            ?: items.count { it.processing in setOf("pending", "running") })
}
