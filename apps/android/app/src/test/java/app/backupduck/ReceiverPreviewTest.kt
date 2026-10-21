package app.backupduck

import java.io.File
import java.util.concurrent.CancellationException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class ReceiverPreviewTest {
    private fun temporary(check: (File) -> Unit) {
        val file = File.createTempFile("receiver-preview-", ".jpg")
        try { check(file) } finally { file.delete() }
    }

    @Test fun unavailableDoesNotDecodeOrRetry() {
        var requests = 0
        assertNull(loadReceiverPreviewFile<String>({ requests++; null }, { error("No path to decode") }, {}))
        assertEquals(1, requests)
    }

    @Test fun purgedReplyRegeneratesOnce() = temporary { file ->
        file.delete()
        var requests = 0
        val image = loadReceiverPreviewFile({
            if (++requests == 2) file.writeText("regenerated")
            file
        }, File::readText, {})
        assertEquals("regenerated", image)
        assertEquals(2, requests)
    }

    @Test fun purgeBetweenExistenceCheckAndDecodeAlsoRegenerates() = temporary { file ->
        var requests = 0
        val image = loadReceiverPreviewFile({ requests++; file.writeText("preview"); file }, {
            if (requests == 1) { it.delete(); throw java.io.FileNotFoundException() }
            it.readText()
        }, {})
        assertEquals("preview", image)
        assertEquals(2, requests)
    }

    @Test fun repeatedPurgeHasABoundedRetry() = temporary { file ->
        file.delete()
        var requests = 0
        assertNull(loadReceiverPreviewFile({ requests++; file }, { "unused" }, {}))
        assertEquals(2, requests)
    }

    @Test fun undecodableExistingFileStaysNeutralWithoutRegeneration() = temporary { file ->
        var requests = 0
        assertNull(loadReceiverPreviewFile<String>({ requests++; file }, { throw IllegalArgumentException("bad image") }, {}))
        assertEquals(1, requests)
    }

    @Test fun cancellationDuringRequestPreventsDecode() = temporary { file ->
        var cancelled = false
        assertThrows(CancellationException::class.java) {
            loadReceiverPreviewFile({ cancelled = true; file }, { error("Cancelled before decode") }, {
                if (cancelled) throw CancellationException()
            })
        }
    }

    @Test fun cancellationDuringDecodePreventsDelivery() = temporary { file ->
        var cancelled = false
        assertThrows(CancellationException::class.java) {
            loadReceiverPreviewFile({ file }, { cancelled = true; "late image" }, {
                if (cancelled) throw CancellationException()
            })
        }
    }
}
