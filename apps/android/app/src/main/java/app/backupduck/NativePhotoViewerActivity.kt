package app.backupduck

import android.animation.ValueAnimator
import android.app.ActivityOptions
import android.app.SharedElementCallback
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Rect
import android.graphics.drawable.BitmapDrawable
import android.os.Bundle
import android.os.CancellationSignal
import android.provider.Settings
import android.transition.ChangeBounds
import android.transition.ChangeImageTransform
import android.transition.ChangeTransform
import android.transition.Fade
import android.transition.Transition
import android.transition.TransitionSet
import android.view.View
import android.view.Window
import android.widget.ImageView
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

internal fun photoTransitionName(id: String) = "received-photo:$id"
internal interface PhotoTransitionItems { fun positionOfPhoto(id: String): Int }

/** Use the pixels already displayed, including when the image cache has evicted them. */
internal fun ImageView.photoPoster(id: String): Bitmap? =
    (drawable as? BitmapDrawable)?.bitmap?.takeIf { getTag(R.id.photo_transition_ready) == id }

internal fun Context.photoAnimationsEnabled() = ValueAnimator.areAnimatorsEnabled() &&
    Settings.Global.getFloat(contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) != 0f

/** Android moves the actual tile ImageView to the fitted media ImageView. */
class NativePhotoViewerActivity : BackupDuckActivity() {
    private var content: PhotoDetail.Content? = null
    private var shared = false
    private var entered = false
    private var publishAfterEnter: (() -> Unit)? = null
    private var initialId = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        delegate.localNightMode = getSharedPreferences("appearance", MODE_PRIVATE).getInt("mode", AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        window.requestFeature(Window.FEATURE_ACTIVITY_TRANSITIONS)
        super.onCreate(savedInstanceState)
        // Install the decor/theme defaults before configuring transitions. A null
        // transition set before decor installation can be replaced by theme defaults.
        window.decorView
        val item = intent.getBundleExtra("photo")?.toPhoto() ?: run { finish(); return }
        initialId = item.id
        shared = intent.getBooleanExtra("shared", false) && photoAnimationsEnabled()
        setResult(RESULT_OK, Intent().putExtra(RETURN_ID, item.id))
        val poster = pendingPoster?.takeIf { it.first == item.id }?.second
        pendingPoster = null
        window.setWindowAnimations(0)
        window.sharedElementEnterTransition = if (shared) photoTransition(this) else null
        window.sharedElementReturnTransition = if (shared) photoTransition(this) else null
        window.transitionBackgroundFadeDuration = resources.getInteger(R.integer.duck_motion_enter_ms).toLong()
        entered = savedInstanceState != null || !shared
        if (shared) {
            postponeEnterTransition()
            window.sharedElementEnterTransition.addListener(object : PhotoTransitionListener() {
                override fun onTransitionEnd(transition: Transition) { transition.removeListener(this); finishEntry() }
                override fun onTransitionCancel(transition: Transition) { transition.removeListener(this); finishEntry() }
            })
        }
        // Enter also owns the outgoing shared element on return. Resolve the displayed
        // photo, rather than retaining a stale original image/name after navigation.
        setEnterSharedElementCallback(object : SharedElementCallback() {
            override fun onMapSharedElements(names: MutableList<String>, elements: MutableMap<String, View>) {
                elements.clear()
                val preview = content?.preview
                if (shared && preview != null && preview.drawable is BitmapDrawable) {
                    names.firstOrNull()?.let { elements[it] = preview }
                } else names.clear()
            }
        })
        val actions = ReceivedPhotosPage.Actions({}, {}, { it(false) }, { photo, done ->
            lifecycleScope.launch {
                val ok = withContext(Dispatchers.IO) { runCatching {
                    NativeBridge.request(org.json.JSONObject().put("op", "retry_processing").put("id", photo.id))
                }.isSuccess }
                done(ok)
            }
        }, {})
        content = PhotoDetail(this, PhotoImages(this), actions).content(item,
            dismiss = ::finishAfterTransition, isShowing = { !isFinishing && !isDestroyed },
            sharedName = photoTransitionName(item.id), poster = poster,
            ready = { hasImage ->
                if (!hasImage) {
                    shared = false; window.sharedElementEnterTransition = null
                    window.sharedElementReturnTransition = null; finishEntry()
                }
                // Post out of pre-draw so the destination's image matrix and
                // insets are committed before the coordinator captures its bounds.
                content?.preview?.post { startPostponedEnterTransition() }
            }, afterEnter = { publish -> if (entered) publish() else publishAfterEnter = publish })
        setContentView(content!!.root)
        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(getColor(android.R.color.black)))
        // Never fade a parent of the shared image: it would also fade the photo
        // out before its return flight has reached the grid.
        window.enterTransition = photoChromeFade(this, content!!.root)
        window.returnTransition = photoChromeFade(this, content!!.root)
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = getColor(android.R.color.transparent)
        window.navigationBarColor = getColor(android.R.color.transparent)
        if (android.os.Build.VERSION.SDK_INT >= 29) window.isNavigationBarContrastEnforced = false
        androidx.core.view.WindowCompat.getInsetsController(window, content!!.root).apply {
            isAppearanceLightStatusBars = false; isAppearanceLightNavigationBars = false
        }
        onBackPressedDispatcher.addCallback(this, object : androidx.activity.OnBackPressedCallback(true) {
            override fun handleOnBackPressed() { if (content?.closePanel?.invoke() != true) finishAfterTransition() }
        })
    }
    private fun finishEntry() {
        entered = true; publishAfterEnter?.invoke(); publishAfterEnter = null
    }
    override fun finishAfterTransition() {
        val id = content?.preview?.transitionName?.removePrefix("received-photo:") ?: initialId
        setResult(RESULT_OK, Intent().putExtra(RETURN_ID, id))
        publishAfterEnter = null
        content?.cancel?.invoke()
        // This window still owns the bars while its canvas fades over the grid.
        // Adopt the source appearance at return start, rather than focus transfer.
        androidx.core.view.WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = intent.getBooleanExtra(RETURN_LIGHT_STATUS, false)
            isAppearanceLightNavigationBars = intent.getBooleanExtra(RETURN_LIGHT_NAVIGATION, false)
        }
        if (!photoAnimationsEnabled()) {
            window.returnTransition = null; window.sharedElementReturnTransition = null
            finish(); overridePendingTransition(0, 0)
        } else if (!shared) {
            finish(); overridePendingTransition(0, R.anim.photo_fade_out)
        } else super.finishAfterTransition()
    }
    override fun onDestroy() {
        publishAfterEnter = null; content?.cancel?.invoke(); content = null
        super.onDestroy()
    }
    companion object {
        private const val RETURN_ID = "returnedPhotoId"
        private const val RETURN_LIGHT_STATUS = "returnLightStatus"
        private const val RETURN_LIGHT_NAVIGATION = "returnLightNavigation"
        // One bounded poster handoff, consumed by onCreate. No Bitmap goes through Binder.
        private var pendingPoster: Pair<String, Bitmap>? = null
        internal fun open(activity: MainActivity, item: HistoryItem, source: ImageView?, list: RecyclerView) {
            val name = photoTransitionName(item.id)
            var returnId = item.id
            val animate = activity.photoAnimationsEnabled()
            val poster = source?.photoPoster(item.id)
            val shared = source?.takeIf {
                animate && it.isAttachedToWindow && it.rootView === activity.window.decorView &&
                    poster != null
            }
            // Reassert the identity at the actual launch, after any selection rebind.
            shared?.transitionName = name
            pendingPoster = poster?.let { item.id to it }
            activity.window.sharedElementExitTransition = if (shared != null) photoTransition(activity) else null
            activity.window.sharedElementReenterTransition = if (shared != null) photoTransition(activity) else null
            // Keep the mounted grid visible and stationary beneath the media flight.
            activity.window.exitTransition = null
            activity.window.reenterTransition = null
            var returning = false
            activity.setExitSharedElementCallback(object : SharedElementCallback() {
                override fun onMapSharedElements(names: MutableList<String>, elements: MutableMap<String, View>) {
                    // The framework has already captured the outgoing view. Do not
                    // replace it with a visibility-dependent return lookup.
                    if (!returning) return
                    val tile = list.transitionImage(photoTransitionName(returnId))
                    elements.clear()
                    if (tile != null) names.firstOrNull()?.let { elements[it] = tile } else names.clear()
                }
                override fun onRejectSharedElements(rejected: MutableList<View>) {
                    // A removed photo has no landing tile. Fade its snapshot locally
                    // instead of letting Android run its longer default rejection fade.
                    val overlay = (activity.window.decorView as android.view.ViewGroup).overlay
                    rejected.forEach { snapshot ->
                        if (activity.photoAnimationsEnabled()) {
                            overlay.add(snapshot)
                            snapshot.animate().alpha(0f)
                                .setDuration(activity.resources.getInteger(R.integer.duck_motion_text_ms).toLong())
                                .withEndAction { overlay.remove(snapshot) }.start()
                        }
                    }
                    rejected.clear()
                }
            })
            activity.restorePhotoAnchor = { data ->
                returning = true
                returnId = data?.getStringExtra(RETURN_ID) ?: item.id
                val manager = list.layoutManager as? GridLayoutManager
                val position = (list.adapter as? PhotoTransitionItems)?.positionOfPhoto(returnId) ?: -1
                if (shared != null) {
                    activity.postponeEnterTransition()
                    val tile = manager?.findViewByPosition(position)
                    if (position >= 0 && manager != null && (tile == null ||
                        tile.top < list.paddingTop || tile.bottom > list.height - list.paddingBottom)) {
                        manager.scrollToPositionWithOffset(position, 0)
                    }
                    // Await both layout and the rebound thumbnail. A removed item or
                    // unavailable rendition clears the mapping and uses the short fade.
                    list.awaitTransitionImage(photoTransitionName(returnId), position >= 0) {
                        activity.startPostponedEnterTransition()
                    }
                }
            }
            val bars = androidx.core.view.WindowCompat.getInsetsController(activity.window, activity.window.decorView)
            val intent = Intent(activity, NativePhotoViewerActivity::class.java)
                .putExtra("photo", item.toBundle()).putExtra("shared", shared != null)
                .putExtra(RETURN_LIGHT_STATUS, bars.isAppearanceLightStatusBars)
                .putExtra(RETURN_LIGHT_NAVIGATION, bars.isAppearanceLightNavigationBars)
            if (shared != null) activity.startActivity(intent,
                ActivityOptions.makeSceneTransitionAnimation(activity, shared, name).toBundle())
            else {
                activity.startActivity(intent, ActivityOptions.makeCustomAnimation(activity,
                    if (animate) R.anim.photo_fade_in else 0, 0).toBundle())
            }
        }
    }
}
private open class PhotoTransitionListener : Transition.TransitionListener {
    override fun onTransitionStart(transition: Transition) {}
    override fun onTransitionEnd(transition: Transition) {}
    override fun onTransitionCancel(transition: Transition) {}
    override fun onTransitionPause(transition: Transition) {}
    override fun onTransitionResume(transition: Transition) {}
}
private fun photoTransition(context: Context) = TransitionSet().apply {
    ordering = TransitionSet.ORDERING_TOGETHER
    addTransition(ChangeBounds()); addTransition(ChangeTransform()); addTransition(ChangeImageTransform())
    duration = context.resources.getInteger(R.integer.duck_motion_enter_ms).toLong()
    interpolator = android.view.animation.AnimationUtils.loadInterpolator(context, android.R.interpolator.fast_out_slow_in)
}
private fun photoChromeFade(context: Context, root: View) = Fade().apply {
    duration = if (context.photoAnimationsEnabled()) context.resources.getInteger(R.integer.duck_motion_text_ms).toLong() else 0
    // PhotoDetail owns the toolbar, media and information as direct children.
    (root as android.view.ViewGroup).let { group ->
        for (i in 0 until group.childCount) {
            group.getChildAt(i).takeUnless { it is ImageView }?.let { addTarget(it) }
        }
    }
}
/** A placeholder or a recycled tile with another identity can never be a return target. */
private fun View.transitionImage(name: String): ImageView? {
    if (!isAttachedToWindow) return null
    if (this is ImageView && transitionName == name && drawable is BitmapDrawable &&
        getTag(R.id.photo_transition_ready) == name.removePrefix("received-photo:") &&
        getGlobalVisibleRect(Rect())) return this
    if (this is android.view.ViewGroup) for (i in 0 until childCount) {
        getChildAt(i).transitionImage(name)?.let { return it }
    }
    return null
}
private fun RecyclerView.awaitTransitionImage(name: String, exists: Boolean, ready: () -> Unit) {
    var completed = false
    lateinit var listener: android.view.ViewTreeObserver.OnPreDrawListener
    val timeout = Runnable {
        if (!completed) {
            completed = true
            if (viewTreeObserver.isAlive) viewTreeObserver.removeOnPreDrawListener(listener)
            ready()
        }
    }
    listener = android.view.ViewTreeObserver.OnPreDrawListener {
        if (!exists || !isAttachedToWindow || transitionImage(name) != null) {
            removeCallbacks(timeout); timeout.run()
        }
        true
    }
    viewTreeObserver.addOnPreDrawListener(listener)
    postDelayed(timeout, 1000)
    requestLayout()
}
internal fun HistoryItem.toBundle() = Bundle().apply {
    putLong("cursor", cursor); putString("id", id); putString("filename", filename); putString("kind", kind)
    putLong("total", totalBytes); putLong("confirmed", confirmedBytes); putString("receipt", receipt)
    putString("processing", processing); putString("error", processingError); putBoolean("released", originalsReleased)
    putString("releaseReason", releaseReason); putString("senders", senderNames)
    capturedAtMs?.let { putLong("captured", it) }; receivedAtMs?.let { putLong("received", it) }
    publishedAtMs?.let { putLong("published", it) }; burstPrimary?.let { putBoolean("burst", it) }
}
internal fun Bundle.toPhoto() = HistoryItem(getLong("cursor"), getString("id")!!, getString("filename")!!,
    getString("kind")!!, getLong("total"), getLong("confirmed"), getString("receipt")!!,
    getString("processing")!!, getString("error"), getBoolean("released"), getString("releaseReason"), getString("senders").orEmpty(),
    getLong("captured").takeIf { containsKey("captured") }, getBoolean("burst").takeIf { containsKey("burst") },
    getLong("received").takeIf { containsKey("received") }, getLong("published").takeIf { containsKey("published") })

/** Share a verified published copy; synthetic catalog photos get isolated, explicitly synthetic files. */
internal fun photoShareCopy(context: Context, item: HistoryItem, signal: CancellationSignal): GalleryPreviewCopy? {
    signal.throwIfCanceled()
    ReceiverEnvironment.previewImage?.let { synthetic ->
        val bitmap = synthetic(item, 1440, 1440) ?: return null
        signal.throwIfCanceled()
        val folder = File(context.cacheDir, "photo-shares").apply { mkdirs() }
        val file = File(folder, "synthetic-${item.id.hashCode()}.jpg")
        file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 90, it) }
        signal.throwIfCanceled()
        return GalleryPreviewCopy(FileProvider.getUriForFile(context, "${context.packageName}.updates", file), "image/jpeg", null)
    }
    return GalleryPreview.resolve(context, item, null, signal)
}
