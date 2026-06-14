import 'dart:ui';

import 'quad.dart';

/// Coarse-grained guidance shown to the user about the current detection state.
enum DetectionStatus {
  /// No quad detected at all.
  searching,

  /// Quad detected, but its area suggests the document is too far from camera.
  tooFar,

  /// Quad detected, but its area is too large — document is too close.
  tooClose,

  /// Quad detected but tilted (aspect or perspective skew out of bounds).
  tilted,

  /// Quad is well-framed and stable enough to capture.
  aligned,

  /// Quad has been aligned long enough that auto-capture is about to
  /// fire. UI typically pulses or recolours the overlay during this
  /// brief confirmation window so the user knows what's about to be
  /// captured. Mirrors VisionKit's "found a document — hold still" cue.
  confirming,

  /// Camera is producing frames, but no paper-like quad found.
  noPaper,
}

/// Camera flash / torch mode.
enum FlashMode {
  off,
  auto,
  on,

  /// Continuous torch (useful in low light, independent of capture).
  torch,
}

/// Which camera to use.
enum CameraLens { back, front }

enum ImageFormat { jpeg, png }

/// Optional post-warp image processing applied to the cropped document.
///
/// Enhancement runs on the perspective-corrected crop only — the raw image
/// ([ScanResult.rawImagePath]) is always left untouched. It is applied both
/// to the capture's cropped output and to re-warps performed via
/// `EditCornersScreen`.
///
/// [enhanced] and [blackAndWhite] remove uneven lighting and soft shadows:
/// on iOS via Apple's `CIDocumentEnhancer` (with a manual illumination-
/// division fallback on older OSes), and on Android via an equivalent
/// background-division ("flatten") pass. No model is bundled and no extra
/// dependency is required.
enum ImageEnhancement {
  /// No processing — the cropped output is the original pixels, just
  /// dewarped. Most faithful; best when you run your own preprocessing or
  /// want unmodified bytes for archival.
  none,

  /// Desaturate to grayscale. A plain global desaturate (no shadow
  /// handling) — neutral tone, smaller files, calmer look for mixed
  /// photo/text pages.
  grayscale,

  /// Shadow-corrected colour scan ("magic colour"): estimates the lighting
  /// and divides it out so uneven illumination and soft shadows are removed
  /// and the background is whitened, while colour is preserved. Good
  /// general-purpose choice for photos of documents shot in uneven light.
  enhanced,

  /// Shadow-corrected, near-bitonal "document" look: flattens the lighting
  /// then thresholds locally (adaptive / Otsu) for clean black text on a
  /// white background. Best for plain text pages and OCR on faint or
  /// low-contrast print.
  blackAndWhite,
}

/// Capture resolution hint. The native side picks the closest supported preset.
enum Resolution { auto, high, max }

/// Output of a single capture.
class ScanResult {
  const ScanResult({
    required this.croppedImagePath,
    required this.rawImagePath,
    required this.detectedQuad,
    required this.rawImageSize,
    this.warpError,
  });

  /// Perspective-warped, cropped document. `null` when
  /// [ScannerConfig.enablePerspectiveWarp] was false **or** when the warp
  /// could not be applied (degenerate quad, out-of-bounds coordinates) —
  /// see [warpError]. Callers should check [warpError] before treating a
  /// null cropped path as "no warp requested".
  final String? croppedImagePath;

  /// Full raw still image (always present).
  final String rawImagePath;

  /// Quad in raw image pixel coordinates.
  final Quad detectedQuad;

  /// Pixel size of the raw image.
  final Size rawImageSize;

  /// Non-null when the native warp pipeline failed for this capture. The
  /// raw image and quad are still valid; the developer can ask the user
  /// to retake or to nudge corners via `EditCornersScreen`.
  final String? warpError;

  static ScanResult fromMap(Map<dynamic, dynamic> m) {
    final rawPath = m['rawImagePath'];
    final quadMap = m['quad'];
    final sizeRaw = m['rawImageSize'];
    if (rawPath is! String || quadMap is! Map || sizeRaw is! List ||
        sizeRaw.length < 2) {
      throw ScannerCaptureException('Malformed capture payload: $m');
    }
    return ScanResult(
      croppedImagePath: m['croppedImagePath'] as String?,
      rawImagePath: rawPath,
      detectedQuad: Quad.fromMap(quadMap),
      rawImageSize: Size(
        (sizeRaw[0] as num).toDouble(),
        (sizeRaw[1] as num).toDouble(),
      ),
      warpError: m['warpError'] as String?,
    );
  }
}

