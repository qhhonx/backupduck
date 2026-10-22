package app.backupduck

import android.content.ClipData
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.drawable.GradientDrawable
import android.os.CancellationSignal
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.coordinatorlayout.widget.CoordinatorLayout
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.doOnPreDraw
import androidx.core.widget.NestedScrollView
import androidx.lifecycle.lifecycleScope
import com.google.android.material.R as M
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDragHandleView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.withContext

/** One shared viewer composition for grids, recent photos and history. */
internal class PhotoDetail(private val activity: androidx.appcompat.app.AppCompatActivity,
    private val images: PhotoImages, private val actions: ReceivedPhotosPage.Actions) {
    internal class Content(val root: View, val preview: ImageView, val closePanel: () -> Boolean, val cancel: () -> Unit)

    fun content(initialItem: HistoryItem, dismiss: () -> Unit, isShowing: () -> Boolean,
        sharedName: String? = null, poster: Bitmap? = null, ready: (Boolean) -> Unit = {},
        afterEnter: (() -> Unit) -> Unit = { it() }): Content = with(activity) {
        var item = initialItem
        // design-exception: media canvas and overlay controls are always black/white, independent of app appearance.
        val black = getColor(android.R.color.black)
        val white = getColor(android.R.color.white)
        val root = CoordinatorLayout(this).apply { isTransitionGroup = false }
        val preview = ImageView(this).apply {
            transitionName = sharedName; scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = item.filename
        }
        root.addView(preview, CoordinatorLayout.LayoutParams(-1, -1))
        val signal = CancellationSignal()
        var work: Job? = null
        var lookup: Job? = null
        var metadataWork: Job? = null
        var shareWork: Job? = null
        val top = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val bottom = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        fun scrim(reverse: Boolean) = GradientDrawable(
            if (reverse) GradientDrawable.Orientation.BOTTOM_TOP else GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(androidx.core.graphics.ColorUtils.setAlphaComponent(black, 180), android.graphics.Color.TRANSPARENT))
        top.background = scrim(false); bottom.background = scrim(true)
        root.addView(top, CoordinatorLayout.LayoutParams(-1, -2).apply { gravity = Gravity.TOP })
        root.addView(bottom, CoordinatorLayout.LayoutParams(-1, -2).apply { gravity = Gravity.BOTTOM })
        val bar = FrameLayout(this)
        val barHeight = resources.getDimensionPixelSize(M.dimen.m3_appbar_size_compact)
        top.addView(bar, LinearLayout.LayoutParams(-1, barHeight))
        fun icon(resource: Int, description: Int, click: () -> Unit) = ImageButton(this).apply {
            setImageResource(resource); imageTintList = ColorStateList.valueOf(white)
            contentDescription = getString(description)
            val attr = android.util.TypedValue(); theme.resolveAttribute(android.R.attr.selectableItemBackgroundBorderless, attr, true)
            setBackgroundResource(attr.resourceId); setOnClickListener { click() }
        }
        val back = icon(R.drawable.ic_back, R.string.viewer_back, dismiss)
        bar.addView(back, FrameLayout.LayoutParams(dp(48), -1, Gravity.START).apply { marginStart = dp(4) })
        val date = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; isClickable = true; isFocusable = true
            contentDescription = getString(R.string.viewer_details)
        }
        fun text(value: String, style: Int, color: Int? = null) = lookText(value, style).apply { color?.let(::setTextColor) }
        fun dateText(skeleton: String) = item.capturedAtMs?.let {
            android.icu.text.DateFormat.getInstanceForSkeleton(skeleton, resources.configuration.locales[0]).format(java.util.Date(it))
        }
        date.addView(text(dateText("MMMd")?.plus(" ›") ?: getString(R.string.photos_taken_unknown), M.style.TextAppearance_Material3_TitleMedium, white).apply { gravity = Gravity.CENTER })
        date.addView(text(dateText("jm").orEmpty(), M.style.TextAppearance_Material3_BodySmall, white).apply { gravity = Gravity.CENTER })
        bar.addView(date, FrameLayout.LayoutParams(-1, -1).apply { setMargins(dp(56), 0, dp(56), 0) })
        var openCopy: GalleryPreviewCopy? = null
        var immersive = false
        val feedback = text("", M.style.TextAppearance_Material3_BodyMedium, white).apply {
            visibility = View.GONE; gravity = Gravity.CENTER; accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        fun message(value: Int) { feedback.setText(value); feedback.visibility = View.VISIBLE }
        fun openPhotos() {
            val copy = openCopy ?: return
            runCatching { startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(copy.uri, copy.mime)
                .setPackage("com.google.android.apps.photos").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)) }
                .onFailure { message(R.string.photos_open_failed) }
        }
        val more = icon(R.drawable.ic_viewer_more, R.string.viewer_more) {}
        bar.addView(more, FrameLayout.LayoutParams(dp(48), -1, Gravity.END))
        more.setOnClickListener {
            androidx.appcompat.widget.PopupMenu(this, more).apply {
                menu.add(R.string.viewer_history).setOnMenuItemClickListener {
                    startActivity(Intent(activity, MainActivity::class.java).putExtra("destination", "transfers")
                        .putExtra("surface", "photo-history").putExtra("record", item.toBundle())
                        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
                    dismiss(); true
                }
                menu.add(R.string.viewer_open_photos).apply { isVisible = openCopy != null }.setOnMenuItemClickListener { openPhotos(); true }
            }.show()
        }
        val pill = lookButton(getString(R.string.viewer_save_failed), LookButton.TONAL) {}.apply {
            setText(R.string.viewer_save_failed); visibility = if (item.cause == PhotoCause.NOT_SAVED) View.VISIBLE else View.GONE
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        top.addView(pill, LinearLayout.LayoutParams(-2, -2).apply { gravity = Gravity.CENTER_HORIZONTAL; topMargin = token(R.dimen.duck_space_small) })
        top.addView(feedback, LinearLayout.LayoutParams(-1, -2))
        top.setPadding(0, 0, 0, token(R.dimen.duck_space_large))
        val actionRow = LinearLayout(this).apply { gravity = Gravity.CENTER; orientation = LinearLayout.HORIZONTAL }
        bottom.addView(actionRow, LinearLayout.LayoutParams(-1, -2))
        fun action(resource: Int, label: Int, click: () -> Unit): View {
            val cell = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; isClickable = true; isFocusable = true
                contentDescription = getString(label); setPadding(dp(4), dp(8), dp(4), dp(8))
                val attr = android.util.TypedValue(); theme.resolveAttribute(android.R.attr.selectableItemBackground, attr, true)
                setBackgroundResource(attr.resourceId); setOnClickListener { click() }
            }
            cell.addView(ImageView(this).apply { setImageResource(resource); imageTintList = ColorStateList.valueOf(white); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
                LinearLayout.LayoutParams(dp(24), dp(24)))
            cell.addView(text(getString(if (label == R.string.viewer_open_photos) R.string.viewer_gallery_action else label), M.style.TextAppearance_Material3_LabelMedium, white).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL; minLines = 1; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_small) })
            actionRow.addView(cell, LinearLayout.LayoutParams(0, -2, 1f))
            return cell
        }
        action(R.drawable.ic_viewer_share, R.string.photos_share) {
            if (shareWork?.isActive == true) return@action
            shareWork = lifecycleScope.launch {
                val copy = withContext(Dispatchers.IO) { runCatching { photoShareCopy(activity, item, signal) }.getOrNull() }
                if (!isShowing()) return@launch
                if (copy == null) message(R.string.photos_share_unavailable) else {
                    runCatching { startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                        type = copy.mime; putExtra(Intent.EXTRA_STREAM, copy.uri)
                        clipData = ClipData.newRawUri("", copy.uri); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }, getString(R.string.photos_share))) }.onFailure { message(R.string.photos_share_unavailable) }
                }
            }
        }
        val openAction = action(R.drawable.ic_photo, R.string.viewer_open_photos, ::openPhotos).apply { visibility = View.GONE }
        // The dark information surface keeps light status indicators legible even over a bright photo.
        val statusScrim = View(this).apply {
            setBackgroundColor(androidx.core.graphics.ColorUtils.setAlphaComponent(black, 180))
            visibility = View.GONE
        }
        root.addView(statusScrim, CoordinatorLayout.LayoutParams(-1, 0).apply { gravity = Gravity.TOP })
        val panel = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val sheet = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                val r = dp(16).toFloat(); cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
                setColor(if (isDarkAppearance()) getColor(R.color.duck_role_background) else white)
            }
        }
        val handle = BottomSheetDragHandleView(this).apply { imageTintList = ColorStateList.valueOf(androidx.core.graphics.ColorUtils.setAlphaComponent(getColor(R.color.duck_role_secondary_text), 70)) }
        sheet.addView(handle, LinearLayout.LayoutParams(-1, dp(32)))
        val scroll = NestedScrollView(this).apply { addView(panel); isFillViewport = false }
        sheet.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        val behavior = BottomSheetBehavior<LinearLayout>().apply { isHideable = true; skipCollapsed = true; isFitToContents = true }
        root.addView(sheet, CoordinatorLayout.LayoutParams(-1, -1).apply { this.behavior = behavior; gravity = Gravity.BOTTOM })
        behavior.state = BottomSheetBehavior.STATE_HIDDEN
        // Keep a native Back control above the photo while information replaces the app bar.
        val detailBack = lookButton("", LookButton.TONAL, icon = R.drawable.ic_back) {
            behavior.state = BottomSheetBehavior.STATE_HIDDEN
        }.apply {
            contentDescription = getString(R.string.viewer_back)
            iconPadding = 0; iconSize = dp(24)
            iconGravity = com.google.android.material.button.MaterialButton.ICON_GRAVITY_TEXT_START
            setPadding(0, 0, 0, 0); insetTop = 0; insetBottom = 0
            minWidth = 0; minimumWidth = 0; minHeight = 0; minimumHeight = 0
            backgroundTintList = ColorStateList.valueOf(if (isDarkAppearance()) getColor(R.color.duck_role_elevated_surface) else white)
            iconTint = ColorStateList.valueOf(getColor(R.color.duck_role_primary_text))
            visibility = View.GONE
        }
        root.addView(detailBack, CoordinatorLayout.LayoutParams(dp(40), dp(40)).apply {
            gravity = Gravity.TOP or Gravity.START; marginStart = token(R.dimen.duck_space_small)
        })
        var sheetOpen = false
        var metadataLoaded = false
        var systemTop = 0
        var sheetHeight = 0
        val controller = WindowCompat.getInsetsController(window, root)
        fun bars() {
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            if (immersive) controller.hide(WindowInsetsCompat.Type.systemBars()) else controller.show(WindowInsetsCompat.Type.systemBars())
            statusScrim.visibility = if (sheetOpen && isDarkAppearance() && !immersive) View.VISIBLE else View.GONE
            val light = sheetOpen && !isDarkAppearance()
            controller.isAppearanceLightStatusBars = light
            controller.isAppearanceLightNavigationBars = light
        }
        fun chrome(fraction: Float) {
            // Keep the fitted image bounds unchanged; information translates the media node only.
            // The sheet reaches the window edge; media travel uses the viewport below the status inset.
            val mediaFraction = (root.height - systemTop).toFloat() / root.height.coerceAtLeast(1)
            preview.translationY = -sheetHeight * mediaFraction * fraction
            detailBack.alpha = fraction
            detailBack.visibility = if (fraction > 0f && !immersive) View.VISIBLE else View.GONE
            val alpha = if (immersive) 0f else 1f - fraction
            top.alpha = alpha; bottom.alpha = alpha
            top.visibility = if (alpha == 0f) View.INVISIBLE else View.VISIBLE
            bottom.visibility = if (alpha == 0f) View.INVISIBLE else View.VISIBLE
        }
        behavior.addBottomSheetCallback(object : BottomSheetBehavior.BottomSheetCallback() {
            override fun onSlide(bottomSheet: View, offset: Float) { chrome(((root.height - sheet.top).toFloat() / sheetHeight.coerceAtLeast(1)).coerceIn(0f, 1f)) }
            override fun onStateChanged(bottomSheet: View, state: Int) {
                sheetOpen = state != BottomSheetBehavior.STATE_HIDDEN
                bars()
                if (state == BottomSheetBehavior.STATE_HIDDEN) { chrome(0f); date.requestFocus() }
            }
        })
        fun group(): LinearLayout = lookGroup(panel).also {
            (it.parent as View).let { card -> (card.layoutParams as LinearLayout.LayoutParams).topMargin = token(R.dimen.duck_space_large) }
        }
        panel.setPadding(token(R.dimen.duck_space_medium), 0, token(R.dimen.duck_space_medium), token(R.dimen.duck_space_large))
        panel.addView(text(listOfNotNull(dateText("yMMMEd"), dateText("jm")).joinToString(" · ").ifEmpty { getString(R.string.photos_taken_unknown) },
            M.style.TextAppearance_Material3_TitleMedium).apply { isAccessibilityHeading = true }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_small) })
        panel.addView(text(item.filename, M.style.TextAppearance_Material3_BodyMedium), LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_large) })
        val facts = group()
        val sender = item.senders.joinToString(getString(R.string.photos_list_separator)).ifEmpty { null }
        lookRow(facts, R.drawable.ic_clock,
            if (item.receipt == "received") sender?.let { getString(R.string.photos_received_from, it) } ?: getString(R.string.photos_received)
            else sender?.let { getString(R.string.photos_receiving_from, it) } ?: getString(R.string.photos_receiving),
            item.receivedAtMs?.let { shortTime(activity, it) })
        val saveSupport = lookRow(facts, if (item.processing == "complete") R.drawable.ic_check else R.drawable.ic_clock,
            getString(when { item.processing == "complete" -> R.string.photos_in_photos
                item.processing == "failed" -> R.string.photos_not_saved
                item.receipt == "received" -> R.string.photos_saving
                else -> R.string.photos_after_arrival }),
            item.publishedAtMs?.takeIf { item.processing == "complete" }?.let { shortTime(activity, it) }
                ?: item.processingError?.let { publicationReason(activity, it) })
        val retry = if (item.cause == PhotoCause.NOT_SAVED) lookButton(getString(R.string.photos_try_again), LookButton.TONAL) {}.also {
            panel.addView(it, LinearLayout.LayoutParams(-2, -2).apply { topMargin = token(R.dimen.duck_space_small) })
        } else null
        fun retrySave() {
            pill.isEnabled = false; retry?.isEnabled = false; pill.setText(R.string.viewer_retrying)
            saveSupport.visibility = View.VISIBLE; saveSupport.text = getString(R.string.viewer_retrying)
            actions.retry(item) { ok ->
                if (!isShowing()) return@retry
                pill.isEnabled = true; retry?.isEnabled = true
                pill.setText(if (ok) R.string.photos_trying_again else R.string.viewer_save_failed)
                saveSupport.text = getString(if (ok) R.string.photos_trying_again else R.string.photos_retry_failed)
            }
        }
        pill.setOnClickListener { retrySave() }; retry?.setOnClickListener { retrySave() }
        val files = group()
        val fileInfo = lookRow(files, R.drawable.ic_photo, getString(R.string.viewer_file_details),
            listOf(FormatterSize(activity, item.totalBytes), item.filename.substringAfterLast('.', "").uppercase()).filter { it.isNotBlank() }.joinToString(" · "))
        fun showDetails() {
            immersive = false; sheetOpen = true; bars()
            behavior.state = BottomSheetBehavior.STATE_EXPANDED
            if (!metadataLoaded) {
                metadataLoaded = true
                metadataWork = lifecycleScope.launch {
                    val info = withContext(Dispatchers.IO) { readPhotoMetadata(activity, item, signal) }
                    if (isShowing() && info.isNotEmpty()) { fileInfo.visibility = View.VISIBLE; fileInfo.text = listOf(fileInfo.text.toString(), info.joinToString("\n")).joinToString("\n") }
                }
            }
        }
        date.setOnClickListener { showDetails() }
        action(R.drawable.ic_info, R.string.viewer_details, ::showDetails)
        var downX = 0f; var downY = 0f
        preview.setOnTouchListener { _, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> { downX = e.x; downY = e.y; true }
                MotionEvent.ACTION_UP -> {
                    val dy = e.y - downY; val dx = e.x - downX
                    when {
                        dy < -dp(48) && kotlin.math.abs(dy) > kotlin.math.abs(dx) -> showDetails()
                        dy > dp(48) && sheetOpen -> behavior.state = BottomSheetBehavior.STATE_HIDDEN
                        kotlin.math.abs(dy) < dp(16) && kotlin.math.abs(dx) < dp(16) -> {
                            preview.performClick(); immersive = !immersive; chrome(0f); bars()
                        }
                    }; true
                }
                else -> true
            }
        }
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val safe = insets.getInsetsIgnoringVisibility(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            systemTop = safe.top
            statusScrim.layoutParams = statusScrim.layoutParams.apply { height = safe.top }
            detailBack.layoutParams = (detailBack.layoutParams as CoordinatorLayout.LayoutParams).apply { topMargin = safe.top + token(R.dimen.duck_space_small) }
            top.setPadding(safe.left, safe.top, safe.right, token(R.dimen.duck_space_xx_large))
            bottom.setPadding(safe.left, token(R.dimen.duck_space_xx_large), safe.right, safe.bottom)
            sheet.setPadding(safe.left, 0, safe.right, safe.bottom)
            insets
        }
        root.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            val h = (root.height * .65f).toInt().coerceAtMost(root.height - systemTop - dp(96))
            if (h > 0 && h != sheetHeight) { sheetHeight = h; sheet.layoutParams = sheet.layoutParams.apply { height = h } }
        }
        var hasPreview = false
        (poster ?: images.cached(item, (resources.displayMetrics.widthPixels / 4).coerceIn(160, 384),
            (resources.displayMetrics.widthPixels / 4).coerceIn(160, 384)))?.let { preview.setImageBitmap(it); hasPreview = true }
        fun load() {
            work = images.load(item, resources.displayMetrics.widthPixels.coerceAtMost(1440), resources.displayMetrics.heightPixels.coerceAtMost(2560), signal) { bitmap ->
                if (bitmap != null && isShowing()) {
                    fun publish() { if (isShowing()) preview.setImageBitmap(bitmap) }
                    if (hasPreview) afterEnter(::publish) else publish()
                } else if (!hasPreview && isShowing()) {
                    preview.scaleType = ImageView.ScaleType.CENTER
                    preview.setImageResource(R.drawable.ic_photo)
                    preview.imageTintList = ColorStateList.valueOf(white)
                    preview.contentDescription = getString(R.string.photos_preview_unavailable)
                }
                if (!hasPreview) preview.doOnPreDraw { ready(bitmap != null) }
            }
        }
        if (hasPreview) preview.doOnPreDraw { ready(true); afterEnter(::load) } else load()
        lookup = lifecycleScope.launch {
            openCopy = withContext(Dispatchers.IO) { runCatching { GalleryPreview.resolve(activity, item, null, signal) }.getOrNull() }
            if (isShowing()) openAction.visibility = if (openCopy == null) View.GONE else View.VISIBLE
        }
        val observations = lifecycleScope.launch {
            repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                ReceiverProgress.snapshot.collect { progress ->
                    val next = item.withLive(progress[item.id])
                    if (next.processing != item.processing || next.processingError != item.processingError) {
                        item = next
                        val title = (saveSupport.parent as LinearLayout).getChildAt(0) as TextView
                        title.setText(when { item.processing == "complete" -> R.string.photos_in_photos
                            item.processing == "failed" -> R.string.photos_not_saved
                            else -> R.string.photos_saving })
                        saveSupport.text = item.processingError?.let { publicationReason(activity, it) }.orEmpty()
                        saveSupport.visibility = if (saveSupport.text.isEmpty()) View.GONE else View.VISIBLE
                        pill.visibility = if (item.cause == PhotoCause.NOT_SAVED) View.VISIBLE else View.GONE
                        pill.setText(R.string.viewer_save_failed)
                        retry?.visibility = pill.visibility
                        if (item.processing == "complete") {
                            openCopy = withContext(Dispatchers.IO) { runCatching { GalleryPreview.resolve(activity, item, null, signal) }.getOrNull() }
                            openAction.visibility = if (openCopy == null) View.GONE else View.VISIBLE
                        }
                    }
                }
            }
        }
        Content(root, preview, {
            if (sheetOpen) { behavior.state = BottomSheetBehavior.STATE_HIDDEN; true }
            else if (immersive) { immersive = false; chrome(0f); bars(); true } else false
        }) { signal.cancel(); observations.cancel(); work?.cancel(); lookup?.cancel(); metadataWork?.cancel(); shareWork?.cancel() }
    }
}

