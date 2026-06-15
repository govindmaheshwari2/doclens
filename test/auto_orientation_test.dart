import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:doclens/src/method_channel_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AutoOrientation config', () {
    test('defaults to none', () {
      const config = ScannerConfig();
      expect(config.autoOrientation, AutoOrientation.none);
      expect(config.toMap()['autoOrientation'], 'none');
    });

    test('serializes auto into the native config map', () {
      const config = ScannerConfig(autoOrientation: AutoOrientation.auto);
      expect(config.toMap()['autoOrientation'], 'auto');
    });
  });

  group('MethodChannelDoclens orientation plumbing', () {
    const channel = MethodChannel('doclens/methods');
    final platform = MethodChannelDoclens();
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        // Echo a fake output path for the path-returning methods.
        return '/tmp/out.jpg';
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('warpImage forwards autoOrientation', () async {
      const quad = Quad(
        topLeft: Offset.zero,
        topRight: Offset(1, 0),
        bottomRight: Offset(1, 1),
        bottomLeft: Offset(0, 1),
      );
      await platform.warpImage(
        rawImagePath: '/tmp/raw.jpg',
        quad: quad,
        autoOrientation: AutoOrientation.auto,
      );
      expect(calls.single.method, 'warpImage');
      expect(calls.single.arguments['autoOrientation'], 'auto');
    });

    test('rotateImage forwards path and quarter turns', () async {
      final out = await platform.rotateImage(
        imagePath: '/tmp/page.jpg',
        quarterTurns: -1,
      );
      expect(out, '/tmp/out.jpg');
      expect(calls.single.method, 'rotateImage');
      expect(calls.single.arguments['imagePath'], '/tmp/page.jpg');
      expect(calls.single.arguments['quarterTurns'], -1);
    });
  });
}
