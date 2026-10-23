package app.backupduck

import org.junit.Assert.*
import org.junit.Test

class DiagnosticReleaseRoutesTest {
    @Test fun productionCannotOpenTechnicalTools() {
        assertEquals("release", BuildConfig.BUILD_TYPE)
        assertFalse(BuildConfig.DEBUG)
        assertFalse(DiagnosticRoutes.toolsEnabled)
        listOf("diagnostics-probe", "diagnostics-setup", "diagnostics-bind", "diagnostics-progress").forEach {
            // MainActivity routes a null technical destination to Storage.
            assertNull(DiagnosticRoutes.technicalRoute(it))
        }
    }
}
