package app.backupduck

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CleanupCompletionTest {
    @Test fun recordsOnlyARecognizedCompletionAmount() {
        assertEquals(2_300_000_000L, CleanupCompletion.bytes("You freed up 2.3 GB"))
        assertEquals(734_000_000L, CleanupCompletion.bytes("您已释放 734 MB"))
        assertNull(CleanupCompletion.bytes("Free up 2.3 GB"))
        assertNull(CleanupCompletion.bytes("You freed up 0 GB"))
        assertNull(CleanupCompletion.bytes("You freed up 2,3 GB"))
        assertNull(CleanupCompletion.bytes("You freed up 2.3 GB from account@example.com"))
    }
}
