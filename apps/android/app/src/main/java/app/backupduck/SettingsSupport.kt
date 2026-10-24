package app.backupduck

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.view.doOnDetach
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import com.google.android.material.R as M

/** Public destinations already used by the website. */
private const val WEBSITE = "https://backupduck.app"
private const val FEEDBACK_GROUP = "https://t.me/+MCA62rlSwZplMGI1"

/** Reserved content is absent from production until supplied by its owner. */
internal data class ReservedSettingsContent(
    // TODO: Supply the author's own words before enabling the production card.
    val authorText: String? = null,
    // Resolve catalog placeholder copy in the page's current language.
    @androidx.annotation.StringRes val authorTextResource: Int? = null,
    // TODO: Supply the public support mailbox before enabling production email feedback.
    val feedbackEmail: String? = null,
)

internal fun Context.feedbackSummary(): String = getString(
    if (ReceiverEnvironment.reservedSettings.feedbackEmail == null) R.string.feedback_join_group else R.string.pref_feedback_note)

internal fun Context.receiverAppVersion(): String =
    packageManager.getPackageInfo(packageName, 0).versionName.orEmpty().substringBefore('-')

internal fun Context.receiverDiagnostics(root: String): ByteArray = combinedDiagnostics(root)

internal fun Context.settingsFooter(parent: LinearLayout, diagnostics: () -> Unit, advanced: () -> Unit) {
    val line = LinearLayout(this).apply {
        gravity = Gravity.CENTER
        setPadding(0, token(R.dimen.duck_space_medium), 0, token(R.dimen.duck_space_large))
    }
    fun link(title: Int, action: () -> Unit) = lookText(getString(title), M.style.TextAppearance_Material3_BodySmall,
        color = getColor(R.color.duck_role_accent)).apply {
        gravity = Gravity.CENTER
        minimumHeight = token(R.dimen.duck_space_xx_large)
        val inset = token(R.dimen.duck_space_x_small)
        setPadding(inset, inset, inset, inset)
        isClickable = true; isFocusable = true; background = selectableBackground()
        setOnClickListener { action() }
        accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(host: View, info: android.view.accessibility.AccessibilityNodeInfo) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = android.widget.Button::class.java.name
            }
        }
    }
    line.addView(link(R.string.pref_diagnostics, diagnostics))
    line.addView(lookText("·", M.style.TextAppearance_Material3_BodySmall, secondary = true))
    line.addView(link(R.string.pref_advanced_settings, advanced))
    parent.addView(line, LinearLayout.LayoutParams(-1, -2))
}

internal fun MainActivity.createAboutPage(): LookPage {
    val page = LookPage(this, getString(R.string.pref_about), "about")
    val brand = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL }
    brand.addView(android.widget.ImageView(this).apply {
        setImageResource(R.mipmap.ic_launcher)
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }, LinearLayout.LayoutParams(dp(72), dp(72)))
    brand.addView(lookText(getString(R.string.app_name), M.style.TextAppearance_Material3_HeadlineSmall).apply { gravity = Gravity.CENTER_HORIZONTAL })
    brand.addView(lookText(getString(R.string.about_tagline), M.style.TextAppearance_Material3_BodyMedium, secondary = true).apply { gravity = Gravity.CENTER_HORIZONTAL })
    page.body.addView(brand, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = token(R.dimen.duck_space_large) })
    val content = ReceiverEnvironment.reservedSettings
    val authorText = content.authorText ?: content.authorTextResource?.let { getString(it) }
    authorText?.let {
        lookCard(page.body).apply {
            addView(lookText(getString(R.string.about_author_title), M.style.TextAppearance_Material3_TitleMedium).apply {
                isAccessibilityHeading = true
            })
            addView(lookText(it, M.style.TextAppearance_Material3_BodyLarge), LinearLayout.LayoutParams(-1, -2).apply {
                topMargin = token(R.dimen.duck_space_small)
            })
        }
    }
    val rows = lookGroup(page.body)
    if (authorText != null) (rows.parent as View).layoutParams = ((rows.parent as View).layoutParams as LinearLayout.LayoutParams).apply {
        topMargin = token(R.dimen.duck_space_large)
    }
    fun versionStatus(value: UpdateCheckStatus?): String = "${receiverAppVersion()} · ${updateStatusLabel(value, compact = true)}"
    val status = lookRow(rows, R.drawable.ic_info, getString(R.string.pref_version),
        versionStatus(AppUpdates.status.value)) {
        startActivity(Intent(this, UpdatesActivity::class.java))
    }
    val observation = lifecycleScope.launch {
        AppUpdates.status.collect { status.setSupporting(versionStatus(it)) }
    }
    page.body.doOnDetach { observation.cancel() }
    if (AppUpdates.status.value == null) lifecycleScope.launch { AppUpdates.check(this@createAboutPage) }
    lookRow(rows, R.drawable.ic_document, getString(R.string.about_privacy)) { openSupportLink("$WEBSITE/privacy.html") }
    lookRow(rows, R.drawable.ic_computer, getString(R.string.about_source_licenses)) { createSourceLicensesPage().show() }
    lookRow(rows, R.drawable.ic_globe, getString(R.string.official_website)) { openSupportLink(WEBSITE) }
    lookFootnote(page.body, getString(R.string.about_privacy_note))
    return page
}

