package dev.doclens.doclens

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.os.Build
import android.util.Size
import androidx.annotation.MainThread
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.Executors

class ScannerSession(
    private val activity: Activity,
    private val context: Context,
    private val config: ScannerConfig,
    private val textureEntry: TextureRegistry.SurfaceTextureEntry,
    private val eventSink: (Map<String, Any?>) -> Unit,
) {
    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private val captureExecutor = Executors.newSingleThreadExecutor()

    private var cameraProvider: ProcessCameraProvider? = null
    private var preview: Preview? = null
    private var analysis: ImageAnalysis? = null
    private var imageCapture: ImageCapture? = null
    private var camera: androidx.camera.core.Camera? = null

    private var lensFacing: Int = CameraSelector.LENS_FACING_BACK
    private var flashMode: Int = ImageCapture.FLASH_MODE_AUTO
    private var torch: Boolean = false

    @Volatile private var lastQuad: Quad? = null
    @Volatile private var lastFrameWidth: Int = 0
    @Volatile private var lastFrameHeight: Int = 0
    @Volatile private var lastDetectionMs: Long = 0L
    @Volatile private var previewSurfaceWidth: Int = 0
    @Volatile private var previewSurfaceHeight: Int = 0
    @Volatile private var lastEmittedPreviewW: Int = 0
    @Volatile private var lastEmittedPreviewH: Int = 0

    init {
        lensFacing = if (config.initialLens == "front") CameraSelector.LENS_FACING_FRONT
                     else CameraSelector.LENS_FACING_BACK
        flashMode = when (config.initialFlashMode) {
            "off" -> ImageCapture.FLASH_MODE_OFF
            "on" -> ImageCapture.FLASH_MODE_ON
            "torch" -> { torch = true; ImageCapture.FLASH_MODE_OFF }
            else -> ImageCapture.FLASH_MODE_AUTO
        }
    }

    @MainThread
    fun start(completion: (Result<Long>) -> Unit) {
        if (ContextCompat.checkSelfPermission(context, android.Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED) {
            completion(Result.failure(ScannerException.PermissionDenied()))
            return
        }
        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener({
            try {
                val provider = providerFuture.get()
                cameraProvider = provider
                val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
                if (!provider.hasCamera(selector)) {
                    completion(Result.failure(
                        ScannerException.Unavailable("No camera for requested lens")))
                    return@addListener
                }
                bindUseCases(provider)
                completion(Result.success(textureEntry.id()))
            } catch (e: ScannerException) {
                completion(Result.failure(e))
            } catch (e: Exception) {
                completion(Result.failure(ScannerException.InitFailed(e.message ?: "unknown")))
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindUseCases(provider: ProcessCameraProvider) {
        provider.unbindAll()
        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
        val surfaceTexture = textureEntry.surfaceTexture()

        preview = Preview.Builder().build().also { p ->
            p.setSurfaceProvider { request: SurfaceRequest ->
                val res = request.resolution
                previewSurfaceWidth = res.width
                previewSurfaceHeight = res.height
                surfaceTexture.setDefaultBufferSize(res.width, res.height)

                // `request.resolution` is the sensor-natural buffer size, which
                // is landscape (e.g. 1920x1080). CameraX rotates the buffer to
                // the display orientation before it reaches the SurfaceTexture,
                // so the pixels Flutter renders are upright. Report the size in
                // that rotated orientation — for a 90/270 rotation the displayed
                // size is the transpose — otherwise Flutter's BoxFit.cover scales
                // a landscape box onto a portrait screen and the preview stretches.
                //
                // The transformation info can fire more than once per bind (and
                // again on every resume()). Dedupe identical sizes so a repeat
                // emission with the same orientation is a no-op, and never emit
                // a 0x0 — both would let a transient/stale event corrupt the
                // layout the Flutter side already computed.
                request.setTransformationInfoListener(
                    ContextCompat.getMainExecutor(context)
                ) { info ->
                    val swap = info.rotationDegrees % 180 != 0
                    val w = if (swap) res.height else res.width
                    val h = if (swap) res.width else res.height
                    if (w <= 0 || h <= 0) return@setTransformationInfoListener
                    if (w == lastEmittedPreviewW && h == lastEmittedPreviewH) {
                        return@setTransformationInfoListener
                    }
                    lastEmittedPreviewW = w
                    lastEmittedPreviewH = h
                    eventSink(mapOf(
                        "previewSize" to listOf(w.toDouble(), h.toDouble()),
                    ))
                }

                val surface = android.view.Surface(surfaceTexture)
                request.provideSurface(surface, ContextCompat.getMainExecutor(context)) {
                    surface.release()
                }
            }
        }

        analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setTargetResolution(Size(640, 480))
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
            .build()
            .also { a ->
                a.setAnalyzer(analysisExecutor) { proxy -> onFrame(proxy) }
            }

        imageCapture = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
            .setFlashMode(flashMode)
            .build()

        val owner = activity as? LifecycleOwner
            ?: throw ScannerException.InitFailed("Activity must be LifecycleOwner")
        camera = provider.bindToLifecycle(owner, selector, preview, analysis, imageCapture)
        if (torch) camera?.cameraControl?.enableTorch(true)
    }

    @SuppressLint("UnsafeOptInUsageError")
    private fun onFrame(proxy: ImageProxy) {
        try {
            if (!config.enableLiveDetection) return
            val now = System.currentTimeMillis()
            val intervalMs = (1000.0 / config.detectionThrottleHz).toLong().coerceAtLeast(33L)
            if (now - lastDetectionMs < intervalMs) return
            lastDetectionMs = now

            val image = proxy.image ?: return
            val rotation = proxy.imageInfo.rotationDegrees
            val (luma, width, height) = YuvUtils.extractLuma(image, downscaleTo = 256)
            lastFrameWidth = width
            lastFrameHeight = height
            val quad = QuadDetector.detect(luma, width, height)
            // Rotate quad coordinates into the displayed (rotated) coordinate
            // space so that normalized values match what users see.
            val rotated = quad?.let { rotateNormalizedQuad(it, rotation) }
            lastQuad = rotated

            val lowLight = config.enableLowLightDetection && LumaEstimator.isLowLight(luma)
            eventSink(mapOf(
                "quad" to rotated?.toMap(),
                "lowLight" to lowLight,
            ))
        } finally {
            proxy.close()
        }
    }

    private fun rotateNormalizedQuad(q: Quad, deg: Int): Quad {
        fun r(p: PointF): PointF = when (((deg % 360) + 360) % 360) {
            0 -> p
            90 -> PointF(1f - p.y, p.x)
            180 -> PointF(1f - p.x, 1f - p.y)
            270 -> PointF(p.y, 1f - p.x)
            else -> p
        }
        // Re-order corners to maintain TL/TR/BR/BL after rotation.
        val rotated = listOf(r(q.topLeft), r(q.topRight), r(q.bottomRight), r(q.bottomLeft))
        return QuadOrdering.reorderClockwise(rotated)
    }

    @MainThread
    fun setFlashMode(mode: String) {
        flashMode = when (mode) {
            "off" -> { torch = false; ImageCapture.FLASH_MODE_OFF }
            "on" -> { torch = false; ImageCapture.FLASH_MODE_ON }
            "auto" -> { torch = false; ImageCapture.FLASH_MODE_AUTO }
            "torch" -> { torch = true; ImageCapture.FLASH_MODE_OFF }
            else -> ImageCapture.FLASH_MODE_AUTO
        }
        imageCapture?.flashMode = flashMode
        camera?.cameraControl?.enableTorch(torch)
    }

    @MainThread
    fun switchCamera() {
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK)
            CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
        cameraProvider?.let { bindUseCases(it) }
    }

    @MainThread
    fun pause() {
        cameraProvider?.unbindAll()
    }

    @MainThread
    fun resume() {
        cameraProvider?.let { bindUseCases(it) }
    }

    /// Tap-to-focus. [normX], [normY] are in the Flutter widget's portrait
    /// [0, 1] space (origin top-left). We build a metering point on the
    /// preview Surface's native coordinate space using
    /// [SurfaceOrientedMeteringPointFactory], which is the correct factory
    /// for textures (see CameraX docs). Auto-cancel after 3 s drops back
    /// to continuous autofocus.
    @MainThread
    fun focus(normX: Float, normY: Float) {
        val camera = this.camera ?: return
        val w = previewSurfaceWidth
        val h = previewSurfaceHeight
        if (w <= 0 || h <= 0) return
        val factory = androidx.camera.core.SurfaceOrientedMeteringPointFactory(
            w.toFloat(), h.toFloat(),
        )
        val point = factory.createPoint(
            (normX.coerceIn(0f, 1f)) * w,
            (normY.coerceIn(0f, 1f)) * h,
        )
        val action = androidx.camera.core.FocusMeteringAction.Builder(
            point,
            androidx.camera.core.FocusMeteringAction.FLAG_AF or
                androidx.camera.core.FocusMeteringAction.FLAG_AE,
        ).setAutoCancelDuration(3, java.util.concurrent.TimeUnit.SECONDS)
         .build()
        if (camera.cameraInfo.isFocusMeteringSupported(action)) {
            try {
                camera.cameraControl.startFocusAndMetering(action)
            } catch (_: Exception) {
                // Best-effort.
            }
        }
    }

    @MainThread
    fun capture(result: MethodChannel.Result) {
        val capture = imageCapture
        if (capture == null) {
            result.error("init_failed", "ImageCapture not ready", null); return
        }
        val file = File(context.cacheDir, "fnds_raw_${System.currentTimeMillis()}.jpg")
        val options = ImageCapture.OutputFileOptions.Builder(file).build()
        capture.takePicture(options, captureExecutor, object : ImageCapture.OnImageSavedCallback {
            override fun onError(exception: ImageCaptureException) {
                activity.runOnUiThread {
                    result.error("capture_failed", exception.message, null)
                }
            }
            override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                var raw: Bitmap? = null
                var rotated: Bitmap? = null
                try {
                    raw = decodeDownscaled(file.absolutePath, maxDimension = 3000)
                        ?: throw ScannerException.CaptureFailed("Decode failed")
                    rotated = ExifRotator.rotated(raw, file.absolutePath)
                    val rawSize = Size(rotated.width, rotated.height)
                    val q = lastQuad
                    val pixelQuad = q?.let {
                        Quad(
                            PointF(it.topLeft.x * rawSize.width, it.topLeft.y * rawSize.height),
                            PointF(it.topRight.x * rawSize.width, it.topRight.y * rawSize.height),
                            PointF(it.bottomRight.x * rawSize.width, it.bottomRight.y * rawSize.height),
                            PointF(it.bottomLeft.x * rawSize.width, it.bottomLeft.y * rawSize.height),
                        )
                    }
                    var croppedPath: String? = null
                    if (config.enablePerspectiveWarp && pixelQuad != null) {
                        croppedPath = ImageWarper.warp(rotated, pixelQuad, config.jpegQuality, config.imageEnhancement)
                    }
                    // Always persist the upright bitmap we actually measured
                    // (`rotated`) so the returned rawImagePath's pixel
                    // dimensions exactly match `rawImageSize` — and therefore
                    // the reported quad. We can't return the original on-disk
                    // file here: `decodeDownscaled` may have shrunk large
                    // captures (e.g. 4000x3000 -> 2000x1500), so the original
                    // file would be full-resolution while rawImageSize/quad
                    // describe the downscaled space. A later re-warp via
                    // EditCorners decodes that file at full resolution and
                    // applies the half-scale quad, cropping the wrong region.
                    val rawPathToReturn = run {
                        val out = File(context.cacheDir, "fnds_raw_upright_${System.currentTimeMillis()}.jpg")
                        out.outputStream().use { rotated.compress(Bitmap.CompressFormat.JPEG, config.jpegQuality, it) }
                        // Original on-disk file is now stale (rotated and/or
                        // downscaled relative to what we return).
                        file.delete()
                        out.absolutePath
                    }

                    val payload = mapOf(
                        "croppedImagePath" to croppedPath,
                        "rawImagePath" to rawPathToReturn,
                        "quad" to (pixelQuad ?: Quad(
                            PointF(0f, 0f),
                            PointF(rawSize.width.toFloat(), 0f),
                            PointF(rawSize.width.toFloat(), rawSize.height.toFloat()),
                            PointF(0f, rawSize.height.toFloat()),
                        )).toMap(),
                        "rawImageSize" to listOf(rawSize.width.toDouble(), rawSize.height.toDouble()),
                    )
                    activity.runOnUiThread { result.success(payload) }
                } catch (e: Exception) {
                    activity.runOnUiThread {
                        result.error("capture_failed", e.message, null)
                    }
                } finally {
                    if (rotated != null && rotated !== raw) rotated.recycle()
                    raw?.recycle()
                }
            }
        })
    }

    private fun decodeDownscaled(path: String, maxDimension: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / sample > maxDimension ||
               bounds.outHeight / sample > maxDimension) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeFile(path, opts)
    }

    @MainThread
    fun dispose() {
        cameraProvider?.unbindAll()
        cameraProvider = null
        analysisExecutor.shutdown()
        captureExecutor.shutdown()
        textureEntry.release()
    }
}
