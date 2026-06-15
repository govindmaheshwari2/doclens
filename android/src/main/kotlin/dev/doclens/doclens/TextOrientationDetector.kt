package dev.doclens.doclens

import android.graphics.Bitmap
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.TimeUnit
import kotlin.math.max

/**
 * Detects the dominant text direction of a (already dewarped) document crop so
 * the caller can rotate it upright.
 *
 * Uses ML Kit's on-device Latin text recognizer, delivered by Google Play
 * services (`play-services-mlkit-text-recognition`) — exactly like the
 * OS-native document scanner. No model is bundled in the app; it is downloaded
 * on demand the first time it's used. If the model isn't ready yet (or
 * recognition fails), this returns `0` so the crop is left untouched.
 *
 * The crop is recognised at each of the four 90° rotations; whichever the
 * recognizer reads the most confident text from is the upright one.
 */
object TextOrientationDetector {
    private val recognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    /**
     * Number of clockwise 90° turns to apply to [bitmap] so its dominant text
     * reads upright (`0..3`). Returns `0` when no confident text orientation is
     * found (blank/graphical page, model unavailable, or recognition failed).
     *
     * MUST be called off the main thread — it blocks on the recognizer.
     */
    fun bestClockwiseTurns(bitmap: Bitmap): Int {
        val small = downscale(bitmap, 1000)
        var bestTurns = 0
        var bestScore = 0.0
        // `InputImage.fromBitmap(bm, rotationDegrees)` follows the CameraX
        // convention: `rotationDegrees` is the *clockwise* rotation that brings
        // the buffer upright, which ML Kit applies before recognition. So if
        // text reads best after rotating `deg` clockwise, that same rotation
        // (deg / 90 turns) is what we bake into the output.
        for (deg in intArrayOf(0, 90, 180, 270)) {
            val score = try {
                val image = InputImage.fromBitmap(small, deg)
                val text = Tasks.await(recognizer.process(image), 3, TimeUnit.SECONDS)
                scoreOf(text)
            } catch (_: Exception) {
                0.0
            }
            if (score > bestScore) {
                bestScore = score
                bestTurns = deg / 90
            }
        }
        if (small !== bitmap) small.recycle()
        // Require a meaningful amount of confident text before trusting a
        // rotation — otherwise speckle on a near-blank page could spin it.
        return if (bestScore >= 1.0) bestTurns else 0
    }

    private fun scoreOf(text: Text): Double {
        var score = 0.0
        for (block in text.textBlocks) {
            for (line in block.lines) {
                // `confidence` can be null or NaN on some models — treat as
                // fully confident so the recognised length still counts.
                val conf: Float? = line.confidence
                val weight = if (conf == null || conf.isNaN()) 1f else conf
                score += weight.toDouble() * line.text.length
            }
        }
        return score
    }

    private fun downscale(src: Bitmap, maxDimension: Int): Bitmap {
        val maxDim = max(src.width, src.height)
        if (maxDim <= maxDimension) return src
        val scale = maxDimension.toFloat() / maxDim
        val w = max(1, (src.width * scale).toInt())
        val h = max(1, (src.height * scale).toInt())
        return Bitmap.createScaledBitmap(src, w, h, true)
    }
}