/// Configuration for a scanner session. Every flag has a sensible default;
/// developers override only what they care about.
class ScannerConfig {
  const ScannerConfig({
    // Detection
    this.enableLiveDetection = true,
    this.enableAutoCapture = true,
    this.autoCaptureStabilityDuration = const Duration(milliseconds: 800),
    this.autoCaptureCornerThreshold = 0.02,
    this.enableAutoCaptureConfirmation = true,
    this.autoCaptureConfirmationDelay = const Duration(milliseconds: 350),
    this.detectionThrottleHz = 15,
    this.enableQuadSmoothing = true,
    this.quadSmoothingWindow = 5,
    // Capture
    this.enablePerspectiveWarp = true,
    this.jpegQuality = 100,
    this.imageEnhancement = ImageEnhancement.none,
    this.outputFormat = ImageFormat.jpeg,
    this.captureResolution = Resolution.high,
    // Camera
    this.initialFlashMode = FlashMode.auto,
    this.initialLens = CameraLens.back,
    this.enableCameraSwitch = true,
    this.enableTapToFocus = true,
    this.enablePinchToZoom = true,
    // Status stream
    this.enableLowLightDetection = true,
    this.enableStabilityStatus = true,
    // Lifecycle
    this.pauseOnBackground = true,
    this.resumeOnForeground = true,
    // Diagnostics
    this.enableDebugOverlay = false,
    this.enableTelemetryLogging = false,
  })  : assert(detectionThrottleHz > 0 && detectionThrottleHz <= 60),
        assert(jpegQuality >= 1 && jpegQuality <= 100),
        assert(autoCaptureCornerThreshold >= 0);

  // Detection

  /// Master switch for the per-frame edge-detection pipeline. When
  /// `false`, no quad events are emitted and auto-capture cannot fire.
  final bool enableLiveDetection;

  /// When `true`, the controller fires the shutter automatically once
  /// the detected quad has been stable long enough (subject to the
  /// confirmation phase if `enableAutoCaptureConfirmation` is `true`).
  final bool enableAutoCapture;

  /// How long the document quad must hold "still" (per
  /// [autoCaptureCornerThreshold]) before the controller enters the
  /// confirmation phase (or fires immediately when
  /// [enableAutoCaptureConfirmation] is false). Handheld scanning is
  /// never perfectly motionless — 800 ms at 2% jitter is a realistic
  /// target.
  final Duration autoCaptureStabilityDuration;

  /// Maximum per-corner movement between consecutive frames, expressed as
  /// a fraction of the preview's normalized `[0,1]` coordinate space
  /// (NOT pixels). `0.02` means "no corner moved more than 2% of the
  /// frame width." Tighter values demand a tripod-steady hand; looser
  /// values fire on shakier hands but risk capturing motion-blurred
  /// frames.
  final double autoCaptureCornerThreshold;

  /// When true, the controller emits [DetectionStatus.confirming] for
  /// [autoCaptureConfirmationDelay] before actually triggering the
  /// capture. Mirrors VisionKit's "hold still" cue and gives the user
  /// a chance to abort by moving the camera.
  final bool enableAutoCaptureConfirmation;

  /// How long the quad must remain stable *during the confirmation phase*
  /// before the capture actually fires. Total time from "becomes stable"
  /// to "shutter" is therefore `autoCaptureStabilityDuration +
  /// autoCaptureConfirmationDelay` when confirmation is enabled.
  final Duration autoCaptureConfirmationDelay;

  final int detectionThrottleHz;

  /// Apply a median filter across recent frames before emitting the quad
  /// downstream. Kills single-frame jitter without adding meaningful lag.
  final bool enableQuadSmoothing;

  /// Window size for the median filter. Must be odd. Larger = smoother but
  /// laggier — 5 frames at 15 Hz is ~330 ms of latency, which feels live.
  final int quadSmoothingWindow;

  // Capture
  final bool enablePerspectiveWarp;
  /// JPEG compression quality `1`–`100` for both raw and cropped outputs
  /// written to disk. Defaults to **100** — best for OCR or
  /// re-processing pipelines that don't want lossy compression. Drop to
  /// `~92` if disk size matters (visually indistinguishable from 100
  /// and ~3× smaller).
  final int jpegQuality;

