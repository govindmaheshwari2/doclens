import 'dart:ui';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_platform.dart';
import 'models.dart';
import 'ocr.dart';
import 'quad.dart';

/// Raw event from the native detection stream.
///
/// Either [quad]/[lowLight] is set (a regular detection frame), or
/// [previewSize] is set (a one-time metadata event the native side fires
/// when it learns the camera buffer dimensions). Consumers should treat
/// `previewSize` events as info-only and not clear the current quad.
class DetectionEvent {
  const DetectionEvent({
    this.quad,
    this.lowLight = false,
    this.previewSize,
    this.sharpness,
  });
  final Quad? quad;
  final bool lowLight;
  final Size? previewSize;

  /// Raw variance-of-Laplacian sharpness for this frame (in-quad when a
  /// quad is present, whole-frame otherwise). `null` when the native side
  /// does not provide it — consumers treat null as "no signal".
  final double? sharpness;

  bool get isPreviewSizeOnly => previewSize != null && quad == null;
}

/// Platform interface for the native pipeline. The default implementation
/// uses method + event channels and is registered automatically.
abstract class DoclensPlatform extends PlatformInterface {
  DoclensPlatform() : super(token: _token);
  static final Object _token = Object();

  static DoclensPlatform _instance = MethodChannelDoclens();
  static DoclensPlatform get instance => _instance;
  static set instance(DoclensPlatform p) {
    PlatformInterface.verifyToken(p, _token);
    _instance = p;
  }

  /// Initialize a session. Returns the texture id to render in [Texture].
  Future<int> initialize(ScannerConfig config);

  Future<void> dispose();

  Future<ScanResult> capture();

  Future<String> warpImage({
    required String rawImagePath,
    required Quad quad,
    int jpegQuality = 100,
    ImageEnhancement enhancement = ImageEnhancement.none,
    AutoOrientation autoOrientation = AutoOrientation.none,
  });

  /// Rotate the JPEG at [imagePath] by [quarterTurns] clockwise 90° steps and
  /// write a new file, returning its path. The original file is left
  /// untouched. [quarterTurns] is normalized modulo 4, so negative
  /// (counter-clockwise) and large values are accepted; `0` is a no-op copy.
  Future<String> rotateImage({
    required String imagePath,
    required int quarterTurns,
  });

  Future<void> setFlashMode(FlashMode mode);

  /// Tap-to-focus. `point` is in the preview widget's normalized
  /// `[0, 1]` portrait space (origin top-left). Native uses this to
  /// trigger a one-shot focus + auto-exposure at that location, then
  /// drops back to continuous AF after a short window.
  Future<void> focusAt(Offset point);

  Future<void> switchCamera();

  Future<void> pause();

  Future<void> resume();

  /// Stream of detection frames. Null quad means "nothing detected this frame".
  Stream<DetectionEvent> detectionEvents();

  /// Recognise text (OCR) in the image at [imagePath] entirely on-device.
  ///
  /// Uses the OS text APIs already present on each platform — Apple Vision's
  /// `VNRecognizeTextRequest` on iOS and Play-services ML Kit text recognition
  /// on Android — so no model is bundled. Works on any JPEG/PNG on disk
  /// (typically a [ScanResult.croppedImagePath]); no camera session or
  /// `initialize()` call is required.
  ///
  /// Returns an [OcrResult] with the full text plus per-block / per-line
  /// bounding boxes and confidence. When nothing is recognised (blank or
  /// graphical page, or the recogniser is unavailable) the result is empty
  /// ([OcrResult.isEmpty]) rather than an error.
  Future<OcrResult> recognizeText({required String imagePath});

  /// Present the OS-native document scanner UI (VisionKit on iOS,
  /// ML Kit Document Scanner on Android). Returns the cropped page image
  /// paths, or `null` if the user cancelled.
  ///
  /// This is a completely independent flow from the live preview /
  /// controller. No `initialize()` call is required.
  Future<List<String>?> scanWithNativeUI({
    int pageLimit = 100,
    bool allowGalleryImport = false,
    int jpegQuality = 100,
  });

  /// Run document edge-detection on a still image already on disk — the same
  /// native detector that powers the live preview, but on a single picked /
  /// imported photo (e.g. from the gallery) rather than a camera frame.
  ///
  /// Returns an [ImageDetection] with the detected quad in normalized `[0,1]`
  /// coordinates (or `null` quad when nothing document-like is found) plus the
  /// image's EXIF-upright pixel size. Pair it with `EditCornersScreen` and
  /// [warpImage] to run the full **detect → edit → warp** pipeline on an
  /// imported image. Returns `null` only when the image cannot be read.
  ///
  /// A pure file operation — no camera session or [initialize] call required.
  Future<ImageDetection?> detectInImage({required String imagePath});
}
