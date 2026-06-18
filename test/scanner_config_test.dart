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
}
