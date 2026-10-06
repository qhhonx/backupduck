package app.backupduck

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import com.google.android.material.materialswitch.MaterialSwitch
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.URL
import java.security.MessageDigest

internal data class AppRelease(val version: String, val build: Long, val url: String, val sha256: String, val size: Long)
internal object AppUpdates {
    private const val API = "https://api.github.com/repos/qhhonx/backupduck/releases?per_page=30"
    private const val SITE_API = "https://backupduck.vercel.app/api/releases"
    private const val PREFIX = "https://github.com/qhhonx/backupduck/releases/download/"
    private const val MAX_APK = 250L * 1024 * 1024
    private val TAG = Regex("v[0-9]+\\.[0-9]+\\.[0-9]+(?:-(?:alpha|beta|rc)\\.[0-9]+)?")
    fun preferences(context: Context) = context.getSharedPreferences("app_updates", Context.MODE_PRIVATE)
    private fun connection(url: String) = (URL(url).openConnection() as javax.net.ssl.HttpsURLConnection).apply {
        connectTimeout = 15_000; readTimeout = 30_000
        setRequestProperty("Accept", "application/vnd.github+json")
        setRequestProperty("User-Agent", "BackupDuck")
    }
    private fun read(url: String, limit: Int): String {
        val c = connection(url)
        try {
            check(c.responseCode == 200)
            return c.inputStream.use { stream ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) { val n = stream.read(buffer); if (n < 0) break
                    check(output.size() + n <= limit); output.write(buffer, 0, n)
                }
                output.toString("UTF-8")
            }
        } finally { c.disconnect() }
    }
    private fun release(tag: String, installed: Long): AppRelease? {
        check(TAG.matches(tag))
        val data = JSONObject(read("$PREFIX$tag/android-update.json", 16_384))
        val next = AppRelease(data.getString("version"), data.getLong("build"), data.getString("url"), data.getString("sha256"), data.getLong("size"))
        check(next.version == tag.removePrefix("v"))
        check(next.url == "$PREFIX$tag/BackupDuck-${next.version}-arm64.apk")
        check(Regex("[a-f0-9]{64}").matches(next.sha256) && next.size in 1..MAX_APK)
        return next.takeIf { it.build > installed }
    }
    private fun fromWebsite(installed: Long): AppRelease? {
        val site = JSONObject(read(SITE_API, 16_384))
        val version = site.getString("version")
        val tag = "v$version"
        check(TAG.matches(tag))
        check(site.getString("android") == "$PREFIX$tag/BackupDuck-$version-arm64.apk")
        return release(tag, installed)
    }
    private fun fromGithub(installed: Long): AppRelease? {
        val list = JSONArray(read(API, 1024 * 1024))
        var latest: AppRelease? = null
        for (i in 0 until list.length()) {
            val release = list.getJSONObject(i)
            if (release.optBoolean("draft") || release.isNull("published_at")) continue
            val tag = release.optString("tag_name")
            if (!TAG.matches(tag)) continue
            val assets = release.getJSONArray("assets")
            val metadata = (0 until assets.length()).map { assets.getJSONObject(it) }
                .firstOrNull { it.optString("name") == "android-update.json" } ?: continue
            val url = metadata.getString("browser_download_url")
            check(url == "$PREFIX$tag/android-update.json")
            val next = release(tag, installed)
            if (next != null && (latest == null || next.build > latest.build)) latest = next
        }
        return latest
    }
    internal fun latest(installed: Long): AppRelease? {
        val website = runCatching { fromWebsite(installed) }
        website.getOrNull()?.let { return it }
        val github = runCatching { fromGithub(installed) }
        if (github.isSuccess) return github.getOrNull()
        return website.getOrThrow()
    }
    fun latest(context: Context): AppRelease? =
        latest(context.packageManager.getPackageInfo(context.packageName, 0).longVersionCode)
    fun verify(context: Context, file: File, release: AppRelease) {
        check(file.length() == release.size)
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input -> val bytes = ByteArray(65536); while (true) {
            val n = input.read(bytes); if (n < 0) break; digest.update(bytes, 0, n)
        } }
        check(digest.digest().joinToString("") { "%02x".format(it) } == release.sha256)
        val flags = PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES
        val candidate = context.packageManager.getPackageArchiveInfo(file.path, flags) ?: error("Invalid APK")
        val current = context.packageManager.getPackageInfo(context.packageName, flags)
        check(candidate.packageName == context.packageName && candidate.longVersionCode == release.build && candidate.longVersionCode > current.longVersionCode)
        @Suppress("DEPRECATION")
        fun certificates(info: android.content.pm.PackageInfo): Set<String> {
            val signers = info.signingInfo?.apkContentsSigners ?: info.signatures
            check(!signers.isNullOrEmpty()) { "Missing APK signing certificates" }
            return signers.map { it.toCharsString() }.toSet()
        }
        check(certificates(candidate) == certificates(current)) { "Signing identity mismatch" }
    }
    fun download(context: Context, release: AppRelease): File {
        val directory = File(context.cacheDir, "updates").apply { mkdirs() }
        val file = File(directory, "BackupDuck.apk")
        val partial = File(directory, "download.part")
        val c = connection(release.url)
        try {
            check(c.responseCode == 200)
            var count = 0L
            c.inputStream.use { input -> partial.outputStream().use { output ->
                val bytes = ByteArray(65536)
                while (true) { val n = input.read(bytes); if (n < 0) break
                    count += n; check(count <= release.size); output.write(bytes, 0, n)
                }
            } }
            verify(context, partial, release)
            if (file.exists()) check(file.delete())
            check(partial.renameTo(file)); return file
        } finally { c.disconnect(); partial.delete() }
    }
}

