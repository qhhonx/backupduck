package app.backupduck

internal object DiagnosticRoutes {
    val toolsEnabled = BuildConfig.DEBUG || BuildConfig.BUILD_TYPE == "catalog"
    fun technicalRoute(surface: String): String? = if (!toolsEnabled) null else when (surface) {
        "diagnostics-probe" -> "diagnostics"
        "diagnostics-setup" -> "cleanup"
        "diagnostics-bind" -> "bind"
        "diagnostics-progress" -> "progress"
        else -> null
    }
}