  /// Post-warp processing applied to the cropped document image. Defaults
  /// to [ImageEnhancement.none] (pure dewarp, unmodified pixels). Applies
  /// to both the capture's cropped output and re-warps via
  /// `EditCornersScreen`. The raw image is never enhanced.
  final ImageEnhancement imageEnhancement;

  /// Output container format for captures. JPEG is the only fully
  /// supported value today; PNG is reserved for a future release.
  final ImageFormat outputFormat;

  /// Capture resolution hint passed to the platform's photo output.
  /// `Resolution.auto` lets the OS pick; `high` / `max` raise the
  /// preset where supported.
  final Resolution captureResolution;

  // Camera

  /// Initial flash / torch mode the camera starts in.
  final FlashMode initialFlashMode;

  /// Which lens the camera starts on. Use `CameraLens.front` for
  /// selfie-mode scanning of whiteboards, etc.
  final CameraLens initialLens;

  /// Hint that the host UI may expose a camera-switch control. Currently
  /// informational only — the package does not render a switch button
  /// itself; consumers wire it via `controller.switchCamera()`.
  final bool enableCameraSwitch;

  /// When `true`, tapping the preview triggers a one-shot focus +
  /// auto-exposure at that location and renders a brief focus reticle.
  /// The camera reverts to continuous autofocus after ~3 s.
  /// Continuous autofocus stays on regardless of this flag — disabling
  /// only suppresses the tap gesture and the programmatic
  /// `DoclensController.focusAt(...)` call.
  final bool enableTapToFocus;

  /// When `true`, pinching the preview drives the camera's zoom level
  /// (where supported by the OS). Currently a hint only — the native
  /// pipeline does not yet implement pinch handling; reserved for a
  /// future release.
  final bool enablePinchToZoom;

  // Status stream

  /// When `true`, native estimates a low-light flag from frame luma and
  /// emits it on `DoclensController.lowLightStream`.
  final bool enableLowLightDetection;

  /// When `true`, the controller emits coarse `DetectionStatus` values
  /// (`searching`, `tooFar`, `tooClose`, `tilted`, `aligned`,
  /// `confirming`, `noPaper`) on `statusStream` derived from the
  /// detected quad.
  final bool enableStabilityStatus;

  // Lifecycle

  /// When `true`, `DoclensView` calls `controller.pause()` when the host
  /// app moves to the background. Saves battery and avoids holding the
  /// camera while another app uses it.
  final bool pauseOnBackground;

  /// When `true`, `DoclensView` calls `controller.resume()` when the
  /// host app comes back to the foreground.
  final bool resumeOnForeground;

  // Diagnostics

  /// When `true`, `DoclensView` paints its `debugOverlayBuilder` slot.
  /// Builder is responsible for rendering FPS / current quad / etc. —
  /// the package does not render anything itself.
  final bool enableDebugOverlay;

  /// When `true`, the controller writes auto-capture state-machine
  /// transitions to `debugPrint` (prefix `[fnds]`). Useful when a
  /// scanner appears stuck and you need to see which gate is failing.
  final bool enableTelemetryLogging;

  Map<String, dynamic> toMap() => {
        'enableLiveDetection': enableLiveDetection,
        'detectionThrottleHz': detectionThrottleHz,
        'enablePerspectiveWarp': enablePerspectiveWarp,
        'jpegQuality': jpegQuality,
        'imageEnhancement': imageEnhancement.name,
        'outputFormat': outputFormat.name,
        'captureResolution': captureResolution.name,
        'initialFlashMode': initialFlashMode.name,
        'initialLens': initialLens.name,
        'enableTapToFocus': enableTapToFocus,
        'enablePinchToZoom': enablePinchToZoom,
        'enableLowLightDetection': enableLowLightDetection,
      };
}

/// Exceptions the package throws. Developers catch these.
abstract class ScannerException implements Exception {
  const ScannerException(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}

class ScannerPermissionException extends ScannerException {
  const ScannerPermissionException(
      [super.message = 'Camera permission denied']);
}

class ScannerUnavailableException extends ScannerException {
  const ScannerUnavailableException(super.message);
}

class ScannerInitializationException extends ScannerException {
  const ScannerInitializationException(super.message);
}

class ScannerCaptureException extends ScannerException {
  const ScannerCaptureException(super.message);
}
