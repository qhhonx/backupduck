package app.backupduck

/** The route survives process death; only the automatic foreground return expires. */
internal data class CleanupAccessStep(val route: String, val waitingSince: Long?)

internal interface CleanupAccessStore {
    var accessStep: CleanupAccessStep?
}

internal enum class CleanupAccessNext { NONE, BIND, ACCESS_REQUIRED }

/** One-shot handoff between Settings, the accessibility service and the journey. */
internal class CleanupAccessRecovery(private val store: CleanupAccessStore) {
    companion object {
        const val RETURN_WINDOW_MS = 10 * 60_000L
        val routes = setOf("storage", "auto-cleanup")
    }
    val route: String? get() = store.accessStep?.route?.takeIf { it in routes }

    fun waiting(route: String, now: Long) {
        require(route in routes)
        store.accessStep = CleanupAccessStep(route, now)
    }

    fun serviceConnected(now: Long): String? {
        val step = store.accessStep ?: return null
        val started = step.waitingSince ?: return null
        // Consume even an expired or clock-invalid marker. Keep the route for a
        // manual return or Activity recreation after this foreground request.
        store.accessStep = step.copy(waitingSince = null)
        return step.route.takeIf { it in routes && now >= started && now - started < RETURN_WINDOW_MS }
    }

    fun resumed(hasAccess: Boolean): CleanupAccessNext {
        if (store.accessStep == null) return CleanupAccessNext.NONE
        store.accessStep = null
        return if (hasAccess) CleanupAccessNext.BIND else CleanupAccessNext.ACCESS_REQUIRED
    }
}
