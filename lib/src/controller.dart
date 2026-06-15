import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'method_channel_platform.dart';
import 'models.dart';
import 'platform_interface.dart';
import 'quad.dart';
import 'quad_smoother.dart';
import 'stability_tracker.dart';
import 'status_classifier.dart';

/// Owns a scanning session: native pipeline lifecycle, detection streams,
/// auto-capture decisioning, and exposed status.
///
/// Construct one per scanner screen. Call [initialize] before mounting the
/// widget. Call [dispose] when the screen is gone.
class DoclensController extends ChangeNotifier {
  DoclensController({ScannerConfig config = const ScannerConfig()})
      : _config = config,
        _flashMode = config.initialFlashMode {
    if (DoclensPlatform.instance is! MethodChannelDoclens) {
      DoclensPlatform.instance = MethodChannelDoclens();
    }
    _stability = StabilityTracker(
      cornerThreshold: _config.autoCaptureCornerThreshold,
      stabilityDuration: _config.autoCaptureStabilityDuration,
    );
  }

  final ScannerConfig _config;
  ScannerConfig get config => _config;

  late final StabilityTracker _stability;
  late final QuadSmoother? _smoother = _config.enableQuadSmoothing
      ? QuadSmoother(windowSize: _config.quadSmoothingWindow)
      : null;
  final StatusClassifier _classifier = const StatusClassifier();

  int? _textureId;
  int? get textureId => _textureId;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  bool _disposed = false;

  StreamSubscription<DetectionEvent>? _eventSub;

  final StreamController<Quad?> _quadCtrl = StreamController.broadcast();
  final StreamController<DetectionStatus> _statusCtrl =
      StreamController.broadcast();
  final StreamController<ScanResult> _autoCaptureCtrl =
      StreamController.broadcast();
  final StreamController<bool> _lowLightCtrl = StreamController.broadcast();
  final StreamController<Size> _previewSizeCtrl = StreamController.broadcast();

  Stream<Quad?> get quadStream => _quadCtrl.stream;
  Stream<DetectionStatus> get statusStream => _statusCtrl.stream;
  Stream<ScanResult> get autoCaptureStream => _autoCaptureCtrl.stream;
  Stream<bool> get lowLightStream => _lowLightCtrl.stream;

  /// Emits the preview buffer's pixel size the first time native learns it
  /// (and again after orientation/lens changes). Use this to size your
  /// preview widget so the quad overlay aligns with the rendered pixels.
  Stream<Size> get previewSizeStream => _previewSizeCtrl.stream;

  Size? _previewSize;
  Size? get previewSize => _previewSize;

  Quad? _lastQuad;
  Quad? get lastQuad => _lastQuad;

  DetectionStatus _status = DetectionStatus.searching;
  DetectionStatus get status => _status;

  FlashMode _flashMode;
  FlashMode get flashMode => _flashMode;

  bool _capturing = false;
  bool get isCapturing => _capturing;

  DateTime? _autoCaptureCooldownUntil;
  Timer? _confirmationTimer;
  bool _inConfirmation = false;

  /// Start the native session. Must be called before mounting the widget.
  Future<void> initialize() async {
    _ensureNotDisposed();
    if (_initialized) return;
    _textureId = await DoclensPlatform.instance.initialize(_config);
    _eventSub = DoclensPlatform.instance
        .detectionEvents()
        .listen(_onDetection, onError: (Object e) {
      // Detection errors are non-fatal; surface as status.
      _emitStatus(DetectionStatus.searching);
    });
    _initialized = true;
    notifyListeners();
  }

