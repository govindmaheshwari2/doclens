package dev.doclens.doclens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
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
    fun warp(bitmap: Bitmap, quad: Quad, jpegQuality: Int): String {
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
        canvas.drawBitmap(bitmap, matrix, paint)

        val tmp = File.createTempFile("fnds_cropped_", ".jpg")
        FileOutputStream(tmp).use { stream ->
            out.compress(Bitmap.CompressFormat.JPEG, jpegQuality.coerceIn(1, 100), stream)
        }
        out.recycle()
        return tmp.absolutePath
    }

    fun warpFile(rawPath: String, quad: Quad, jpegQuality: Int): String {
        val raw = BitmapFactory.decodeFile(rawPath)
            ?: throw ScannerException.CaptureFailed("Decode failed: $rawPath")
        val rotated = ExifRotator.rotated(raw, rawPath)
        return warp(rotated, quad, jpegQuality)
    }
}