internal fun MainActivity.showFeedback() {
    val email = ReceiverEnvironment.reservedSettings.feedbackEmail
    if (email == null) {
        openSupportLink(FEEDBACK_GROUP)
        return
    }
    val sheet = LookSheet(this)
    sheet.body.addView(lookText(getString(R.string.pref_send_feedback), M.style.TextAppearance_Material3_TitleLarge).apply {
        isAccessibilityHeading = true
        val padding = token(R.dimen.duck_space_medium)
        setPadding(padding, 0, padding, token(R.dimen.duck_space_small))
    })
    lookRow(sheet.body, R.drawable.ic_group, getString(R.string.feedback_join_group)) {
        sheet.dismiss(); openSupportLink(FEEDBACK_GROUP)
    }
    lookRow(sheet.body, R.drawable.ic_mail, getString(R.string.feedback_email)) {
        sheet.dismiss(); startActivity(Intent(this, FeedbackActivity::class.java))
    }
    sheet.show()
}

internal fun MainActivity.openSupportLink(url: String) {
    runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
        .onFailure { showActionFailure(R.string.support_open_failed) { openSupportLink(url) } }
}

/** Export first; the person can inspect the same document before composing a draft. */
class FeedbackActivity : BackupDuckActivity() {
    private var exported: Uri? = null
    private lateinit var body: LinearLayout
    private var busy = false
    private val export = registerForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) lifecycleScope.launch {
            busy = true; render()
            val result = withContext(Dispatchers.IO) { runCatching {
                val bytes = receiverDiagnostics("$filesDir/receiver")
                checkNotNull(contentResolver.openOutputStream(uri, "wt")).use { it.write(bytes) }
            } }
            busy = false
            if (result.isSuccess) {
                runCatching { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                exported = uri; render()
            } else render(getString(R.string.duck_export_report_failure))
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", androidx.appcompat.app.AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        if (ReceiverEnvironment.reservedSettings.feedbackEmail == null) {
            finish()
            return
        }
        exported = savedInstanceState?.getString("exported")?.let(Uri::parse)
        nativeDetailPage(R.string.feedback_email) { body = it; render() }
    }
    override fun onSaveInstanceState(outState: Bundle) {
        exported?.let { outState.putString("exported", it.toString()) }
        super.onSaveInstanceState(outState)
    }
    private fun render(error: String? = null) {
        body.removeAllViews()
        body.addView(lookText(getString(R.string.feedback_export_note), M.style.TextAppearance_Material3_BodyMedium, secondary = true))
        val rows = lookGroup(body)
        val uri = exported
        if (uri == null) {
            lookRow(rows, R.drawable.ic_document, getString(if (busy) R.string.duck_exporting_report else R.string.logs_export)) {
                if (!busy) export.launch("BackupDuck-diagnostics.json")
            }
        } else {
            lookRow(rows, R.drawable.ic_document, getString(R.string.feedback_view_file), diagnosticsName(uri)) {
                launchExternal(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/json").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
            }
            lookRow(rows, R.drawable.ic_mail, getString(R.string.feedback_compose)) {
                val draft = Intent(Intent.ACTION_SEND).apply {
                    type = "message/rfc822"
                    putExtra(Intent.EXTRA_EMAIL, arrayOf(checkNotNull(ReceiverEnvironment.reservedSettings.feedbackEmail)))
                    putExtra(Intent.EXTRA_SUBJECT, getString(R.string.feedback_subject, receiverAppVersion()))
                    putExtra(Intent.EXTRA_STREAM, uri)
                    clipData = ClipData.newRawUri("BackupDuck-diagnostics.json", uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                launchExternal(Intent.createChooser(draft, getString(R.string.feedback_compose)))
            }
        }
        error?.let { body.addView(lookText(it, M.style.TextAppearance_Material3_BodyMedium).apply {
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }) }
    }
    private fun diagnosticsName(uri: Uri): String = runCatching {
        contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
    }.getOrNull() ?: "BackupDuck-diagnostics.json"

    private fun launchExternal(intent: Intent) {
        runCatching { startActivity(intent) }.onFailure { render(getString(R.string.support_open_failed)) }
    }
}