  void _onDetection(DetectionEvent event) {
    if (_disposed) return;

    final ps = event.previewSize;
    if (ps != null && ps != _previewSize) {
      _previewSize = ps;
      _previewSizeCtrl.add(ps);
      notifyListeners();
    }
    if (event.isPreviewSizeOnly) return;

    // Run the raw quad through a median filter so jitter doesn't reach the
    // overlay or the stability tracker. Smoothing is a no-op when disabled.
    final smoothed = _smoother?.add(event.quad) ?? event.quad;
    _lastQuad = smoothed;
    _quadCtrl.add(smoothed);

    if (_config.enableLowLightDetection) {
      _lowLightCtrl.add(event.lowLight);
    }

    final classified = _classifier.classify(quad: smoothed);
    if (_config.enableStabilityStatus) {
      // While we're in the confirmation window keep emitting `confirming`
      // (as long as the geometry hasn't drifted away from aligned).
      if (_inConfirmation && classified == DetectionStatus.aligned) {
        _emitStatus(DetectionStatus.confirming);
      } else {
        _emitStatus(classified);
      }
    }

    if (_config.enableAutoCapture && !_capturing && !_inAutoCaptureCooldown()) {
      final stable = _stability.update(smoothed);
      // Auto-capture gating:
      //  (a) we have a quad,
      //  (b) StabilityTracker says it's been still long enough,
      //  (c) StatusClassifier says the geometry is actually document-like
      //      (using `classified`, not `_status`, because `_status` may be
      //      `confirming` mid-window and that compared `false` here).
      final geometryReady =
          stable && smoothed != null && classified == DetectionStatus.aligned;

      _log(
        'autoCapture gate: rawQuad=${event.quad != null} '
        'smoothed=${smoothed != null} stable=$stable '
        'classified=${classified.name} status=${_status.name} '
        'inConfirmation=$_inConfirmation capturing=$_capturing '
        'cooldown=${_inAutoCaptureCooldown()} → ready=$geometryReady',
      );

      if (geometryReady) {
        if (_config.enableAutoCaptureConfirmation) {
          _startConfirmationPhase();
        } else {
          unawaited(_autoCapture());
        }
      } else if (_inConfirmation) {
        // Confirmation in flight but geometry no longer ready — abort.
        _log('autoCapture: confirmation cancelled — geometry no longer ready');
        _cancelConfirmation();
      }
    }
  }

  void _log(String message) {
    if (!_config.enableTelemetryLogging) return;
    // ignore: avoid_print
    debugPrint('[fnds] $message');
  }

  /// Enter the brief "confirming — about to shoot" phase. UI typically
  /// pulses or recolours the overlay during this window so the user knows
  /// the capture is imminent and can move the camera away to abort.
  void _startConfirmationPhase() {
    if (_inConfirmation) return;
    _log('autoCapture: entering confirmation phase '
        '(${_config.autoCaptureConfirmationDelay.inMilliseconds} ms)');
    _inConfirmation = true;
    _emitStatus(DetectionStatus.confirming);
    _confirmationTimer?.cancel();
    _confirmationTimer = Timer(_config.autoCaptureConfirmationDelay, () {
      if (_disposed || _capturing) {
        _log('autoCapture: timer fired but disposed/capturing — aborting');
        _inConfirmation = false;
        return;
      }
      _log('autoCapture: confirmation timer elapsed → capturing');
      _inConfirmation = false;
      unawaited(_autoCapture());
    });
  }

  void _cancelConfirmation() {
    if (!_inConfirmation) return;
    _log('autoCapture: cancelConfirmation called');
    _inConfirmation = false;
    _confirmationTimer?.cancel();
    _confirmationTimer = null;
    // Drop back to whatever the classifier last said.
    _emitStatus(_classifier.classify(quad: _lastQuad));
  }

