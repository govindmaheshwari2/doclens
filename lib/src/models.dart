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

  /// Quad is aligned and stable, but the frame is not yet verifiably in
  /// focus. The controller has requested a focus-lock on the document and
  /// is holding the shutter until sharpness clears threshold (or the
  /// focus timeout elapses). UI shows a "focusing — hold steady" hint.
  focusing,

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

/// Automatic upright-orientation correction for the cropped document.
///
/// A capture only ever knows the document's *in-frame* orientation — if the
/// page (or its text) was sideways or upside-down when shot, the dewarped
/// crop comes out sideways or upside-down too. [auto] detects the dominant
/// text direction on-device and rotates the crop in 90° steps so the text
/// reads upright.
///
/// Detection uses the OS text APIs already present on each platform — Apple
/// Vision (`VNRecognizeTextRequest`) on iOS and Play-services ML Kit text
/// recognition on Android — so **no model is bundled** (the Android model is
/// delivered on demand by Google Play services, exactly like the OS-native
/// scanner). When no text is found, the page is blank/graphical, or the API is
/// unavailable, the crop is left exactly as warped.
///
/// Like [ImageEnhancement], orientation correction runs on the
/// perspective-corrected crop only — the raw image ([ScanResult.rawImagePath])
/// is never rotated — and applies to both the capture's cropped output and
/// re-warps performed via `EditCornersScreen`.
enum AutoOrientation {
  /// Leave the crop exactly as warped (its in-frame orientation). Default.
  none,

  /// Detect the dominant text direction and rotate the crop to the nearest
  /// 90° so text reads upright. Falls back to [none] when no confident text
  /// orientation can be found.
  auto,
}

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

  /// Returns a copy with the given fields replaced. Useful after a manual
  /// rotate or re-warp, to persist the new [croppedImagePath] back into a
  /// result the caller is holding.
  ScanResult copyWith({
    String? croppedImagePath,
    String? rawImagePath,
    Quad? detectedQuad,
    Size? rawImageSize,
    String? warpError,
  }) {
    return ScanResult(
      croppedImagePath: croppedImagePath ?? this.croppedImagePath,
      rawImagePath: rawImagePath ?? this.rawImagePath,
      detectedQuad: detectedQuad ?? this.detectedQuad,
      rawImageSize: rawImageSize ?? this.rawImageSize,
      warpError: warpError ?? this.warpError,
    );
  }

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

/// Result of running document detection on a still image (e.g. one imported
/// from the photo gallery) via [DoclensController.detectInImage].
///
/// Lets you run the package's own **detect → edit → warp** pipeline on an
/// arbitrary image instead of a live capture: feed [imageSize] and a
/// pixel-space quad (from [quadIn]) to `EditCornersScreen`, then warp the
/// image with the user-adjusted corners.
class ImageDetection {
  const ImageDetection({
    required this.quad,
    required this.imageSize,
  });

  /// Detected document quad in **normalized** `[0, 1]` coordinates
  /// (`topLeft → topRight → bottomRight → bottomLeft`, origin top-left), or
  /// `null` when no document-like quad was found. Scale it into pixel space
  /// with [quadIn] (or `quad.scaleToSize(imageSize)`).
  final Quad? quad;

  /// Pixel size of the image the detection ran on, with any EXIF orientation
  /// already applied (the same upright pixel space the warp operates in). Use
  /// it to size `EditCornersScreen` and to scale [quad] into pixel coords.
  final Size imageSize;

  /// The detected [quad] scaled into [imageSize] pixel coordinates, ready to
  /// seed `EditCornersScreen`. Falls back to a 10%-inset rectangle when no
  /// quad was detected, so the user always has draggable corners to start
  /// from.
  Quad get quadIn {
    final q = quad;
    if (q != null) return q.scaleToSize(imageSize);
    final dx = imageSize.width * 0.1;
    final dy = imageSize.height * 0.1;
    return Quad(
      topLeft: Offset(dx, dy),
      topRight: Offset(imageSize.width - dx, dy),
      bottomRight: Offset(imageSize.width - dx, imageSize.height - dy),
      bottomLeft: Offset(dx, imageSize.height - dy),
    );
  }
}

/// Which side of a frame's brightness the detector should treat as the
/// document.
///
/// **Android only.** The Android detector segments each camera frame by
/// thresholding around the frame's mean luma, so it has to be told which side
/// of that split the document sits on. iOS detects documents with Apple
/// Vision, which is contrast-agnostic and finds dark and light documents
/// alike — this setting is accepted and ignored there.
enum DetectionPolarity {
  /// The document is brighter than what surrounds it — paper on a desk.
  /// The default, and the behavior the detector had before this option
  /// existed.
  brighter,

