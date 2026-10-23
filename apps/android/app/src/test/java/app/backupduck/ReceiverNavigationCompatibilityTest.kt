package app.backupduck

import org.junit.Assert.*
import org.junit.Test

class ReceiverNavigationCompatibilityTest {
    @Test fun savedReceivePhotosAndSettingsKeepTheirMeaning() {
        listOf(1, 2, 4).forEach { saved ->
            val restored = ReceiverRootPage.restore(saved)
            assertEquals(saved, restored.selected)
            assertFalse(restored.openStorage)
        }
    }

    @Test fun savedStorageOpensUnderSettingsAndUnknownValuesFallBackToReceive() {
        assertEquals(ReceiverRootPage(4, openStorage = true), ReceiverRootPage.restore(3))
        listOf(-1, 0, 5, Int.MAX_VALUE).forEach { assertEquals(ReceiverRootPage(1), ReceiverRootPage.restore(it)) }
    }

    @Test fun retiredPresentationCannotBeConstructed() {
        listOf("ReceiverHome", "HistoryPage", "TransferAdapter", "StoragePage", "PairingUI", "PhotosProbeActivity", "DiagnosticRoutes", "OriginalArchive").forEach { name ->
            try {
                Class.forName("app.backupduck.$name", false, javaClass.classLoader)
                fail("Retired presentation remains compiled: $name")
            } catch (_: ClassNotFoundException) { /* Current surfaces own all callers. */ }
        }
    }
}
