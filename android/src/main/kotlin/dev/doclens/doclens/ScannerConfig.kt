package dev.doclens.doclens

data class ScannerConfig(
    val enableLiveDetection: Boolean,
    val detectionThrottleHz: Int,
    val enablePerspectiveWarp: Boolean,
    val jpegQuality: Int,
    val outputFormat: String,
    val captureResolution: String,
    val initialFlashMode: String,
    val initialLens: String,
    val enableTapToFocus: Boolean,
    val enablePinchToZoom: Boolean,
    val enableLowLightDetection: Boolean,
) {
    companion object {
        fun fromMap(m: Map<String, Any?>): ScannerConfig = ScannerConfig(
            enableLiveDetection = m["enableLiveDetection"] as? Boolean ?: true,
            detectionThrottleHz = (m["detectionThrottleHz"] as? Number)?.toInt() ?: 12,
            enablePerspectiveWarp = m["enablePerspectiveWarp"] as? Boolean ?: true,
            jpegQuality = (m["jpegQuality"] as? Number)?.toInt() ?: 92,
            outputFormat = m["outputFormat"] as? String ?: "jpeg",
            captureResolution = m["captureResolution"] as? String ?: "high",
            initialFlashMode = m["initialFlashMode"] as? String ?: "auto",
            initialLens = m["initialLens"] as? String ?: "back",
            enableTapToFocus = m["enableTapToFocus"] as? Boolean ?: true,
            enablePinchToZoom = m["enablePinchToZoom"] as? Boolean ?: true,
            enableLowLightDetection = m["enableLowLightDetection"] as? Boolean ?: true,
        )
    }
}

data class Quad(
    val topLeft: PointF,
    val topRight: PointF,
    val bottomRight: PointF,
    val bottomLeft: PointF,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "topLeft" to listOf(topLeft.x.toDouble(), topLeft.y.toDouble()),
        "topRight" to listOf(topRight.x.toDouble(), topRight.y.toDouble()),
        "bottomRight" to listOf(bottomRight.x.toDouble(), bottomRight.y.toDouble()),
        "bottomLeft" to listOf(bottomLeft.x.toDouble(), bottomLeft.y.toDouble()),
    )

    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(m: Map<String, Any?>): Quad {
            fun pt(key: String): PointF {
                val raw = m[key] as? List<Number> ?: return PointF(0f, 0f)
                return PointF(raw[0].toFloat(), raw[1].toFloat())
            }
            return Quad(pt("topLeft"), pt("topRight"), pt("bottomRight"), pt("bottomLeft"))
        }
    }
}

data class PointF(val x: Float, val y: Float)

sealed class ScannerException(message: String) : Exception(message) {
    class PermissionDenied : ScannerException("Camera permission denied")
    class Unavailable(message: String) : ScannerException(message)
    class InitFailed(message: String) : ScannerException(message)
    class CaptureFailed(message: String) : ScannerException(message)
}
