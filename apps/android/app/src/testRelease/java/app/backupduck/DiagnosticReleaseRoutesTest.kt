package app.backupduck

import org.junit.Assert.*
import org.junit.Test

class DiagnosticReleaseRoutesTest {
    @Test fun productionDoesNotCompileTechnicalPresentation() {
        assertEquals("release", BuildConfig.BUILD_TYPE)
        assertFalse(BuildConfig.DEBUG)
        listOf("PhotosProbeActivity", "DiagnosticRoutes", "OriginalArchive").forEach { name ->
            try {
                Class.forName("app.backupduck.$name", false, javaClass.classLoader)
                fail("Retired technical presentation remains compiled: $name")
            } catch (_: ClassNotFoundException) { /* Compatibility routes use Storage. */ }
        }
    }
}
