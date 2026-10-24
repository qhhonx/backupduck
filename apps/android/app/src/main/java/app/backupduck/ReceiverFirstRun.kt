package app.backupduck

/** Durable first-run positions; a live connection confirmation is never replayed. */
internal enum class FirstRunStep {
    WELCOME, RUNNING, CODE, CONNECTED, GPHOTOS, SPACE;

    val resumable: FirstRunStep get() = if (this == CONNECTED) GPHOTOS else this

    /** Null leaves the task in the background without completing first run. */
    val previous: FirstRunStep? get() = when (this) {
        WELCOME -> null
        RUNNING -> WELCOME
        CODE -> RUNNING
        CONNECTED -> CODE
        GPHOTOS -> CODE
        SPACE -> GPHOTOS
    }

    companion object {
        fun restore(name: String?): FirstRunStep = entries.firstOrNull { it.name.equals(name, true) }?.resumable ?: WELCOME
    }
}
