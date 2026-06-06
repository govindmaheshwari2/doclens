import 'dart:ui';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_platform.dart';
import 'models.dart';
import 'quad.dart';

/// Raw event from the native detection stream.
///
/// Either [quad]/[lowLight] is set (a regular detection frame), or
/// [previewSize] is set (a one-time metadata event the native side fires
/// when it learns the camera buffer dimensions). Consumers should treat
/// `previewSize` events as info-only and not clear the current quad.
class DetectionEvent {
  const DetectionEvent({this.quad, this.lowLight = false, this.previewSize});
  final Quad? quad;
  final bool lowLight;
  final Size? previewSize;

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
}
