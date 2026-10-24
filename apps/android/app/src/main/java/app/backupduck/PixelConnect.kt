package app.backupduck

/**
 * The rules of connecting a device to the Pixel (design/pixel-connect.md):
 * when the code is shown, what counts as connected, and how the device list
 * groups devices. Pure, so the rules are unit tested.
 */
internal data class DevicePeer(val id: String, val name: String, val kind: String?, val lastSeenSec: Long, val enabled: Boolean) {
    /** Macs and PCs use the computer mark; phone and tablet marks remain distinct. */
    val computer: Boolean get() = kind in setOf("Mac", "Windows", "Linux")
}

internal enum class CodePhase { GETTING_READY, CODE, FAILED }

/** The receiver is given a minute to start before the screen says why it could not. */
internal const val CODE_READY_TIMEOUT_MS = 60_000L

internal fun codePhase(phase: String, error: String?, hasCode: Boolean, waitedMs: Long): CodePhase = when {
    phase == "ready" && hasCode -> CodePhase.CODE
    phase == "waiting" && error != null -> CodePhase.FAILED
    waitedMs > CODE_READY_TIMEOUT_MS -> CodePhase.FAILED
    else -> CodePhase.GETTING_READY
}

/**
 * The device that connected while the code was shown. The core records a known
 * device again on every exchange, so only a device it had not seen counts.
 */
internal fun newlyConnected(before: Set<String>, now: List<DevicePeer>): DevicePeer? = now.firstOrNull { it.id !in before }

internal data class DeviceGroups(val sending: List<DevicePeer>, val stopped: List<DevicePeer>)

/** One row per device, most recently connected first; stopped devices apart. */
internal fun deviceGroups(peers: List<DevicePeer>): DeviceGroups {
    val devices = peers.sortedByDescending { it.lastSeenSec }.distinctBy { it.id }
    return DeviceGroups(devices.filter { it.enabled }, devices.filterNot { it.enabled })
}

internal enum class MacScan { CANCELLED, UNREADABLE, CODE }

/** A Mac's code names its kind; anything else is not a BackupDuck Mac code. */
internal fun macScan(contents: String?): MacScan = when {
    contents == null -> MacScan.CANCELLED
    contents.length > 32_768 || !contents.contains("\"backupduck_desktop_pairing\"") -> MacScan.UNREADABLE
    else -> MacScan.CODE
}
