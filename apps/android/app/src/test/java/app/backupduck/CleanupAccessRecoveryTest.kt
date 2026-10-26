package app.backupduck

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CleanupAccessRecoveryTest {
    private class SavedStep : CleanupAccessStore {
        override var accessStep: CleanupAccessStep? = null
    }
    private val opened = 1_000_000L

    @Test fun settingsHandoffRecordsTheTimeAndEitherJourneyHost() {
        CleanupAccessRecovery.routes.forEach { route ->
            val saved = SavedStep()
            CleanupAccessRecovery(saved).waiting(route, opened)
            assertEquals(CleanupAccessStep(route, opened), saved.accessStep)
        }
    }
    @Test fun aNewControllerRestoresTheStepAfterProcessDeath() {
        val saved = SavedStep()
        CleanupAccessRecovery(saved).waiting("auto-cleanup", opened)
        val recreated = CleanupAccessRecovery(saved)
        assertEquals("auto-cleanup", recreated.route)
        assertEquals("auto-cleanup", recreated.serviceConnected(opened + 1))
        assertEquals("auto-cleanup", CleanupAccessRecovery(saved).route)
        assertEquals(CleanupAccessNext.BIND, CleanupAccessRecovery(saved).resumed(true))
        assertNull(saved.accessStep)
    }
    @Test fun connectionReturnsOnceWithinTenMinutes() {
        val saved = SavedStep()
        val recovery = CleanupAccessRecovery(saved)
        recovery.waiting("storage", opened)
        assertEquals("storage", recovery.serviceConnected(opened + CleanupAccessRecovery.RETURN_WINDOW_MS - 1))
        assertNull(saved.accessStep?.waitingSince)
        assertNull(recovery.serviceConnected(opened + CleanupAccessRecovery.RETURN_WINDOW_MS - 1))
    }
    @Test fun connectionAtOrBeyondTheDeadlineDoesNotForeground() {
        listOf(CleanupAccessRecovery.RETURN_WINDOW_MS, CleanupAccessRecovery.RETURN_WINDOW_MS + 1).forEach { age ->
            val saved = SavedStep()
            val recovery = CleanupAccessRecovery(saved)
            recovery.waiting("storage", opened)
            assertNull(recovery.serviceConnected(opened + age))
            assertNull(saved.accessStep?.waitingSince)
            assertEquals("storage", recovery.route)
            // Explicit manual return still continues after automatic return expires.
            assertEquals(CleanupAccessNext.BIND, recovery.resumed(true))
        }
    }
    @Test fun aClockRollbackCannotExtendAnAutomaticReturn() {
        val saved = SavedStep()
        val recovery = CleanupAccessRecovery(saved)
        recovery.waiting("storage", opened)
        assertNull(recovery.serviceConnected(opened - 1))
        assertNull(recovery.serviceConnected(opened + 1))
        assertEquals(CleanupAccessNext.BIND, recovery.resumed(true))
    }
    @Test fun manualReturnWithAccessConsumesTheMarkerAndContinuesOnce() {
        val saved = SavedStep()
        val recovery = CleanupAccessRecovery(saved)
        recovery.waiting("storage", opened)
        assertEquals(CleanupAccessNext.BIND, recovery.resumed(true))
        assertEquals(CleanupAccessNext.NONE, recovery.resumed(true))
        assertNull(recovery.serviceConnected(opened + 1))
    }
    @Test fun returningWithoutAccessStopsSetupAndPreventsALaterForeground() {
        val saved = SavedStep()
        val recovery = CleanupAccessRecovery(saved)
        recovery.waiting("auto-cleanup", opened)
        assertEquals(CleanupAccessNext.ACCESS_REQUIRED, recovery.resumed(false))
        assertNull(saved.accessStep)
        assertNull(recovery.serviceConnected(opened + 1))
        assertEquals(CleanupAccessNext.NONE, recovery.resumed(true))
    }
    @Test fun cancellingOrLeavingTheAccessStepInvalidatesTheReturn() {
        val saved = SavedStep()
        val recovery = CleanupAccessRecovery(saved)
        recovery.waiting("storage", opened)
        saved.accessStep = null
        assertNull(recovery.route)
        assertNull(recovery.serviceConnected(opened + 1))
        assertEquals(CleanupAccessNext.NONE, recovery.resumed(true))
    }
    @Test fun unrelatedConnectionsAndResumesDoNothing() {
        val recovery = CleanupAccessRecovery(SavedStep())
        assertNull(recovery.serviceConnected(opened))
        assertEquals(CleanupAccessNext.NONE, recovery.resumed(false))
        assertEquals(CleanupAccessNext.NONE, recovery.resumed(true))
    }
    @Test fun savedAccessWithoutATimestampRestoresButCannotForeground() {
        val saved = SavedStep().apply { accessStep = CleanupAccessStep("storage", null) }
        val recovery = CleanupAccessRecovery(saved)
        assertEquals("storage", recovery.route)
        assertNull(recovery.serviceConnected(opened))
        assertEquals(CleanupAccessNext.BIND, recovery.resumed(true))
    }
    @Test fun aNewAttemptReplacesAnExpiredMarkerAndRoute() {
        val saved = SavedStep()
        val recovery = CleanupAccessRecovery(saved)
        recovery.waiting("storage", opened)
        recovery.serviceConnected(opened + CleanupAccessRecovery.RETURN_WINDOW_MS)
        recovery.waiting("auto-cleanup", opened + CleanupAccessRecovery.RETURN_WINDOW_MS)
        assertEquals("auto-cleanup", recovery.serviceConnected(opened + CleanupAccessRecovery.RETURN_WINDOW_MS + 1))
    }
    @Test(expected = IllegalArgumentException::class)
    fun onlyExistingJourneyHostsMayRegisterASettingsHandoff() {
        CleanupAccessRecovery(SavedStep()).waiting("diagnostics", opened)
    }
}
