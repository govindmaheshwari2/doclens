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
    this.jpegQuality = 92,
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
  final bool enableLiveDetection;
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
  final int jpegQuality;
  final ImageFormat outputFormat;
  final Resolution captureResolution;

  // Camera
  final FlashMode initialFlashMode;
  final CameraLens initialLens;
  final bool enableCameraSwitch;
  final bool enableTapToFocus;
  final bool enablePinchToZoom;

  // Status stream
  final bool enableLowLightDetection;
  final bool enableStabilityStatus;

  // Lifecycle
  final bool pauseOnBackground;
  final bool resumeOnForeground;

  // Diagnostics
  final bool enableDebugOverlay;
  final bool enableTelemetryLogging;

  Map<String, dynamic> toMap() => {
        'enableLiveDetection': enableLiveDetection,
        'detectionThrottleHz': detectionThrottleHz,
        'enablePerspectiveWarp': enablePerspectiveWarp,
        'jpegQuality': jpegQuality,
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
