package dev.doclens.doclens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import java.io.File
import java.io.FileOutputStream
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Applies a 4-corner perspective warp using Android's `Matrix.setPolyToPoly`.
 * The output bitmap's size is determined by the average of the quad's edge
 * lengths to preserve resolution without excessive memory use.
 */
object ImageWarper {
    fun warp(bitmap: Bitmap, quad: Quad, jpegQuality: Int, enhancement: String = "none"): String {
        val widthTop = hypot((quad.topRight.x - quad.topLeft.x).toDouble(),
                             (quad.topRight.y - quad.topLeft.y).toDouble())
        val widthBottom = hypot((quad.bottomRight.x - quad.bottomLeft.x).toDouble(),
                                (quad.bottomRight.y - quad.bottomLeft.y).toDouble())
        val heightLeft = hypot((quad.bottomLeft.x - quad.topLeft.x).toDouble(),
                               (quad.bottomLeft.y - quad.topLeft.y).toDouble())
        val heightRight = hypot((quad.bottomRight.x - quad.topRight.x).toDouble(),
                                (quad.bottomRight.y - quad.topRight.y).toDouble())
        val outW = max(widthTop, widthBottom).roundToInt().coerceAtLeast(8)
        val outH = max(heightLeft, heightRight).roundToInt().coerceAtLeast(8)

        val src = floatArrayOf(
            quad.topLeft.x, quad.topLeft.y,
            quad.topRight.x, quad.topRight.y,
            quad.bottomRight.x, quad.bottomRight.y,
            quad.bottomLeft.x, quad.bottomLeft.y,
        )
        val dst = floatArrayOf(
            0f, 0f,
            outW.toFloat(), 0f,
            outW.toFloat(), outH.toFloat(),
            0f, outH.toFloat(),
        )

        val matrix = Matrix()
        if (!matrix.setPolyToPoly(src, 0, dst, 0, 4)) {
            throw ScannerException.CaptureFailed("setPolyToPoly failed")
        }
        val out = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
        // Apply optional enhancement in the same pass as the warp by tinting
        // the source through a ColorMatrix — no extra full-frame allocation.
        colorMatrixFor(enhancement)?.let {
            paint.colorFilter = ColorMatrixColorFilter(it)
        }
        canvas.drawBitmap(bitmap, matrix, paint)

        val tmp = File.createTempFile("fnds_cropped_", ".jpg")
        FileOutputStream(tmp).use { stream ->
            out.compress(Bitmap.CompressFormat.JPEG, jpegQuality.coerceIn(1, 100), stream)
        }
        out.recycle()
        return tmp.absolutePath
    }

    fun warpFile(rawPath: String, quad: Quad, jpegQuality: Int, enhancement: String = "none"): String {
        val raw = BitmapFactory.decodeFile(rawPath)
            ?: throw ScannerException.CaptureFailed("Decode failed: $rawPath")
        val rotated = ExifRotator.rotated(raw, rawPath)
        return warp(rotated, quad, jpegQuality, enhancement)
    }

    /**
     * Builds the ColorMatrix for a given enhancement mode, or null for
     * `none` (no colour processing). Values mirror the iOS CIColorControls
     * settings so both platforms produce a comparable look.
     */
    private fun colorMatrixFor(enhancement: String): ColorMatrix? = when (enhancement) {
        "grayscale" -> ColorMatrix().apply { setSaturation(0f) }
        "enhanced" -> contrastMatrix(1.2f).apply { postConcat(ColorMatrix().apply { setSaturation(1.1f) }) }
        "blackAndWhite" -> ColorMatrix().apply {
            setSaturation(0f)
            postConcat(contrastMatrix(2.2f))
        }
        else -> null
    }

    /**
     * A contrast-only matrix around the 8-bit mid-grey point: each channel is
     * scaled by [c] and offset so 128 stays fixed. `c > 1` increases contrast.
     */
    private fun contrastMatrix(c: Float): ColorMatrix {
        val t = (1f - c) * 128f
        return ColorMatrix(floatArrayOf(
            c, 0f, 0f, 0f, t,
            0f, c, 0f, 0f, t,
            0f, 0f, c, 0f, t,
            0f, 0f, 0f, 1f, 0f,
        ))
    }
}
