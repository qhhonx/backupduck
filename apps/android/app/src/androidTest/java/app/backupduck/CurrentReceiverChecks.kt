package app.backupduck

/** Instrumentation accesses the actual current page without adding a production test API. */
internal fun MainActivity.photosForCheck(): ReceivedPhotosPage = MainActivity::class.java
    .getDeclaredField("receivedPhotos").apply { isAccessible = true }.get(this) as ReceivedPhotosPage