class UpdatesActivity:AppCompatActivity() {
    private var release:AppRelease?=null
    private var downloaded:File?=null
    private lateinit var feedback:LinearLayout
    private lateinit var button:com.google.android.material.button.MaterialButton
    private val installedVersion get()=packageManager.getPackageInfo(packageName,0).versionName ?: ""
    override fun onCreate(savedInstanceState:Bundle?) {
        delegate.localNightMode=getSharedPreferences("appearance",MODE_PRIVATE).getInt("mode",androidx.appcompat.app.AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        nativeDetailPage(R.string.updates_title) {panel ->
            val group=duckGroup(panel)
            duckSetting(group,getString(R.string.settings_version,installedVersion),control=duckText("",13))
            duckSetting(group,getString(R.string.updates_automatic),getString(R.string.updates_note),duckSwitch(AppUpdates.preferences(this).getBoolean("automatic",true)) {
                AppUpdates.preferences(this).edit().putBoolean("automatic",it).apply()
            })
            feedback=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL};panel.addView(feedback)
            button=duckButton(getString(R.string.updates_check),true) {perform()};panel.addView(button,LinearLayout.LayoutParams(-1,-2))
            panel.addView(duckLink(getString(R.string.official_website)) {
                runCatching {startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://backupduck.vercel.app")))}.onFailure {showMessage(getString(R.string.updates_check_failed),true)}
            })
        }
        check()
    }
    private fun showMessage(message:String,failed:Boolean=false) {
        feedback.removeAllViews()
        if(failed)duckProblem(feedback,message) else duckNotice(feedback,message)
    }
    private fun check() {
        if(packageName.endsWith(".validation")||installedVersion.endsWith("-dev")) {
            showMessage(getString(R.string.duck_update_development));button.isEnabled=false;return
        }
        button.isEnabled=false;release=null;showMessage(getString(R.string.updates_checking))
        lifecycleScope.launch {
            runCatching {withContext(Dispatchers.IO) {AppUpdates.latest(this@UpdatesActivity)}}
                .onSuccess {release=it;showMessage(if(it==null)getString(R.string.updates_current) else getString(R.string.updates_available,it.version));button.setText(if(it==null)R.string.updates_check else R.string.updates_download)}
                .onFailure {showMessage(getString(R.string.updates_check_failed),true);button.setText(R.string.duck_retry)}
            button.isEnabled=true
        }
    }
    private fun perform() {
        val target=release?:return check()
        button.isEnabled=false;showMessage(getString(R.string.updates_downloading))
        lifecycleScope.launch {
            runCatching {
                val file=withContext(Dispatchers.IO) {
                    val local=downloaded
                    if(local!=null&&local.exists()) {AppUpdates.verify(this@UpdatesActivity,local,target);local} else AppUpdates.download(this@UpdatesActivity,target)
                }
                downloaded=file
                if(!packageManager.canRequestPackageInstalls()) {
                    showMessage(getString(R.string.updates_permission))
                    startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:$packageName")))
                } else {
                    val uri=FileProvider.getUriForFile(this@UpdatesActivity,"$packageName.updates",file)
                    startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                    showMessage(getString(R.string.updates_confirm))
                }
                button.setText(R.string.updates_install)
            }.onFailure {error ->showMessage(getString(if(error.message=="Signing identity mismatch")R.string.duck_update_signature else R.string.updates_download_failed),true);button.setText(R.string.duck_retry)}
            button.isEnabled=true
        }
    }
}
