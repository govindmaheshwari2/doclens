import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:doclens/src/method_channel_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OcrResult.fromMap', () {
    test('parses blocks, lines, boxes and confidence', () {
      final result = OcrResult.fromMap({
        'text': 'Hello\nWorld',
        'imageSize': [1000, 2000],
        'blocks': [
          {
            'text': 'Hello',
            'boundingBox': [10, 20, 100, 30],
            'recognizedLanguage': 'en',
            'lines': [
              {
                'text': 'Hello',
                'boundingBox': [10, 20, 100, 30],
                'confidence': 0.95,
              },
            ],
          },
          {
            'text': 'World',
            'boundingBox': [10, 60, 120, 30],
            'lines': [
              {
                'text': 'World',
                'boundingBox': [10, 60, 120, 30],
                'confidence': null,
              },
            ],
          },
        ],
      });

      expect(result.text, 'Hello\nWorld');
      expect(result.imageSize, const Size(1000, 2000));
      expect(result.isNotEmpty, isTrue);
      expect(result.blocks, hasLength(2));
      expect(result.blocks.first.recognizedLanguage, 'en');
      expect(result.blocks.first.boundingBox, const Rect.fromLTWH(10, 20, 100, 30));
      expect(result.lines, hasLength(2));
      expect(result.lines.first.confidence, 0.95);
      expect(result.lines.last.confidence, isNull);
    });

    test('empty result has no blocks and is reported empty', () {
      final result = OcrResult.fromMap({
        'text': '',
        'imageSize': [640, 480],
        'blocks': <dynamic>[],
      });
      expect(result.isEmpty, isTrue);
      expect(result.text, isEmpty);
      expect(result.lines, isEmpty);
    });

    test('tolerates malformed boxes and missing fields', () {
      final result = OcrResult.fromMap({
        'blocks': [
          {
            'lines': [
              {'text': 'x'},
            ],
          },
        ],
      });
      expect(result.imageSize, Size.zero);
      expect(result.blocks.single.boundingBox, Rect.zero);
      expect(result.blocks.single.lines.single.boundingBox, Rect.zero);
      expect(result.blocks.single.lines.single.confidence, isNull);
    });
  });

  group('MethodChannelDoclens.recognizeText', () {
    const channel = MethodChannel('doclens/methods');
    final platform = MethodChannelDoclens();
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {
          'text': 'hi',
          'imageSize': [100, 200],
          'blocks': [
            {
              'text': 'hi',
              'boundingBox': [0, 0, 50, 10],
              'lines': [
                {'text': 'hi', 'boundingBox': [0, 0, 50, 10], 'confidence': 0.5},
              ],
            },
          ],
        };
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('forwards the image path and parses the result', () async {
      final result = await platform.recognizeText(imagePath: '/tmp/page.jpg');
      expect(calls.single.method, 'recognizeText');
      expect(calls.single.arguments['imagePath'], '/tmp/page.jpg');
      expect(result.text, 'hi');
      expect(result.lines.single.confidence, 0.5);
    });
  });
}
