package app.backupduck

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.PowerManager
import org.json.JSONObject

internal object ReceiverThermalSettings {
    const val DEFAULT_CELSIUS = 40
    val choices = (35..45).toList()
    private fun prefs(context: Context) = context.getSharedPreferences("receiver_thermal", Context.MODE_PRIVATE)
    fun enabled(context: Context) = prefs(context).getBoolean("enabled", true)
    fun threshold(context: Context) = prefs(context).getInt("threshold_c", DEFAULT_CELSIUS).coerceIn(35, 45)
    fun setEnabled(context: Context, enabled: Boolean) { prefs(context).edit().putBoolean("enabled", enabled).apply() }
    fun setThreshold(context: Context, celsius: Int) {
        require(celsius in 35..45)
        prefs(context).edit().putInt("threshold_c", celsius).apply()
    }
}

/** Temperatures come from Android's battery sensor, in tenths of a degree Celsius. */
internal data class ThermalReading(val deciCelsius: Int?, val systemStatus: Int,
    val batteryPercent: Int? = null, val charging: Boolean? = null)

internal data class ThermalDecision(val batteryHeld: Boolean = false, val systemHeld: Boolean = false) {
    val held: Boolean get() = batteryHeld || systemHeld

    fun next(enabled: Boolean, limitCelsius: Int, reading: ThermalReading): ThermalDecision {
        if (!enabled) return ThermalDecision()
        // Keep the battery hold if a sensor read is briefly unavailable. A two-degree
        // gap prevents repeated pause/resume at the selected boundary.
        val battery = reading.deciCelsius?.let {
            if (batteryHeld) it > (limitCelsius - 2) * 10 else it >= limitCelsius * 10
        } ?: batteryHeld
        val system = if (systemHeld) reading.systemStatus >= PowerManager.THERMAL_STATUS_MODERATE
            else reading.systemStatus >= PowerManager.THERMAL_STATUS_SEVERE
        return ThermalDecision(battery, system)
    }
}

internal object ReceiverHolds {
    @Volatile var thermalHeld = false
        private set

    @Synchronized fun setThermal(context: Context, held: Boolean) {
        thermalHeld = held
        sync(context)
    }

    @Synchronized fun sync(context: Context) {
        NativeBridge.request(JSONObject().put("op", "receiver_transfer_hold")
            .put("held", thermalHeld || ReceiverPreferences.paused(context) || PhotosCleanup(context).held))
    }

    @Synchronized fun reset() { thermalHeld = false }
}

internal fun readThermal(context: Context): ThermalReading {
    val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    val value = battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
        ?.takeIf { it in -200..900 }
    val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
    val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
    val percent = if (level >= 0 && scale > 0) (level * 100 / scale).coerceIn(0, 100) else null
    val charging = when (battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)) {
        BatteryManager.BATTERY_STATUS_CHARGING, BatteryManager.BATTERY_STATUS_FULL -> true
        BatteryManager.BATTERY_STATUS_DISCHARGING, BatteryManager.BATTERY_STATUS_NOT_CHARGING -> false
        else -> null
    }
    val power = context.getSystemService(PowerManager::class.java)
    return ThermalReading(value, power.currentThermalStatus, percent, charging)
}
