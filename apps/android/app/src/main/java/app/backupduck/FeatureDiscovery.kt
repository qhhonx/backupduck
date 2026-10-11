package app.backupduck

import android.content.Context

/** Local, per-feature acknowledgements. Discovery never enables a feature or grants consent. */
internal class FeatureDiscovery(context: Context) {
    private val preferences = context.getSharedPreferences("feature_discovery", Context.MODE_PRIVATE)

    fun isUnseen(feature: String): Boolean = !preferences.getBoolean(feature, false)
    fun acknowledge(feature: String) { preferences.edit().putBoolean(feature, true).apply() }

    companion object {
        const val PHOTOS_CLEANUP = "photos_cleanup_introduction_v1"
    }
}
