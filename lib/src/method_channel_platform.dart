import 'dart:async';

import 'package:flutter/services.dart';

import 'models.dart';
import 'platform_interface.dart';
import 'quad.dart';

class MethodChannelDoclens extends DoclensPlatform {
  static const _method = MethodChannel('doclens/methods');
  static const _events = EventChannel('doclens/events');

  Stream<DetectionEvent>? _detectionStream;

  @override
  Future<int> initialize(ScannerConfig config) async {
    try {
      final result = await _method.invokeMethod<int>('initialize', config.toMap());
      if (result == null) {
        throw const ScannerInitializationException(
            'Native returned null texture id');
      }
      return result;
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _method.invokeMethod<void>('dispose');
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
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<String> warpImage({
    required String rawImagePath,
    required Quad quad,
    int jpegQuality = 92,
  }) async {
    try {
      final out = await _method.invokeMethod<String>('warpImage', {
        'rawImagePath': rawImagePath,
        'quad': quad.toMap(),
        'jpegQuality': jpegQuality,
      });
      if (out == null) {
        throw const ScannerCaptureException('Warp returned null path');
      }
      return out;
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
      );
    });
  }

  @override
  Future<List<String>?> scanWithNativeUI({
    int pageLimit = 100,
    bool allowGalleryImport = false,
    int jpegQuality = 92,
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
