import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Offset, Rect;

import '../quad.dart';

/// Pure-Dart perspective (homography) warp built on `dart:ui`.
///
/// This is the off-mobile fallback for the native dewarp: it maps the four
/// source-quad corners onto an axis-aligned output rectangle using a full
/// projective transform, so a photographed page comes out flat and cropped —
/// exactly like the native pipeline, just computed in Flutter instead of in
/// Kotlin/Swift.
///
/// It uses only `dart:ui` (no `dart:io`), so it compiles and runs on **every**
/// platform including web. Callers on desktop/mobile wrap it with file I/O;
/// web callers can feed decoded bytes directly.
class PerspectiveWarp {
  const PerspectiveWarp._();

  /// Decode [bytes] and dewarp the region bounded by [quadPx] (in decoded-image
  /// pixel coordinates, `TL → TR → BR → BL`) into a flat rectangle.
  ///
  /// The output size is derived from the quad's own edge lengths so the result
  /// keeps the document's real aspect ratio. Returns the warped image; the
  /// caller owns disposing it.
  static Future<ui.Image> warpBytes(Uint8List bytes, Quad quadPx) async {
    final src = await _decode(bytes);
    try {
      return await warpImage(src, quadPx);
    } finally {
      src.dispose();
    }
  }

  /// Dewarp an already-decoded [src] image using [quadPx] (source-pixel space).
  ///
  /// [outWidth]/[outHeight] override the auto-derived output size when set.
  static Future<ui.Image> warpImage(
    ui.Image src,
    Quad quadPx, {
    int? outWidth,
    int? outHeight,
  }) async {
    final size = _outputSize(quadPx, outWidth, outHeight);
    final w = size.$1;
    final h = size.$2;

    // Homography mapping the source quad onto the [0,w]×[0,h] output rect,
    // embedded into a 4x4 so `Canvas.transform` applies the perspective row.
    final matrix = _homographyMatrix(quadPx, w.toDouble(), h.toDouble());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    canvas.transform(matrix);
    canvas.drawImage(
      src,
      Offset.zero,
      ui.Paint()
        ..filterQuality = ui.FilterQuality.high
        ..isAntiAlias = true,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(w, h);
    } finally {
      picture.dispose();
    }
  }

  /// Output dimensions: the longer of each opposing edge pair, so neither axis
  /// is under-sampled. Clamped to a sane pixel range.
  static (int, int) _outputSize(Quad q, int? outW, int? outH) {
    double dist(Offset a, Offset b) => (a - b).distance;
    final width = outW ??
        math.max(
          dist(q.topLeft, q.topRight),
          dist(q.bottomLeft, q.bottomRight),
        ).round();
    final height = outH ??
        math.max(
          dist(q.topLeft, q.bottomLeft),
          dist(q.topRight, q.bottomRight),
        ).round();
    return (
      width.clamp(1, 1 << 15).toInt(),
      height.clamp(1, 1 << 15).toInt(),
    );
  }

  /// Build the column-major 4x4 matrix (as `dart:ui` expects) that maps the
  /// source quad corners to `(0,0) (w,0) (w,h) (0,h)`.
  static Float64List _homographyMatrix(Quad q, double w, double h) {
    // Solve for the 3x3 projective transform H (h22 = 1) that sends each
    // source corner (x,y) to its destination (u,v). 8 unknowns, 8 equations.
    final src = [q.topLeft, q.topRight, q.bottomRight, q.bottomLeft];
    final dst = [
      const Offset(0, 0),
      Offset(w, 0),
      Offset(w, h),
      Offset(0, h),
    ];

    final a = List.generate(8, (_) => List<double>.filled(8, 0));
    final b = List<double>.filled(8, 0);
    for (var i = 0; i < 4; i++) {
      final x = src[i].dx, y = src[i].dy;
      final u = dst[i].dx, v = dst[i].dy;
      a[i * 2] = [x, y, 1, 0, 0, 0, -x * u, -y * u];
      b[i * 2] = u;
      a[i * 2 + 1] = [0, 0, 0, x, y, 1, -x * v, -y * v];
      b[i * 2 + 1] = v;
    }
    final s = _solve(a, b); // [h00,h01,h02,h10,h11,h12,h20,h21]
    final h00 = s[0], h01 = s[1], h02 = s[2];
    final h10 = s[3], h11 = s[4], h12 = s[5];
    final h20 = s[6], h21 = s[7];

    // Column-major storage: index = col*4 + row. z passes through (row/col 2),
    // w' = h20*x + h21*y + 1 lives on row 3.
    final m = Float64List(16);
    m[0] = h00;
    m[1] = h10;
    m[2] = 0;
    m[3] = h20;
    m[4] = h01;
    m[5] = h11;
    m[6] = 0;
    m[7] = h21;
    m[8] = 0;
    m[9] = 0;
    m[10] = 1;
    m[11] = 0;
    m[12] = h02;
    m[13] = h12;
    m[14] = 0;
    m[15] = 1;
    return m;
  }

  /// Gaussian elimination with partial pivoting for a small dense system.
  static List<double> _solve(List<List<double>> a, List<double> b) {
    final n = b.length;
    for (var col = 0; col < n; col++) {
      // Pivot.
      var pivot = col;
      var best = a[col][col].abs();
      for (var r = col + 1; r < n; r++) {
        final v = a[r][col].abs();
        if (v > best) {
          best = v;
          pivot = r;
        }
      }
      if (pivot != col) {
        final tmp = a[col];
        a[col] = a[pivot];
        a[pivot] = tmp;
        final tb = b[col];
        b[col] = b[pivot];
        b[pivot] = tb;
      }
      final diag = a[col][col];
      if (diag == 0) continue; // Degenerate; leave as-is.
      for (var r = 0; r < n; r++) {
        if (r == col) continue;
        final factor = a[r][col] / diag;
        if (factor == 0) continue;
        for (var c = col; c < n; c++) {
          a[r][c] -= factor * a[col][c];
        }
        b[r] -= factor * b[col];
      }
    }
    return [
      for (var i = 0; i < n; i++) a[i][i] == 0 ? 0.0 : b[i] / a[i][i],
    ];
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}