  /// The document is darker than what surrounds it — a dark ID card, a
  /// saturated trading card, or a glossy photo on a light desk.
  darker,

  /// Run the detector at both polarities on every frame and keep whichever
  /// candidate looks more document-like (solid, away from the frame edges,
  /// and large). Handles a mixed pile where the user does not know what comes
  /// next, at roughly twice the per-frame detection cost — still cheap, since
  /// detection runs on a 256 px luma buffer, but measure before shipping it on
  /// low-end devices at a high [ScannerConfig.detectionThrottleHz].
  auto,
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
    this.enableSharpnessGate = true,
    this.autoCaptureFocusTimeout = const Duration(milliseconds: 2500),
    this.sharpnessFloor = 8.0,
    this.detectionThrottleHz = 15,
    this.detectionPolarity = DetectionPolarity.brighter,
    this.detectionThresholdOffset = 20,
    this.enableQuadSmoothing = true,
    this.quadSmoothingWindow = 5,
    // Capture
    this.enablePerspectiveWarp = true,
    this.jpegQuality = 100,
    this.imageEnhancement = ImageEnhancement.none,
    this.autoOrientation = AutoOrientation.none,
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
        assert(autoCaptureCornerThreshold >= 0),
        assert(sharpnessFloor >= 0),
        assert(detectionThresholdOffset >= 0 &&
            detectionThresholdOffset <= 128);

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

  /// When `true` (default), auto-capture additionally waits for the frame
  /// to be verifiably in focus (see [DetectionStatus.focusing]). When
  /// `false`, auto-capture gates on geometry only (legacy behavior).
  final bool enableSharpnessGate;

  /// Maximum time the controller holds the shutter waiting for focus after
  /// the document first aligns. If sharpness has not cleared threshold by
  /// then, auto-capture fires anyway so the user is never stuck. The user
  /// reviews the result and can re-shoot.
  final Duration autoCaptureFocusTimeout;

  /// Absolute minimum variance-of-Laplacian a frame must reach before it
  /// can be considered in focus. Guards against the adaptive baseline
  /// declaring an entirely-flat (and blurry) scene "sharp".
  final double sharpnessFloor;

  final int detectionThrottleHz;

  /// Which side of the frame's brightness holds the document.
  ///
  /// **Android only** — see [DetectionPolarity]. Defaults to
  /// [DetectionPolarity.brighter], the paper-on-a-desk case, which is what
  /// the detector has always assumed. Set [DetectionPolarity.darker] when
  /// scanning dark ID cards, trading cards, or photos on a light surface, or
  /// [DetectionPolarity.auto] to let each frame decide.
  final DetectionPolarity detectionPolarity;

  /// How far past the frame's mean luma a pixel must be, on `0`–`255`, before
  /// the detector counts it as part of the document.
  ///
  /// **Android only.** The mask keeps pixels above `mean + offset` under
  /// [DetectionPolarity.brighter] and below `mean - offset` under
  /// [DetectionPolarity.darker]; the bias keeps the mask off the noise floor
  /// around the mean, where a flat surface's own gradient would otherwise
  /// carve out shapes. Defaults to `20`, the value that was hardcoded before
  /// this option existed.
  ///
  /// Lower it (`8`–`12`) for documents that barely separate from their
  /// background — an off-white receipt on a white desk. Raise it
  /// (`30`–`45`) in high-contrast scenes to stop shadows and specular
  /// highlights from joining the document's component. Must be in `0`–`128`
  /// — past that the detector's own clamps pin the threshold and a larger
  /// value changes nothing.
  final int detectionThresholdOffset;

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

  /// Automatic upright-orientation correction for the cropped document.
  /// Defaults to [AutoOrientation.none] (the crop keeps its in-frame
  /// orientation). Set to [AutoOrientation.auto] to detect the document's
  /// text direction on-device and rotate the crop in 90° steps so it reads
  /// upright. Applies to the capture's cropped output and to re-warps via
  /// `EditCornersScreen`; the raw image is never rotated.
  final AutoOrientation autoOrientation;

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
        'detectionPolarity': detectionPolarity.name,
        'detectionThresholdOffset': detectionThresholdOffset,
        'enablePerspectiveWarp': enablePerspectiveWarp,
        'jpegQuality': jpegQuality,
        'imageEnhancement': imageEnhancement.name,
        'autoOrientation': autoOrientation.name,
        'outputFormat': outputFormat.name,
        'captureResolution': captureResolution.name,
        'initialFlashMode': initialFlashMode.name,
        'initialLens': initialLens.name,
        'enableTapToFocus': enableTapToFocus,
        'enablePinchToZoom': enablePinchToZoom,
        'enableLowLightDetection': enableLowLightDetection,
        'enableSharpnessGate': enableSharpnessGate,
        'sharpnessFloor': sharpnessFloor,
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
