package dev.doclens.doclens

import android.media.Image

/** Helpers for pulling the luma (Y) plane out of a YUV image and downscaling. */
object YuvUtils {
    data class Luma(val data: ByteArray, val width: Int, val height: Int)

    /** Extracts the Y plane, downscales by nearest neighbor so the max dimension
     *  is ~downscaleTo. Returns the bytes + new size. */
    fun extractLuma(image: Image, downscaleTo: Int): Luma {
        val plane = image.planes[0]
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        val w = image.width
        val h = image.height
        val buffer = plane.buffer
        val src = ByteArray(buffer.remaining())
        buffer.get(src)

        val scale = (downscaleTo.toFloat() / maxOf(w, h)).coerceAtMost(1f)
        val outW = (w * scale).toInt().coerceAtLeast(1)
        val outH = (h * scale).toInt().coerceAtLeast(1)
        val out = ByteArray(outW * outH)
        for (y in 0 until outH) {
            val srcY = (y / scale).toInt().coerceIn(0, h - 1)
            val rowStart = srcY * rowStride
            for (x in 0 until outW) {
                val srcX = (x / scale).toInt().coerceIn(0, w - 1)
                out[y * outW + x] = src[rowStart + srcX * pixelStride]
            }
        }
        return Luma(out, outW, outH)
    }
}

object LumaEstimator {
    fun isLowLight(luma: ByteArray): Boolean {
        if (luma.isEmpty()) return false
        var sum = 0L
        var count = 0L
        val step = (luma.size / 1024).coerceAtLeast(1)
        var i = 0
        while (i < luma.size) {
            sum += luma[i].toInt() and 0xFF
            count++
            i += step
        }
        val avg = sum / count
        return avg < 50
    }
}
