package app.backupduck

/** Accept only the bounded completion amount Google Photos actually reports. */
internal object CleanupCompletion {
    fun bytes(title: String): Long? {
        val match = Regex("(?:You freed up |您已释放\\s*)([0-9]+(?:\\.[0-9]+)?)\\s*(B|KB|MB|GB|TB)").matchEntire(title.trim()) ?: return null
        val amount = match.groupValues[1].toDoubleOrNull() ?: return null
        val multiplier = when (match.groupValues[2]) {
            "KB" -> 1e3; "MB" -> 1e6; "GB" -> 1e9; "TB" -> 1e12; else -> 1.0
        }
        val bytes = amount * multiplier
        return bytes.takeIf { it.isFinite() && it > 0 && it < Long.MAX_VALUE.toDouble() }?.toLong()
    }
}
