import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

const _quad = Quad(
  topLeft: Offset.zero,
  topRight: Offset(100, 0),
  bottomRight: Offset(100, 100),
  bottomLeft: Offset(0, 100),
);
const _size = Size(100, 100);

void main() {
  // Regression: a manual shutter tap with no detected quad returns a valid
  // rawImagePath, a null croppedImagePath, and no warpError. The review
  // screen must display the raw photo, not the empty "No preview" placeholder.
  group('reviewDisplayPath', () {
    test('prefers the cropped path when present', () {
      const result = ScanResult(
        croppedImagePath: '/tmp/crop.jpg',
        rawImagePath: '/tmp/raw.jpg',
        detectedQuad: _quad,
        rawImageSize: _size,
      );
      expect(reviewDisplayPath(result), '/tmp/crop.jpg');
    });

    test('falls back to the raw path when no crop and no warp error', () {
      const result = ScanResult(
        croppedImagePath: null,
        rawImagePath: '/tmp/raw.jpg',
        detectedQuad: _quad,
        rawImageSize: _size,
      );
      expect(reviewDisplayPath(result), '/tmp/raw.jpg');
    });

    test('returns null on a genuine warp failure (shows empty state)', () {
      const result = ScanResult(
        croppedImagePath: null,
        rawImagePath: '/tmp/raw.jpg',
        detectedQuad: _quad,
        rawImageSize: _size,
        warpError: 'warpFailed',
      );
      expect(reviewDisplayPath(result), isNull);
    });

    test('prefers the crop even if a warp error is also reported', () {
      const result = ScanResult(
        croppedImagePath: '/tmp/crop.jpg',
        rawImagePath: '/tmp/raw.jpg',
        detectedQuad: _quad,
        rawImageSize: _size,
        warpError: 'warpFailed',
      );
      expect(reviewDisplayPath(result), '/tmp/crop.jpg');
    });
  });
}
