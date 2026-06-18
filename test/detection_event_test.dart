import 'package:doclens/src/platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DetectionEvent defaults sharpness to null', () {
    const e = DetectionEvent();
    expect(e.sharpness, isNull);
  });

  test('DetectionEvent carries a sharpness value', () {
    const e = DetectionEvent(sharpness: 42.5);
    expect(e.sharpness, 42.5);
  });
}
