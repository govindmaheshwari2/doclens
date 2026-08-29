import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sharpness gate defaults are additive and safe', () {
    const c = ScannerConfig();
    expect(c.enableSharpnessGate, isTrue);
    expect(c.autoCaptureFocusTimeout, const Duration(milliseconds: 2500));
    expect(c.sharpnessFloor, 8.0);
  });

  test('toMap exposes sharpness fields to native', () {
    final m = const ScannerConfig().toMap();
    expect(m['enableSharpnessGate'], isTrue);
    expect(m['sharpnessFloor'], 8.0);
  });

  test('focusing status exists', () {
    expect(DetectionStatus.values, contains(DetectionStatus.focusing));
  });

  group('detection polarity', () {
    test('defaults preserve the pre-existing paper-bright behavior', () {
      const c = ScannerConfig();
      expect(c.detectionPolarity, DetectionPolarity.brighter);
      // The bias that used to be hardcoded in the Android detector.
      expect(c.detectionThresholdOffset, 20);
    });

    test('toMap exposes both knobs to native', () {
      final m = const ScannerConfig().toMap();
      expect(m['detectionPolarity'], 'brighter');
      expect(m['detectionThresholdOffset'], 20);
    });

    test('toMap carries an overridden polarity as its enum name', () {
      final m = const ScannerConfig(
        detectionPolarity: DetectionPolarity.darker,
        detectionThresholdOffset: 8,
      ).toMap();
      expect(m['detectionPolarity'], 'darker');
      expect(m['detectionThresholdOffset'], 8);
      expect(
        const ScannerConfig(detectionPolarity: DetectionPolarity.auto)
            .toMap()['detectionPolarity'],
        'auto',
      );
    });

    test('polarity covers brighter, darker and auto', () {
      expect(DetectionPolarity.values, [
        DetectionPolarity.brighter,
        DetectionPolarity.darker,
        DetectionPolarity.auto,
      ]);
    });

    test('threshold offset is asserted into 0..128', () {
      // Held in variables so the constructor calls aren't const-evaluated at
      // compile time — the assertion has to fire at runtime for `expect`.
      var offset = -1;
      expect(() => ScannerConfig(detectionThresholdOffset: offset),
          throwsA(isA<AssertionError>()));
      offset = 129;
      expect(() => ScannerConfig(detectionThresholdOffset: offset),
          throwsA(isA<AssertionError>()));
      expect(const ScannerConfig(detectionThresholdOffset: 0)
          .detectionThresholdOffset, 0);
      expect(const ScannerConfig(detectionThresholdOffset: 128)
          .detectionThresholdOffset, 128);
    });
  });
}