private fun android.content.Context.isDarkAppearance() = resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK == android.content.res.Configuration.UI_MODE_NIGHT_YES
private fun FormatterSize(context: android.content.Context, bytes: Long) = android.text.format.Formatter.formatFileSize(context, bytes)

/** Read original metadata on demand; a rendition's dimensions are never presented as the original's. */
private fun readPhotoMetadata(context: android.content.Context, item: HistoryItem, signal: CancellationSignal): List<String> {
    val copy = runCatching { GalleryPreview.resolve(context, item, null, signal) }.getOrNull() ?: return emptyList()
    signal.throwIfCanceled()
    val result = mutableListOf<String>()
    if (copy.mime.startsWith("image/")) {
        runCatching {
            android.graphics.ImageDecoder.decodeBitmap(android.graphics.ImageDecoder.createSource(context.contentResolver, copy.uri)) { decoder, info, _ ->
                result += "${info.size.width} × ${info.size.height}"
                decoder.setTargetSize(1, 1)
                decoder.allocator = android.graphics.ImageDecoder.ALLOCATOR_SOFTWARE
            }.recycle()
        }
        runCatching { context.contentResolver.openInputStream(copy.uri)?.use { input ->
            val exif = androidx.exifinterface.media.ExifInterface(input)
            fun attribute(tag: String) = exif.getAttribute(tag)?.takeIf { it.isNotBlank() }
            listOfNotNull(attribute(androidx.exifinterface.media.ExifInterface.TAG_MAKE), attribute(androidx.exifinterface.media.ExifInterface.TAG_MODEL))
                .distinct().joinToString(" ").takeIf { it.isNotBlank() }?.let { result += it }
            val aperture = exif.getAttributeDouble(androidx.exifinterface.media.ExifInterface.TAG_F_NUMBER, 0.0).takeIf { it > 0 }
            val exposure = exif.getAttributeDouble(androidx.exifinterface.media.ExifInterface.TAG_EXPOSURE_TIME, 0.0).takeIf { it > 0 }
            val focal = exif.getAttributeDouble(androidx.exifinterface.media.ExifInterface.TAG_FOCAL_LENGTH, 0.0).takeIf { it > 0 }
            val iso = attribute(androidx.exifinterface.media.ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY)
            val numbers = java.text.NumberFormat.getNumberInstance(context.resources.configuration.locales[0]).apply { maximumFractionDigits = 2 }
            listOfNotNull(aperture?.let { "f/${numbers.format(it)}" }, exposure?.let { if (it < 1) "1/${kotlin.math.round(1 / it).toInt()} s" else "${numbers.format(it)} s" },
                iso?.let { "ISO $it" }, focal?.let { "${numbers.format(it)} mm" })
                .joinToString(" · ").takeIf { it.isNotBlank() }?.let { result += it }
        } }
    } else runCatching {
        android.media.MediaMetadataRetriever().use { media ->
            media.setDataSource(context, copy.uri)
            val width = media.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val height = media.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            if (width != null && height != null) result += "$width × $height"
        }
    }
    return result
}

private fun publicationReason(context: android.content.Context, error: String) = context.getString(when (error) {
    "storage_full", "insufficient_storage", "no_space" -> R.string.viewer_storage_full
    "conversion_required" -> R.string.receiver_item_conversion_required
    "unsupported" -> R.string.receiver_item_failed_unsupported
    else -> R.string.viewer_save_reason_unknown
})
