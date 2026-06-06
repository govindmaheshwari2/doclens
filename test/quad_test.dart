import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Quad', () {
    const unit = Quad(
      topLeft: Offset.zero,
      topRight: Offset(1, 0),
      bottomRight: Offset(1, 1),
      bottomLeft: Offset(0, 1),
    );

    test('area = 1 for unit square', () {
      expect(unit.area, closeTo(1.0, 1e-9));
    });

    test('centroid is center', () {
      expect(unit.centroid, const Offset(0.5, 0.5));
    });

    test('contains center, excludes outside', () {
      expect(unit.contains(const Offset(0.5, 0.5)), isTrue);
      expect(unit.contains(const Offset(2, 2)), isFalse);
    });

    test('scaleToSize multiplies coords', () {
      final s = unit.scaleToSize(const Size(100, 200));
      expect(s.bottomRight, const Offset(100, 200));
    });

    test('toMap / fromMap roundtrip', () {
      final m = unit.toMap();
      final back = Quad.fromMap(m);
      expect(back, unit);
    });

    test('interpolate halfway', () {
      const big = Quad(
        topLeft: Offset.zero,
        topRight: Offset(2, 0),
        bottomRight: Offset(2, 2),
        bottomLeft: Offset(0, 2),
      );
      final mid = Quad.interpolate(unit, big, 0.5);
      expect(mid.bottomRight, const Offset(1.5, 1.5));
    });

    test('maxCornerDistance of identical quads is 0', () {
      expect(unit.maxCornerDistance(unit), 0);
    });
  });
}
