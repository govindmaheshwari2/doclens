import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuadSmoother', () {
    Quad shifted(double dx) => Quad(
          topLeft: Offset(dx, 0),
          topRight: Offset(dx + 1, 0),
          bottomRight: Offset(dx + 1, 1),
          bottomLeft: Offset(dx, 1),
        );

    test('first observation passes through', () {
      final s = QuadSmoother(windowSize: 5);
      expect(s.add(shifted(0)), shifted(0));
    });

    test('outlier in middle of stable window is rejected', () {
      final s = QuadSmoother(windowSize: 5);
      s.add(shifted(0));
      s.add(shifted(0));
      // big jitter spike
      final out = s.add(shifted(100));
      s.add(shifted(0));
      final settled = s.add(shifted(0));
      // After the window fills with stable frames the median snaps back
      // to the cluster, ignoring the spike.
      expect(out!.topLeft.dx, lessThan(100));
      expect(settled, shifted(0));
    });

    test('null observations eventually reset', () {
      final s = QuadSmoother(windowSize: 5, missesBeforeReset: 2);
      s.add(shifted(10));
      s.add(null);
      s.add(null);
      // Buffer was cleared by 2 misses.
      expect(s.add(null), isNull);
    });
  });
}
