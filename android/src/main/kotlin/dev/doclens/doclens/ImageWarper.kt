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
        canvas.drawBitmap(bitmap, matrix, paint)

        // Optional post-warp enhancement (shadow-aware). Operates on the
        // cropped pixels in place; `none` is a no-op.
        enhanceInPlace(out, enhancement)

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
     * Applies a shadow-aware enhancement to the cropped bitmap, in place.
     *
     * `enhanced` and `blackAndWhite` first estimate the per-pixel background
     * illumination — a heavily downscaled, smoothed copy of the image — and
     * divide it out. This is the classic Retinex/"flatten" correction: under
     * the multiplicative model `image = reflectance × illumination`, dividing
     * by a smooth illumination estimate cancels uneven lighting and soft
     * shadows. `enhanced` keeps colour and whitens the background; the
     * background estimate is sampled (nearest) from a tiny downscaled copy,
     * which is a cheap stand-in for a very large blur kernel.
     *
     * `blackAndWhite` adaptively thresholds luma against the local background
     * (white where `luma >= background_luma × ratio`, else black) — this is
     * the no-OpenCV equivalent of OpenCV's `ADAPTIVE_THRESH_MEAN_C`, which
     * tolerates shadows where a single global (Otsu) threshold fails.
     *
     * `grayscale` is a plain global desaturate (no shadow handling). `none`
     * is a no-op.
     *
     * iOS performs the equivalent step with `CIDocumentEnhancer` /
     * `CIColorThresholdOtsu`; see `ImageWarper.swift`.
     */
    private fun enhanceInPlace(bmp: Bitmap, mode: String) {
        if (mode == "none" || mode.isEmpty()) return
        val w = bmp.width
        val h = bmp.height
        if (w <= 0 || h <= 0) return

        val px = IntArray(w * h)
        bmp.getPixels(px, 0, w, 0, 0, w, h)

        when (mode) {
            "grayscale" -> {
                for (i in px.indices) {
                    val p = px[i]
                    val l = luma((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF)
                    px[i] = (0xFF shl 24) or (l shl 16) or (l shl 8) or l
                }
            }
            "enhanced", "blackAndWhite" -> {
                // Smooth background illumination estimate. Downscaling to ~80px
                // on the long edge averages away the text and keeps only the
                // lighting gradient; we sample it back (nearest) per pixel
                // without ever allocating a full-size background bitmap.
                val targetMax = 80
                val factor = max(1, max(w, h) / targetMax)
                val sw = max(1, w / factor)
                val sh = max(1, h / factor)
                val small = Bitmap.createScaledBitmap(bmp, sw, sh, true)
                val bg = IntArray(sw * sh)
                small.getPixels(bg, 0, sw, 0, 0, sw, sh)
                small.recycle()

                val blackAndWhite = mode == "blackAndWhite"
                // ~0.85 keeps faint strokes while clearing background speckle;
                // equivalent to a positive C offset in adaptive-mean threshold.
                val bwRatio = 0.85f
                for (y in 0 until h) {
                    val sy = (y * sh / h).coerceIn(0, sh - 1)
                    val rowS = sy * sw
                    val rowD = y * w
                    for (x in 0 until w) {
                        val sx = (x * sw / w).coerceIn(0, sw - 1)
                        val b = bg[rowS + sx]
                        val d = px[rowD + x]
                        val sr = (d shr 16) and 0xFF
                        val sg = (d shr 8) and 0xFF
                        val sb = d and 0xFF
                        if (blackAndWhite) {
                            val sl = luma(sr, sg, sb)
                            val bl = luma((b shr 16) and 0xFF, (b shr 8) and 0xFF, b and 0xFF)
                            val ratio = if (bl > 0) sl.toFloat() / bl else 1f
                            val o = if (ratio >= bwRatio) 0xFF else 0x00
                            px[rowD + x] = (0xFF shl 24) or (o shl 16) or (o shl 8) or o
                        } else {
                            val br = (b shr 16) and 0xFF
                            val bgc = (b shr 8) and 0xFF
                            val bb = b and 0xFF
                            val rr = if (br > 0) (sr * 255 / br).coerceAtMost(255) else 255
                            val rg = if (bgc > 0) (sg * 255 / bgc).coerceAtMost(255) else 255
                            val rb = if (bb > 0) (sb * 255 / bb).coerceAtMost(255) else 255
                            px[rowD + x] = (0xFF shl 24) or (rr shl 16) or (rg shl 8) or rb
                        }
                    }
                }
            }
            else -> return
        }

        bmp.setPixels(px, 0, w, 0, 0, w, h)
    }

    /** Rec.601 luma in [0, 255] using integer weights (77/150/29 ≈ /256). */
    private fun luma(r: Int, g: Int, b: Int): Int =
        ((r * 77 + g * 150 + b * 29) shr 8).coerceIn(0, 255)
}
