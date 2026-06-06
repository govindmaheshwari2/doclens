import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatusClassifier', () {
    const c = StatusClassifier();

    test('no frame yet → searching', () {
      expect(
          c.classify(quad: null, noFrameYet: true),
          DetectionStatus.searching);
    });

    test('frame but no quad → noPaper', () {
      expect(
          c.classify(quad: null, noFrameYet: false),
          DetectionStatus.noPaper);
    });

    test('tiny quad → tooFar', () {
      const tiny = Quad(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.2, 0.1),
        bottomRight: Offset(0.2, 0.2),
        bottomLeft: Offset(0.1, 0.2),
      );
      expect(
          c.classify(quad: tiny, noFrameYet: false),
          DetectionStatus.tooFar);
    });

    test('huge quad → tooClose', () {
      const huge = Quad(
        topLeft: Offset(0.02, 0.02),
        topRight: Offset(0.98, 0.02),
        bottomRight: Offset(0.98, 0.98),
        bottomLeft: Offset(0.02, 0.98),
      );
      expect(
          c.classify(quad: huge, noFrameYet: false),
          DetectionStatus.tooClose);
    });

    test('skewed quad → tilted', () {
      const skewed = Quad(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.05),
        bottomRight: Offset(0.5, 0.9),
        bottomLeft: Offset(0.2, 0.85),
      );
      expect(
          c.classify(quad: skewed, noFrameYet: false),
          DetectionStatus.tilted);
    });

    test('well-formed quad → aligned', () {
      const ok = Quad(
        topLeft: Offset(0.2, 0.2),
        topRight: Offset(0.8, 0.2),
        bottomRight: Offset(0.8, 0.8),
        bottomLeft: Offset(0.2, 0.8),
      );
      expect(
          c.classify(quad: ok, noFrameYet: false),
          DetectionStatus.aligned);
    });
  });
}

