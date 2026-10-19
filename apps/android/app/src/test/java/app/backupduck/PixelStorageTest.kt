package app.backupduck

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PixelStorageTest {
    private val gb = 1L shl 30

    @Test
    fun otherIsTheUsedSpaceBackupDuckDoesNotAccountFor() {
        val parts = StorageParts(total = 64 * gb, free = 6 * gb, photos = 40 * gb, copies = gb)
        assertEquals(17 * gb, parts.other)
    }

    @Test
    fun otherStaysUnknownUntilEveryPartIsRead() {
        assertNull(StorageParts(64 * gb, 6 * gb, photos = null, copies = gb).other)
        assertNull(StorageParts(64 * gb, 6 * gb, photos = 40 * gb, copies = null).other)
    }

    @Test
    fun otherNeverGoesNegativeWhenReadingsDisagree() {
        // The media index can lag the volume; the bar must not draw a negative part.
        assertEquals(0L, StorageParts(total = 10 * gb, free = 5 * gb, photos = 6 * gb, copies = 0).other)
    }

    @Test
    fun spaceIsLowBelowFifteenPercentFree() {
        assertTrue(DeviceStorage(totalBytes = 100 * gb, freeBytes = 14 * gb).low)
        assertFalse(DeviceStorage(totalBytes = 100 * gb, freeBytes = 15 * gb).low)
        assertFalse(DeviceStorage(totalBytes = 0, freeBytes = 0).low)
    }
}