  bool _inAutoCaptureCooldown() {
    final until = _autoCaptureCooldownUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _autoCaptureCooldownUntil = null;
      return false;
    }
    return true;
  }

  Future<void> _autoCapture() async {
    if (_capturing) return;
    _capturing = true;
    _log('autoCapture: native capture starting');
    try {
      final result = await DoclensPlatform.instance.capture();
      _log('autoCapture: native capture succeeded '
          '(cropped=${result.croppedImagePath != null}, '
          'warpError=${result.warpError})');
      _autoCaptureCtrl.add(result);
    } catch (e, st) {
      _log('autoCapture: native capture FAILED: $e');
      _autoCaptureCtrl.addError(e, st);
    } finally {
      _capturing = false;
      _stability.reset();
      // Pause auto-capture briefly so we don't immediately re-fire on the
      // same scene (e.g. after a warp failure or while the user is still
      // looking at the result screen).
      _autoCaptureCooldownUntil =
          DateTime.now().add(const Duration(milliseconds: 1500));
    }
  }

  void _emitStatus(DetectionStatus status) {
    if (status != _status) {
      _status = status;
      _statusCtrl.add(status);
      // Notify ChangeNotifier listeners (e.g. AnimatedBuilder /
      // ListenableBuilder bound to the controller). Without this, the
      // public `status` getter mutates silently and chrome bits read
      // through ChangeNotifier — like the drop-in screen's status
      // readout and top instrument bar — never repaint.
      notifyListeners();
    }
  }

  /// Trigger a full-resolution capture using the most recently detected quad.
  /// Throws [StateError] if a capture is already in flight.
  Future<ScanResult> capture() async {
    _ensureReady();
    if (_capturing) {
      throw StateError('Capture already in progress');
    }
    _capturing = true;
    notifyListeners();
    try {
      return await DoclensPlatform.instance.capture();
    } finally {
      _capturing = false;
      notifyListeners();
    }
  }

  /// Re-warp [rawImagePath] using a user-edited [quad]. Used by EditCornersScreen.
  ///
  /// Applies the session's [ScannerConfig.imageEnhancement] and
  /// [ScannerConfig.autoOrientation] to the result, so a re-warp matches the
  /// original capture's processing.
  Future<String> warpImage(String rawImagePath, Quad quad) {
    _ensureReady();
    return DoclensPlatform.instance.warpImage(
      rawImagePath: rawImagePath,
      quad: quad,
      jpegQuality: _config.jpegQuality,
      enhancement: _config.imageEnhancement,
      autoOrientation: _config.autoOrientation,
    );
  }

  /// Rotate the image at [imagePath] by [quarterTurns] clockwise 90° steps,
  /// writing a new file and returning its path. The source file is left
  /// untouched.
  ///
  /// Use this to expose a manual "rotate" control in your review UI (or to
  /// correct a capture when [ScannerConfig.autoOrientation] is
  /// [AutoOrientation.none]). [quarterTurns] is normalized modulo 4, so
  /// `-1` (one turn counter-clockwise) and `5` (one turn clockwise) are both
  /// valid; `0` simply re-encodes a copy.
  ///
  /// Pure file operation — needs no camera, so it works whether or not
  /// [initialize] has been called. (You can also call
  /// `DoclensPlatform.instance.rotateImage(...)` directly without a
  /// controller.)
  Future<String> rotateImage(String imagePath, int quarterTurns) {
    _ensureNotDisposed();
    return DoclensPlatform.instance.rotateImage(
      imagePath: imagePath,
      quarterTurns: quarterTurns,
    );
  }

  Future<void> setFlashMode(FlashMode mode) async {
    _ensureReady();
    await DoclensPlatform.instance.setFlashMode(mode);
    _flashMode = mode;
    notifyListeners();
  }

  Future<void> cycleFlashMode() {
    const order = [FlashMode.off, FlashMode.auto, FlashMode.on, FlashMode.torch];
    final next = order[(order.indexOf(_flashMode) + 1) % order.length];
    return setFlashMode(next);
  }

  Future<void> switchCamera() {
    _ensureReady();
    return DoclensPlatform.instance.switchCamera();
  }

  /// Tap-to-focus. [point] is in the preview widget's normalized
  /// `[0, 1]` portrait space (origin top-left). Triggers a one-shot
  /// focus + auto-exposure at that location; native drops back to
  /// continuous autofocus after ~3 s.
  ///
  /// No-op when [ScannerConfig.enableTapToFocus] is false.
  Future<void> focusAt(Offset point) {
    _ensureReady();
    if (!_config.enableTapToFocus) return Future.value();
    return DoclensPlatform.instance.focusAt(point);
  }

  Future<void> pause() {
    _ensureReady();
    return DoclensPlatform.instance.pause();
  }

  /// Resume the live preview after a [pause].
  ///
  /// Resuming clears any carried-over stability/confirmation state and
  /// applies a short auto-capture grace window ([resumeAutoCaptureGrace]).
  /// Without this, a document still sitting aligned in frame from before the
  /// pause would re-trip auto-capture within a frame or two of resuming —
  /// giving the user no chance to reposition after a retake.
  Future<void> resume() {
    _ensureReady();
    _cancelConfirmation();
    _stability.reset();
    _autoCaptureCooldownUntil = DateTime.now().add(resumeAutoCaptureGrace);
    return DoclensPlatform.instance.resume();
  }

  /// How long after [resume] auto-capture stays suppressed so the user can
  /// reframe before the scanner re-arms. The user must also hold the
  /// document still again for [ScannerConfig.autoCaptureStabilityDuration]
  /// once the grace elapses, because [resume] resets the stability tracker.
  static const Duration resumeAutoCaptureGrace = Duration(milliseconds: 1200);

  void _ensureReady() {
    _ensureNotDisposed();
    if (!_initialized) {
      throw const ScannerInitializationException(
          'Controller not initialized — call initialize() first');
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('DoclensController used after dispose()');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _confirmationTimer?.cancel();
    _confirmationTimer = null;
    await _eventSub?.cancel();
    if (_initialized) {
      try {
        await DoclensPlatform.instance.dispose();
      } catch (_) {
        // Disposal best-effort.
      }
    }
    await _quadCtrl.close();
    await _statusCtrl.close();
    await _autoCaptureCtrl.close();
    await _lowLightCtrl.close();
    await _previewSizeCtrl.close();
    super.dispose();
  }
}
