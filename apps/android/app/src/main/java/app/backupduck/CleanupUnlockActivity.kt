package app.backupduck

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.PowerManager
import android.view.WindowManager
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.lang.ref.WeakReference
import java.util.UUID

/** Only a live, in-process cleanup request may dismiss a non-secure keyguard. */
internal object CleanupUnlock {
    private var request: String? = null
    private var result: CompletableDeferred<Boolean>? = null
    private var activity = WeakReference<CleanupUnlockActivity>(null)

    internal fun needsManualUnlock(locked: Boolean, secure: Boolean) = locked && secure

    suspend fun ensureReady(context: Context): Boolean = withContext(Dispatchers.Main.immediate) {
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        val power = context.getSystemService(PowerManager::class.java)
        if (needsManualUnlock(keyguard.isKeyguardLocked, keyguard.isKeyguardSecure)) return@withContext false
        if (!keyguard.isKeyguardLocked && power.isInteractive) return@withContext true
        check(request == null) { "unlock_busy" }
        val id = UUID.randomUUID().toString()
        val completion = CompletableDeferred<Boolean>()
        request = id; result = completion
        try {
            context.startActivity(Intent(context, CleanupUnlockActivity::class.java)
                .putExtra("request", id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            withTimeoutOrNull(12_000) { completion.await() } == true
                && !keyguard.isKeyguardLocked && power.isInteractive
        } finally {
            request = null; result = null
            activity.get()?.finish(); activity.clear()
        }
    }
    fun attach(id: String?, owner: CleanupUnlockActivity): Boolean {
        if (id == null || id != request) return false
        activity = WeakReference(owner)
        return true
    }
    fun complete(id: String?, success: Boolean) {
        if (id != null && id == request) result?.complete(success)
    }
}

/** Visible only while waking; it never displays or enters credentials. */
class CleanupUnlockActivity : BackupDuckActivity() {
    private var requested = false
    private val requestID get() = intent.getStringExtra("request")
    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", androidx.appcompat.app.AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        super.onCreate(savedInstanceState)
        if (!CleanupUnlock.attach(requestID, this)) { finish(); return }
        val keyguard = getSystemService(KeyguardManager::class.java)
        if (CleanupUnlock.needsManualUnlock(keyguard.isKeyguardLocked, keyguard.isKeyguardSecure)) {
            complete(false); return
        }
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(cleanupWakeContent(this))
    }
    override fun onPostResume() {
        super.onPostResume()
        if (requested || isFinishing) return
        requested = true
        window.decorView.post {
            if (isFinishing) return@post
            val keyguard = getSystemService(KeyguardManager::class.java)
            if (CleanupUnlock.needsManualUnlock(keyguard.isKeyguardLocked, keyguard.isKeyguardSecure)) {
                complete(false)
            } else if (!keyguard.isKeyguardLocked) {
                complete(getSystemService(PowerManager::class.java).isInteractive)
            } else {
                keyguard.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                    override fun onDismissSucceeded() = complete(!keyguard.isKeyguardLocked)
                    override fun onDismissCancelled() = complete(false)
                    override fun onDismissError() = complete(false)
                })
            }
        }
    }
    private fun complete(success: Boolean) {
        CleanupUnlock.complete(requestID, success)
        finish()
    }
    override fun onDestroy() {
        CleanupUnlock.complete(requestID, false)
        super.onDestroy()
    }
}

/** Shared transient presentation, also rendered by Catalog without touching the keyguard. */
internal fun cleanupWakeContent(context: Context): android.view.View = object : android.widget.FrameLayout(context) {
    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        getChildAt(0)?.translationY = -height * 0.05f
    }
}.apply {
    setBackgroundColor(context.getColor(R.color.duck_role_background))
    val body = android.widget.LinearLayout(context).apply {
        orientation = android.widget.LinearLayout.VERTICAL
        gravity = android.view.Gravity.CENTER_HORIZONTAL
        val inset = context.token(R.dimen.duck_space_large)
        setPadding(inset, inset, inset, inset)
        addView(com.google.android.material.progressindicator.CircularProgressIndicator(context).apply {
            isIndeterminate = true
            indicatorSize = context.token(R.dimen.duck_space_large)
            importantForAccessibility = android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, android.widget.LinearLayout.LayoutParams(-2, -2))
        addView(context.lookText(context.getString(R.string.cleanup_waking_title),
            com.google.android.material.R.style.TextAppearance_Material3_TitleMedium).apply {
            gravity = android.view.Gravity.CENTER
            isAccessibilityHeading = true
        }, android.widget.LinearLayout.LayoutParams(-1, -2).apply { topMargin = context.token(R.dimen.duck_space_small) })
        addView(context.lookText(context.getString(R.string.cleanup_waking_note),
            com.google.android.material.R.style.TextAppearance_Material3_BodyMedium, secondary = true).apply {
            gravity = android.view.Gravity.CENTER
        }, android.widget.LinearLayout.LayoutParams(-1, -2).apply { topMargin = context.token(R.dimen.duck_space_xx_small) })
    }
    addView(body, android.widget.FrameLayout.LayoutParams(-1, -2, android.view.Gravity.CENTER))
}
