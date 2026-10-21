package app.backupduck

import java.io.File

/** A disposable cache path may vanish between the core reply and opening it. */
internal fun <T> loadReceiverPreviewFile(request: () -> File?, decode: (File) -> T?, checkCancelled: () -> Unit): T? {
    repeat(2) {
        checkCancelled()
        val file = request() ?: return null
        checkCancelled()
        if (file.isFile) {
            val image = runCatching { decode(file) }.getOrNull()
            checkCancelled()
            if (image != null) return image
            // Only a purged file warrants regeneration; a bad existing preview stays neutral.
            if (file.isFile) return null
        }
    }
    return null
}
