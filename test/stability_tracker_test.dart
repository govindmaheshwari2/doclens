import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StabilityTracker', () {
    const q1 = Quad(
      topLeft: Offset(10, 10),
      topRight: Offset(110, 10),
      bottomRight: Offset(110, 110),
      bottomLeft: Offset(10, 110),
    );

    test('first frame is never stable', () {
      final t = StabilityTracker(
        cornerThreshold: 5,
        stabilityDuration: const Duration(milliseconds: 100),
      );
      expect(t.update(q1, now: DateTime(2026)), isFalse);
    });

    test('stable after duration passes with small movement', () {
      final t = StabilityTracker(
        cornerThreshold: 5,
        stabilityDuration: const Duration(milliseconds: 100),
      );
      final start = DateTime(2026);
      expect(t.update(q1, now: start), isFalse);
      expect(t.update(q1, now: start.add(const Duration(milliseconds: 50))),
          isFalse);
      expect(t.update(q1, now: start.add(const Duration(milliseconds: 150))),
          isTrue);
    });

    test('large movement resets the stability clock', () {
      final t = StabilityTracker(
        cornerThreshold: 3,
        stabilityDuration: const Duration(milliseconds: 100),
      );
      final start = DateTime(2026);
      t.update(q1, now: start);
      // Big jump
      const q2 = Quad(
        topLeft: Offset(50, 50),
        topRight: Offset(150, 50),
        bottomRight: Offset(150, 150),
        bottomLeft: Offset(50, 150),
      );
      expect(t.update(q2, now: start.add(const Duration(milliseconds: 50))),
          isFalse);
      // Now hold still
      expect(t.update(q2, now: start.add(const Duration(milliseconds: 200))),
          isTrue);
    });

    test('null quad resets', () {
      final t = StabilityTracker(
        cornerThreshold: 5,
        stabilityDuration: const Duration(milliseconds: 100),
      );
      final start = DateTime(2026);
      t.update(q1, now: start);
      expect(
          t.update(null, now: start.add(const Duration(milliseconds: 200))),
          isFalse);
      // After reset, need to start over.
      expect(t.update(q1, now: start.add(const Duration(milliseconds: 300))),
          isFalse);
    });
  });
}
