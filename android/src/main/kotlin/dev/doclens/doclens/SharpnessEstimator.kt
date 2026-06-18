package dev.doclens.doclens

/** Variance-of-Laplacian sharpness over a downscaled luma plane. Higher =
 *  sharper. Optionally restricted to a normalized rect (origin top-left). */
object SharpnessEstimator {
    fun sharpness(
        luma: ByteArray,
        width: Int,
        height: Int,
        minX: Float = 0f,
        minY: Float = 0f,
        maxX: Float = 1f,
        maxY: Float = 1f,
    ): Double {
        if (width <= 2 || height <= 2 || luma.size < width * height) return 0.0
        val x0 = (minX * width).toInt().coerceIn(1, width - 2)
        val y0 = (minY * height).toInt().coerceIn(1, height - 2)
        val x1 = (maxX * width).toInt().coerceIn(1, width - 2)
        val y1 = (maxY * height).toInt().coerceIn(1, height - 2)
        if (x1 <= x0 || y1 <= y0) return 0.0

        fun lum(x: Int, y: Int): Int = luma[y * width + x].toInt() and 0xFF

        var sum = 0.0
        var sumSq = 0.0
        var n = 0.0
        for (y in y0..y1) {
            for (x in x0..x1) {
                val lap = lum(x - 1, y) + lum(x + 1, y) +
                        lum(x, y - 1) + lum(x, y + 1) - 4 * lum(x, y)
                val d = lap.toDouble()
                sum += d
                sumSq += d * d
                n += 1
            }
        }
        if (n < 1) return 0.0
        val mean = sum / n
        return (sumSq / n - mean * mean).coerceAtLeast(0.0)
    }
}
