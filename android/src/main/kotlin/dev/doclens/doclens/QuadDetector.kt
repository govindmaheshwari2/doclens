package dev.doclens.doclens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlin.math.max
import kotlin.math.min


/**
 * Document quadrilateral detector that runs entirely on a downscaled
 * luma buffer. Strategy:
 *
 * 1. Compute mean luma; build a mask of "bright" pixels (paper, typically).
 *    Falls back to Sobel-edge boundary if contrast is poor.
 * 2. Find the largest connected component in the mask.
 * 3. Walk the component's boundary, then approximate to a 4-point convex
 *    hull via Douglas-Peucker on the boundary polygon.
 *
 * Returns normalized `[0,1]` coordinates in `topLeft → topRight → bottomRight
 * → bottomLeft` order on the input buffer's frame (orientation handled by
 * caller).
 *
 * v0.1 deliberately avoids OpenCV and ML Kit (see docs/decisions.md).
 */
object QuadDetector {
    fun detect(luma: ByteArray, width: Int, height: Int): Quad? {
        if (width < 16 || height < 16) return null
        val mask = buildMask(luma, width, height) ?: return null
        val component = largestComponent(mask, width, height) ?: return null
        if (component.size < (width * height) / 50) return null
        val boundary = traceBoundary(component, width, height) ?: return null
        val hull = convexHull(boundary)
        if (hull.size < 4) return null
        val quad = approximateQuad(hull) ?: return null
        return normalizeAndOrder(quad, width.toFloat(), height.toFloat())
    }

    /**
     * Run [detect] on a still image already on disk (e.g. one imported from
     * the gallery). Decodes the file, bakes in any EXIF orientation, then
     * detects on a downscaled luma copy — the normalized quad is
     * resolution-independent, so the downscale only affects speed.
     *
     * Returns a map of `{ "quad": <normalized quad map> | null, "imageSize":
     * [width, height] }` in the EXIF-upright pixel space (the same space the
     * warp operates in). Throws [ScannerException.CaptureFailed] when the file
     * cannot be decoded.
     */
    fun detectInFile(path: String): Map<String, Any?> {
        val raw = BitmapFactory.decodeFile(path)
            ?: throw ScannerException.CaptureFailed("Decode failed: $path")
        val upright = ExifRotator.rotated(raw, path)
        try {
            val w = upright.width
            val h = upright.height
            // Downscale for detection; the largest side caps at ~480 px. The
            // detector emits normalized [0,1] coords, so this is purely a
            // speed/memory optimisation and doesn't affect the result space.
            val target = 480
            val scale = min(1.0, target.toDouble() / max(w, h))
            val dw = max(16, (w * scale).toInt())
            val dh = max(16, (h * scale).toInt())
            val small = if (dw == w && dh == h) upright
                        else Bitmap.createScaledBitmap(upright, dw, dh, true)
            val pixels = IntArray(dw * dh)
            small.getPixels(pixels, 0, dw, 0, 0, dw, dh)
            if (small !== upright) small.recycle()

            val luma = ByteArray(dw * dh)
            for (i in pixels.indices) {
                val p = pixels[i]
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                // Rec.601 luma, integer weights (77/150/29 ≈ /256).
                luma[i] = (((r * 77 + g * 150 + b * 29) shr 8) and 0xFF).toByte()
            }

            val quad = detect(luma, dw, dh)
            return mapOf(
                "quad" to quad?.toMap(),
                "imageSize" to listOf(w.toDouble(), h.toDouble()),
            )
        } finally {
            if (upright !== raw) upright.recycle()
            raw.recycle()
        }
    }

    private fun buildMask(luma: ByteArray, @Suppress("UNUSED_PARAMETER") w: Int, @Suppress("UNUSED_PARAMETER") h: Int): BooleanArray? {
        var sum = 0L
        for (b in luma) sum += b.toInt() and 0xFF
        val mean = (sum / luma.size).toInt()
        // Bias slightly above the mean to favor paper-bright.
        val threshold = (mean + 20).coerceIn(60, 220)
        val mask = BooleanArray(luma.size)
        for (i in luma.indices) {
            mask[i] = (luma[i].toInt() and 0xFF) > threshold
        }
        return mask
    }

