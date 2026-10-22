package app.backupduck

import android.graphics.Matrix
import android.graphics.RectF
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.widget.ImageView
import kotlin.math.abs

/** The fitted photo yields horizontal input to paging; magnified media owns both axes. */
internal class PhotoZoom(private val image: ImageView, tap: () -> Unit,
    private val swipeUp: () -> Unit, private val swipeDown: () -> Unit,
    private val canZoom: () -> Boolean) {
    private var scale = 1f
    private var x = 0f
    private var y = 0f
    private var downX = 0f
    private var downY = 0f
    private var vertical = false
    private var multiple = false
    private val matrix = Matrix()
    private val slop = android.view.ViewConfiguration.get(image.context).scaledTouchSlop

    fun reset() {
        scale = 1f; x = 0f; y = 0f
        image.scaleType = ImageView.ScaleType.FIT_CENTER
        image.parent?.requestDisallowInterceptTouchEvent(false)
    }
    fun refresh() { if (scale > 1f) apply() }
    private fun apply() {
        val drawable = image.drawable ?: return
        // The first native scale callback can be neutral. Keep both pointers
        // owned until the gesture ends instead of yielding them to the pager.
        if (scale <= 1f) {
            scale = 1f; x = 0f; y = 0f
            image.scaleType = ImageView.ScaleType.FIT_CENTER
            return
        }
        val width = (image.width - image.paddingLeft - image.paddingRight).toFloat()
        val height = (image.height - image.paddingTop - image.paddingBottom).toFloat()
        if (width <= 0 || height <= 0 || drawable.intrinsicWidth <= 0 || drawable.intrinsicHeight <= 0) return
        val fitted = minOf(width / drawable.intrinsicWidth, height / drawable.intrinsicHeight)
        val w = drawable.intrinsicWidth * fitted * scale
        val h = drawable.intrinsicHeight * fitted * scale
        x = x.coerceIn(-((w - width) / 2).coerceAtLeast(0f), ((w - width) / 2).coerceAtLeast(0f))
        y = y.coerceIn(-((h - height) / 2).coerceAtLeast(0f), ((h - height) / 2).coerceAtLeast(0f))
        matrix.setRectToRect(RectF(0f, 0f, drawable.intrinsicWidth.toFloat(), drawable.intrinsicHeight.toFloat()),
            RectF((width-w)/2+x, (height-h)/2+y, (width+w)/2+x, (height+h)/2+y), Matrix.ScaleToFit.CENTER)
        image.scaleType = ImageView.ScaleType.MATRIX
        image.imageMatrix = matrix
    }
    private val pinch = ScaleGestureDetector(image.context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScaleBegin(detector: ScaleGestureDetector): Boolean = canZoom()
        override fun onScale(detector: ScaleGestureDetector): Boolean {
            val next = (scale * detector.scaleFactor).coerceIn(1f, 5f)
            val ratio = next / scale
            val fx = detector.focusX - image.paddingLeft - (image.width-image.paddingLeft-image.paddingRight)/2f
            val fy = detector.focusY - image.paddingTop - (image.height-image.paddingTop-image.paddingBottom)/2f
            x = fx - (fx-x)*ratio; y = fy - (fy-y)*ratio
            scale = next; apply(); return true
        }
    })
    private val gestures = GestureDetector(image.context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(e: MotionEvent) = true
        override fun onSingleTapConfirmed(e: MotionEvent): Boolean { tap(); return true }
        override fun onDoubleTap(e: MotionEvent): Boolean {
            if (!canZoom()) { tap(); return true }
            if (scale > 1f) reset() else {
                scale = 2.5f
                x = (image.width/2f-e.x)*(scale-1f); y = (image.height/2f-e.y)*(scale-1f)
                apply(); image.parent?.requestDisallowInterceptTouchEvent(true)
            }
            return true
        }
        override fun onScroll(e1: MotionEvent?, e2: MotionEvent, distanceX: Float, distanceY: Float): Boolean {
            if (scale > 1f && !pinch.isInProgress) { x -= distanceX; y -= distanceY; apply() }
            return true
        }
    })
    init {
        image.isClickable = true
        image.setOnClickListener { tap() }
        image.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.x; downY = event.y; vertical = false; multiple = false
                    image.parent?.requestDisallowInterceptTouchEvent(scale > 1f)
                }
                MotionEvent.ACTION_POINTER_DOWN -> {
                    multiple = true; image.parent?.requestDisallowInterceptTouchEvent(true)
                }
                MotionEvent.ACTION_MOVE -> if (!multiple && scale == 1f && abs(event.y-downY) > slop &&
                    abs(event.y-downY) > abs(event.x-downX)) {
                    vertical = true; image.parent?.requestDisallowInterceptTouchEvent(true)
                }
            }
            pinch.onTouchEvent(event); gestures.onTouchEvent(event)
            if (event.actionMasked == MotionEvent.ACTION_UP) {
                if (vertical && !multiple && scale == 1f && abs(event.y-downY) > image.context.dp(48)) {
                    if (event.y < downY) swipeUp() else swipeDown()
                }
                image.parent?.requestDisallowInterceptTouchEvent(false)
            }
            if (event.actionMasked == MotionEvent.ACTION_CANCEL) image.parent?.requestDisallowInterceptTouchEvent(false)
            true
        }
    }
}
