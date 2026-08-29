import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:doclens/src/method_channel_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Records the config the controller hands to the platform layer.
class _RecordingPlatform extends DoclensPlatform
    with MockPlatformInterfaceMixin {
  ScannerConfig? seenConfig;

  @override
  Future<ImageDetection?> detectInImage({
    required String imagePath,
    ScannerConfig config = const ScannerConfig(),
  }) async {
    seenConfig = config;
    return const ImageDetection(quad: null, imageSize: Size(10, 10));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageDetection.quadIn', () {
    const size = Size(200, 100);

    test('scales a detected normalized quad into pixel space', () {
      const detection = ImageDetection(
        quad: Quad(
          topLeft: Offset(0.1, 0.2),
          topRight: Offset(0.9, 0.2),
          bottomRight: Offset(0.9, 0.8),
          bottomLeft: Offset(0.1, 0.8),
        ),
        imageSize: size,
      );
      final q = detection.quadIn;
      expect(q.topLeft, const Offset(20, 20));
      expect(q.topRight, const Offset(180, 20));
      expect(q.bottomRight, const Offset(180, 80));
      expect(q.bottomLeft, const Offset(20, 80));
    });

    test('falls back to a 10% inset rect when nothing was detected', () {
      const detection = ImageDetection(quad: null, imageSize: size);
      final q = detection.quadIn;
      // 10% of 200 = 20 horizontally, 10% of 100 = 10 vertically.
      expect(q.topLeft, const Offset(20, 10));
      expect(q.topRight, const Offset(180, 10));
      expect(q.bottomRight, const Offset(180, 90));
      expect(q.bottomLeft, const Offset(20, 90));
    });
  });

  group('MethodChannelDoclens.detectInImage', () {
    const channel = MethodChannel('doclens/methods');
    final platform = MethodChannelDoclens();
    final calls = <MethodCall>[];
    Object? response;

    setUp(() {
      calls.clear();
      response = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return response;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('forwards the image path and parses a detected quad', () async {
      response = <String, Object?>{
        'quad': <String, Object?>{
          'topLeft': <double>[0.1, 0.2],
          'topRight': <double>[0.9, 0.2],
          'bottomRight': <double>[0.9, 0.8],
          'bottomLeft': <double>[0.1, 0.8],
        },
        'imageSize': <double>[640, 480],
      };
      final result = await platform.detectInImage(imagePath: '/tmp/pic.jpg');
      expect(calls.single.method, 'detectInImage');
      expect(calls.single.arguments['imagePath'], '/tmp/pic.jpg');
      // Detection knobs ride along so an imported photo segments the same
      // way the live preview does.
      expect(calls.single.arguments['detectionPolarity'], 'brighter');
      expect(calls.single.arguments['detectionThresholdOffset'], 20);
      expect(result, isNotNull);
      expect(result!.imageSize, const Size(640, 480));
      expect(result.quad, isNotNull);
      expect(result.quad!.topLeft, const Offset(0.1, 0.2));
    });

    test('parses a null quad (nothing detected) but keeps the image size',
        () async {
      response = <String, Object?>{
        'quad': null,
        'imageSize': <double>[640, 480],
      };
      final result = await platform.detectInImage(imagePath: '/tmp/pic.jpg');
      expect(result, isNotNull);
      expect(result!.quad, isNull);
      expect(result.imageSize, const Size(640, 480));
    });

    test('forwards the config\'s detection polarity and threshold', () async {
      response = <String, Object?>{
        'quad': null,
        'imageSize': <double>[640, 480],
      };
      await platform.detectInImage(
        imagePath: '/tmp/card.jpg',
        config: const ScannerConfig(
          detectionPolarity: DetectionPolarity.darker,
          detectionThresholdOffset: 12,
        ),
      );
      expect(calls.single.arguments['detectionPolarity'], 'darker');
      expect(calls.single.arguments['detectionThresholdOffset'], 12);
    });

    test('returns null when native returns null', () async {
      response = null;
      final result = await platform.detectInImage(imagePath: '/tmp/pic.jpg');
      expect(result, isNull);
    });
  });

  group('DoclensController.detectInImage', () {
    test('detects with the session config, not the platform defaults',
        () async {
      final recorder = _RecordingPlatform();
      DoclensPlatform.instance = recorder;
      final controller = DoclensController(
        config: const ScannerConfig(
          detectionPolarity: DetectionPolarity.darker,
          detectionThresholdOffset: 12,
        ),
      );
      addTearDown(controller.dispose);

      await controller.detectInImage('/tmp/card.jpg');

      expect(recorder.seenConfig?.detectionPolarity, DetectionPolarity.darker);
      expect(recorder.seenConfig?.detectionThresholdOffset, 12);
    });
  });
}
