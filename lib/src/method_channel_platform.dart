import 'dart:async';

import 'package:flutter/services.dart';

import 'fallback/fallback_engine.dart';
import 'models.dart';
import 'ocr.dart';
import 'platform_interface.dart';
import 'quad.dart';

class MethodChannelDoclens extends DoclensPlatform {
  static const _method = MethodChannel('doclens/methods');
  static const _events = EventChannel('doclens/events');

  Stream<DetectionEvent>? _detectionStream;

  /// Message used when a camera / native-only method is called on a platform
  /// with no native plugin (web, desktop). The pure-compute methods
  /// (warp / rotate / detect / OCR) transparently fall back to a Dart
  /// implementation instead of throwing this.
  static const _noNativeMessage =
      'doclens: the native scanner is not available on this platform. Live '
      'camera scanning (initialize/capture) requires Android or iOS. On web '
      'and desktop, use the import → edit-corners → warp fallback '
      '(detectInImage + warpImage are supported without native).';

  ScannerException get _unavailable =>
      const ScannerUnavailableException(_noNativeMessage);

  @override
  Future<int> initialize(ScannerConfig config) async {
    try {
      final result = await _method.invokeMethod<int>('initialize', config.toMap());
      if (result == null) {
        throw const ScannerInitializationException(
            'Native returned null texture id');
      }
      return result;
    } on MissingPluginException {
      throw _unavailable;
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _method.invokeMethod<void>('dispose');
    } on MissingPluginException {
      // Nothing to tear down when there was never a native session.
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<ScanResult> capture() async {
    try {
      final raw = await _method.invokeMethod<Map<dynamic, dynamic>>('capture');
      if (raw == null) {
        throw const ScannerCaptureException('Native returned null capture');
      }
      return ScanResult.fromMap(raw);
    } on MissingPluginException {
      throw _unavailable;
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<String> warpImage({
    required String rawImagePath,
    required Quad quad,
    int jpegQuality = 100,
    ImageEnhancement enhancement = ImageEnhancement.none,
    AutoOrientation autoOrientation = AutoOrientation.none,
  }) async {
    try {
      final out = await _method.invokeMethod<String>('warpImage', {
        'rawImagePath': rawImagePath,
        'quad': quad.toMap(),
        'jpegQuality': jpegQuality,
        'enhancement': enhancement.name,
        'autoOrientation': autoOrientation.name,
      });
      if (out == null) {
        throw const ScannerCaptureException('Warp returned null path');
      }
      return out;
    } on MissingPluginException {
      // No native plugin — dewarp in pure Dart instead of hard-failing.
      return FallbackEngine.warpImage(
        rawImagePath: rawImagePath,
        quad: quad,
        enhancement: enhancement,
      );
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<String> rotateImage({
    required String imagePath,
    required int quarterTurns,
  }) async {
    try {
      final out = await _method.invokeMethod<String>('rotateImage', {
        'imagePath': imagePath,
        'quarterTurns': quarterTurns,
      });
      if (out == null) {
        throw const ScannerCaptureException('Rotate returned null path');
      }
      return out;
    } on MissingPluginException {
      return FallbackEngine.rotateImage(
        imagePath: imagePath,
        quarterTurns: quarterTurns,
      );
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<void> setFlashMode(FlashMode mode) => _wrap(() =>
      _method.invokeMethod<void>('setFlashMode', {'mode': mode.name}));

  @override
  Future<void> focusAt(Offset point) => _wrap(() => _method.invokeMethod<void>(
        'focusAt',
        {'x': point.dx, 'y': point.dy},
      ));

  @override
  Future<void> switchCamera() =>
      _wrap(() => _method.invokeMethod<void>('switchCamera'));

  @override
  Future<void> pause() => _wrap(() => _method.invokeMethod<void>('pause'));

  @override
  Future<void> resume() => _wrap(() => _method.invokeMethod<void>('resume'));

  Future<void> _wrap(Future<void> Function() action) async {
    try {
      await action();
    } on MissingPluginException {
      throw _unavailable;
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Stream<DetectionEvent> detectionEvents() {
    return _detectionStream ??= _events.receiveBroadcastStream().map((raw) {
      final map = raw as Map;
      final quadMap = map['quad'];
      final previewSizeRaw = map['previewSize'];
      Size? previewSize;
      if (previewSizeRaw is List && previewSizeRaw.length >= 2) {
        previewSize = Size(
          (previewSizeRaw[0] as num).toDouble(),
          (previewSizeRaw[1] as num).toDouble(),
        );
      }
      return DetectionEvent(
        quad: quadMap == null ? null : Quad.fromMap(quadMap as Map),
        lowLight: (map['lowLight'] as bool?) ?? false,
        previewSize: previewSize,
        sharpness: (map['sharpness'] as num?)?.toDouble(),
      );
    });
  }

  @override
  Future<OcrResult> recognizeText({required String imagePath}) async {
    try {
      final raw = await _method.invokeMethod<Map<dynamic, dynamic>>(
        'recognizeText',
        {'imagePath': imagePath},
      );
      if (raw == null) {
        throw const ScannerCaptureException('Native returned null OCR result');
      }
      return OcrResult.fromMap(raw);
    } on MissingPluginException {
      // No OS recogniser off-platform: return an empty result, matching the
      // "recogniser unavailable" contract rather than throwing.
      return FallbackEngine.recognizeText(imagePath: imagePath);
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<List<String>?> scanWithNativeUI({
    int pageLimit = 100,
    bool allowGalleryImport = false,
    int jpegQuality = 100,
  }) async {
    try {
      final raw = await _method.invokeMethod<List<dynamic>>(
        'scanWithNativeUI',
        {
          'pageLimit': pageLimit,
          'allowGalleryImport': allowGalleryImport,
          'jpegQuality': jpegQuality,
        },
      );
      if (raw == null) return null;
      return raw.cast<String>();
    } on MissingPluginException {
      throw _unavailable;
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<ImageDetection?> detectInImage({required String imagePath}) async {
    try {
      final raw = await _method.invokeMethod<Map<dynamic, dynamic>>(
        'detectInImage',
        {'imagePath': imagePath},
      );
      if (raw == null) return null;
      final sizeRaw = raw['imageSize'];
      if (sizeRaw is! List || sizeRaw.length < 2) {
        throw ScannerCaptureException('Malformed detectInImage payload: $raw');
      }
      final quadMap = raw['quad'];
      return ImageDetection(
        quad: quadMap == null ? null : Quad.fromMap(quadMap as Map),
        imageSize: Size(
          (sizeRaw[0] as num).toDouble(),
          (sizeRaw[1] as num).toDouble(),
        ),
      );
    } on MissingPluginException {
      // No native detector: report the image size with a null quad so the
      // caller's EditCornersScreen seeds a default inset for manual cropping.
      return FallbackEngine.detectInImage(imagePath: imagePath);
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  ScannerException _translate(PlatformException e) {
    switch (e.code) {
      case 'permission_denied':
        return ScannerPermissionException(e.message ?? 'Camera permission denied');
      case 'unavailable':
        return ScannerUnavailableException(e.message ?? 'Camera unavailable');
      case 'init_failed':
        return ScannerInitializationException(e.message ?? 'Init failed');
      case 'capture_failed':
        return ScannerCaptureException(e.message ?? 'Capture failed');
      default:
        return ScannerInitializationException(
            '${e.code}: ${e.message ?? "unknown"}');
    }
  }
}
