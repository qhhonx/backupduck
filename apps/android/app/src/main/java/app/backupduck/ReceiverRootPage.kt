package app.backupduck

/** Numeric root IDs are persisted by older receivers; Storage is now secondary. */
internal data class ReceiverRootPage(val selected: Int, val openStorage: Boolean = false) {
    companion object {
        fun restore(saved: Int) = when (saved) {
            1, 2, 4 -> ReceiverRootPage(saved)
            3 -> ReceiverRootPage(4, openStorage = true)
            else -> ReceiverRootPage(1)
        }
    }
}