    private fun largestComponent(mask: BooleanArray, w: Int, h: Int): IntArray? {
        val labels = IntArray(mask.size) { -1 }
        var best: IntArray? = null
        var bestSize = 0
        val stack = IntArray(mask.size)
        for (start in mask.indices) {
            if (!mask[start] || labels[start] != -1) continue
            // BFS / flood fill iterative.
            var top = 0
            stack[top++] = start
            labels[start] = start
            val collected = IntArray(mask.size)
            var collectedSize = 0
            while (top > 0) {
                val idx = stack[--top]
                collected[collectedSize++] = idx
                val x = idx % w
                val y = idx / w
                val neighbors = intArrayOf(
                    if (x > 0) idx - 1 else -1,
                    if (x < w - 1) idx + 1 else -1,
                    if (y > 0) idx - w else -1,
                    if (y < h - 1) idx + w else -1,
                )
                for (n in neighbors) {
                    if (n >= 0 && mask[n] && labels[n] == -1) {
                        labels[n] = start
                        stack[top++] = n
                    }
                }
            }
            if (collectedSize > bestSize) {
                bestSize = collectedSize
                best = collected.copyOf(collectedSize)
            }
        }
        return best
    }

    private fun traceBoundary(component: IntArray, w: Int, h: Int): List<PointF>? {
        // A pixel is a boundary if any of its 4-neighbors is NOT in the component.
        val inComp = BooleanArray(w * h)
        for (idx in component) inComp[idx] = true
        val result = ArrayList<PointF>(component.size / 4 + 8)
        for (idx in component) {
            val x = idx % w
            val y = idx / w
            val isBoundary =
                x == 0 || y == 0 || x == w - 1 || y == h - 1 ||
                !inComp[idx - 1] || !inComp[idx + 1] ||
                !inComp[idx - w] || !inComp[idx + w]
            if (isBoundary) result.add(PointF(x.toFloat(), y.toFloat()))
        }
        return if (result.size < 4) null else result
    }

    private fun convexHull(points: List<PointF>): List<PointF> {
        if (points.size < 3) return points
        val sorted = points.sortedWith(compareBy({ it.x }, { it.y }))
        val lower = ArrayList<PointF>()
        for (p in sorted) {
            while (lower.size >= 2 && cross(lower[lower.size - 2], lower[lower.size - 1], p) <= 0)
                lower.removeAt(lower.size - 1)
            lower.add(p)
        }
        val upper = ArrayList<PointF>()
        for (p in sorted.reversed()) {
            while (upper.size >= 2 && cross(upper[upper.size - 2], upper[upper.size - 1], p) <= 0)
                upper.removeAt(upper.size - 1)
            upper.add(p)
        }
        if (lower.isNotEmpty()) lower.removeAt(lower.size - 1)
        if (upper.isNotEmpty()) upper.removeAt(upper.size - 1)
        return lower + upper
    }

    private fun cross(O: PointF, A: PointF, B: PointF): Float =
        (A.x - O.x) * (B.y - O.y) - (A.y - O.y) * (B.x - O.x)

    /**
     * Reduce a convex hull to its 4 dominant corners by picking the hull
     * points that extremize (x+y), (x-y), -(x+y), -(x-y) — these are the
     * TL, TR, BR, BL extents for any near-rectangular hull, robust to
     * orientation jitter.
     */
    private fun approximateQuad(hull: List<PointF>): List<PointF>? {
        if (hull.size < 4) return null
        var tl = hull[0]; var tr = hull[0]; var br = hull[0]; var bl = hull[0]
        var tlScore = Float.POSITIVE_INFINITY
        var brScore = Float.NEGATIVE_INFINITY
        var trScore = Float.NEGATIVE_INFINITY
        var blScore = Float.POSITIVE_INFINITY
        for (p in hull) {
            val sum = p.x + p.y
            val diff = p.x - p.y
            if (sum < tlScore) { tlScore = sum; tl = p }
            if (sum > brScore) { brScore = sum; br = p }
            if (diff > trScore) { trScore = diff; tr = p }
            if (diff < blScore) { blScore = diff; bl = p }
        }
        // Ensure non-degenerate (no two corners coincide).
        val set = setOf(tl, tr, br, bl)
        if (set.size < 4) return null
        return listOf(tl, tr, br, bl)
    }

    private fun normalizeAndOrder(pts: List<PointF>, w: Float, h: Float): Quad {
        val normalized = pts.map { PointF(it.x / w, it.y / h) }
        return QuadOrdering.reorderClockwise(normalized)
    }
}

object QuadOrdering {
    /** Orders 4 points into TL/TR/BR/BL based on sum and difference heuristics. */
    fun reorderClockwise(pts: List<PointF>): Quad {
        require(pts.size == 4)
        val sumSorted = pts.sortedBy { it.x + it.y }
        val tl = sumSorted.first()
        val br = sumSorted.last()
        val remaining = pts - tl - br
        val (tr, bl) = if (remaining[0].x > remaining[1].x) remaining[0] to remaining[1]
                       else remaining[1] to remaining[0]
        return Quad(tl, tr, br, bl)
    }
}
