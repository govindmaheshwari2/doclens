package dev.doclens.doclens

import android.graphics.BitmapFactory
import android.graphics.Rect
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.TimeUnit

/**
 * On-device OCR over a document image, returning the full recognised text plus
 * per-block / per-line bounding boxes and confidence.
 *
 * Uses ML Kit's on-device Latin text recognizer, delivered by Google Play
 * services (`play-services-mlkit-text-recognition`) — exactly like the
 * OS-native document scanner and `AutoOrientation.auto`. No model is bundled in
 * the app; it is downloaded on demand the first time it is used.
 */
object TextRecognizer {
    private val recognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    /**
     * Recognise text in the image at [path]. The returned map matches the Dart
     * `OcrResult.fromMap` contract:
     * `{ text, imageSize:[w,h], blocks:[ { text, boundingBox:[l,t,w,h],
     *    recognizedLanguage, lines:[ { text, boundingBox, confidence } ] } ] }`.
     *
     * MUST be called off the main thread — it blocks on the recognizer.
     */
    fun recognize(path: String): Map<String, Any?> {
        val raw = BitmapFactory.decodeFile(path)
            ?: throw ScannerException.CaptureFailed("Decode failed: $path")
        // Bake EXIF orientation into the pixels so the bounding boxes are in the
        // same upright pixel space the caller is displaying.
        val bitmap = ExifRotator.rotated(raw, path)
        try {
            val text: Text = try {
                Tasks.await(
                    recognizer.process(InputImage.fromBitmap(bitmap, 0)),
                    10, TimeUnit.SECONDS,
                )
            } catch (_: Exception) {
                // Model still downloading on demand, or recognition failed —
                // return an empty result rather than surfacing an error.
                return emptyResult(bitmap.width, bitmap.height)
            }

            val blocks = ArrayList<Map<String, Any?>>(text.textBlocks.size)
            for (block in text.textBlocks) {
                val lines = ArrayList<Map<String, Any?>>(block.lines.size)
                for (line in block.lines) {
                    lines.add(
                        mapOf(
                            "text" to line.text,
                            "boundingBox" to rectToList(line.boundingBox),
                            "confidence" to confidenceOf(line.confidence),
                        ),
                    )
                }
                blocks.add(
                    mapOf(
                        "text" to block.text,
                        "boundingBox" to rectToList(block.boundingBox),
                        "recognizedLanguage" to block.recognizedLanguage
                            .ifEmpty { null },
                        "lines" to lines,
                    ),
                )
            }

            return mapOf(
                "text" to text.text,
                "imageSize" to listOf(bitmap.width.toDouble(), bitmap.height.toDouble()),
                "blocks" to blocks,
            )
        } finally {
            if (bitmap !== raw) bitmap.recycle()
            raw.recycle()
        }
    }

    private fun emptyResult(width: Int, height: Int): Map<String, Any?> = mapOf(
        "text" to "",
        "imageSize" to listOf(width.toDouble(), height.toDouble()),
        "blocks" to emptyList<Map<String, Any?>>(),
    )

    /** `[left, top, width, height]` in image pixel coordinates, or null. */
    private fun rectToList(r: Rect?): List<Double>? {
        if (r == null) return null
        return listOf(
            r.left.toDouble(),
            r.top.toDouble(),
            r.width().toDouble(),
            r.height().toDouble(),
        )
    }

    /** `confidence` can be null or NaN on some models — drop it then. */
    private fun confidenceOf(conf: Float?): Double? =
        if (conf == null || conf.isNaN()) null else conf.toDouble()
}
