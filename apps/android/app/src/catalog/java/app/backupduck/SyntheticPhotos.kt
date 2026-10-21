package app.backupduck

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import kotlin.random.Random

/**
 * Procedural fallback when the optional catalog media pool is unavailable.
 * Each item id always draws the same scene: a sky, a sun or moon,
 * layered ridges fading into the haze, and water or a meadow in front.
 * Synthetic illustration only; these colors never reach the app.
 */
internal object SyntheticPhotos {
    private class Sky(val top: Int, val horizon: Int, val sun: Int, val ridge: Int, val ground: Int)

    private val skies = listOf(
        Sky(hsv(212f, .55f, .86f), hsv(195f, .18f, .98f), hsv(48f, .12f, 1f), hsv(214f, .35f, .55f), hsv(118f, .45f, .52f)),
        Sky(hsv(262f, .45f, .55f), hsv(22f, .62f, .98f), hsv(40f, .55f, 1f), hsv(280f, .35f, .35f), hsv(250f, .30f, .28f)),
        Sky(hsv(205f, .30f, .70f), hsv(205f, .10f, .90f), hsv(0f, 0f, .97f), hsv(205f, .20f, .45f), hsv(90f, .25f, .45f)),
        Sky(hsv(226f, .70f, .22f), hsv(250f, .45f, .45f), hsv(52f, .10f, .95f), hsv(232f, .45f, .16f), hsv(232f, .40f, .14f)),
        Sky(hsv(198f, .45f, .92f), hsv(42f, .30f, .99f), hsv(46f, .40f, 1f), hsv(28f, .40f, .55f), hsv(38f, .45f, .80f)),
    )

    private fun hsv(h: Float, s: Float, v: Float) = Color.HSVToColor(floatArrayOf(h, s, v))

    private fun mix(a: Int, b: Int, t: Float) = Color.rgb(
        (Color.red(a) + (Color.red(b) - Color.red(a)) * t).toInt(),
        (Color.green(a) + (Color.green(b) - Color.green(a)) * t).toInt(),
        (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).toInt())

    fun draw(id: String, width: Int, height: Int): Bitmap {
        // Scramble the id so neighbouring ids draw unrelated scenes.
        val random = Random(id.hashCode() * -7046029254386353131L)
        val sky = skies[random.nextInt(skies.size)]
        val bitmap = Bitmap.createBitmap(width.coerceAtLeast(1), height.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val w = width.toFloat(); val h = height.toFloat()
        val horizon = h * (0.52f + random.nextFloat() * 0.16f)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        paint.shader = LinearGradient(0f, 0f, 0f, horizon, sky.top, sky.horizon, Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, w, horizon, paint)
        paint.shader = null

        val sunX = w * (0.15f + random.nextFloat() * 0.7f)
        val sunY = horizon * (0.25f + random.nextFloat() * 0.45f)
        val sunR = minOf(w, h) * (0.06f + random.nextFloat() * 0.06f)
        paint.color = mix(sky.sun, sky.horizon, 0.55f); paint.alpha = 90
        canvas.drawCircle(sunX, sunY, sunR * 1.9f, paint)
        paint.color = sky.sun; paint.alpha = 255
        canvas.drawCircle(sunX, sunY, sunR, paint)

        // Ridges: the back ones lighter, taking on the haze of the horizon.
        val layers = 2 + random.nextInt(2)
        for (layer in 0 until layers) {
            val depth = (layer + 1f) / layers
            val base = horizon - h * (0.18f - 0.11f * depth)
            val path = Path().apply { moveTo(0f, horizon + 1) }
            var y = base - random.nextFloat() * h * 0.08f
            var x = 0f
            val step = w / (6 + random.nextInt(6))
            while (x <= w + step) {
                path.lineTo(x, y)
                x += step
                y = (y + (random.nextFloat() - 0.5f) * h * (0.16f - 0.06f * depth)).coerceIn(base - h * 0.16f, horizon - h * 0.015f)
            }
            path.lineTo(w, horizon + 1); path.close()
            paint.color = mix(sky.horizon, sky.ridge, 0.35f + 0.65f * depth)
            canvas.drawPath(path, paint)
        }

        val water = random.nextBoolean()
        if (water) {
            paint.shader = LinearGradient(0f, horizon, 0f, h, mix(sky.horizon, sky.top, 0.4f), mix(sky.top, sky.ridge, 0.6f), Shader.TileMode.CLAMP)
            canvas.drawRect(0f, horizon, w, h, paint)
            paint.shader = null
            paint.color = sky.sun; paint.alpha = 110
            var ry = horizon + h * 0.02f
            while (ry < h) {
                val spread = sunR * (0.6f + (ry - horizon) / h * 2.4f)
                canvas.drawRect(sunX - spread, ry, sunX + spread, ry + maxOf(1f, h * 0.006f), paint)
                ry += h * 0.03f
            }
            paint.alpha = 255
        } else {
            paint.shader = LinearGradient(0f, horizon, 0f, h, mix(sky.ground, sky.horizon, 0.25f), mix(sky.ground, sky.ridge, 0.45f), Shader.TileMode.CLAMP)
            canvas.drawRect(0f, horizon, w, h, paint)
            paint.shader = null
            // A few trees along the front edge.
            paint.color = mix(sky.ground, sky.ridge, 0.75f)
            repeat(random.nextInt(5)) {
                val tx = random.nextFloat() * w
                val th = h * (0.10f + random.nextFloat() * 0.12f)
                val ty = horizon + h * (0.04f + random.nextFloat() * 0.14f)
                canvas.drawPath(Path().apply { moveTo(tx, ty - th); lineTo(tx - th * 0.28f, ty); lineTo(tx + th * 0.28f, ty); close() }, paint)
            }
        }
        return bitmap
    }
}
