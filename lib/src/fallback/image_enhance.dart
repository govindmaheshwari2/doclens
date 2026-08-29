import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models.dart';

/// Pure-Dart post-warp image processing — the off-mobile fallback for the
/// native `ImageEnhancement` pipeline.
///
/// These run on the raw RGBA pixels of a decoded image using only `dart:ui`,
/// so they work on every platform including web. They are honest
/// approximations of the native effects, not pixel-identical to Apple's
/// `CIDocumentEnhancer` or the Android background-division pass:
///
/// - [ImageEnhancement.none] — returned unchanged.
/// - [ImageEnhancement.grayscale] — luma desaturation.
/// - [ImageEnhancement.enhanced] — per-channel percentile contrast stretch,
///   which whitens the background and lifts faded ink under uneven light.
/// - [ImageEnhancement.blackAndWhite] — luma + global Otsu threshold to a
///   near-bitonal page (global, not adaptive).
class ImageEnhance {
  const ImageEnhance._();

  /// Apply [enhancement] to [image], returning a new image. Returns [image]
  /// itself for [ImageEnhancement.none] (caller must not double-dispose).
  static Future<ui.Image> apply(
    ui.Image image,
    ImageEnhancement enhancement,
  ) async {
    if (enhancement == ImageEnhancement.none) return image;

    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return image;
    final pixels = byteData.buffer.asUint8List();
    final w = image.width;
    final h = image.height;

    switch (enhancement) {
      case ImageEnhancement.none:
        return image;
      case ImageEnhancement.grayscale:
        _grayscale(pixels);
        break;
      case ImageEnhancement.enhanced:
        _contrastStretch(pixels);
        break;
      case ImageEnhancement.blackAndWhite:
        _grayscale(pixels);
        _otsuThreshold(pixels);
        break;
    }

    return _imageFromRgba(pixels, w, h);
  }

  static void _grayscale(Uint8List px) {
    for (var i = 0; i < px.length; i += 4) {
      final g =
          (px[i] * 0.299 + px[i + 1] * 0.587 + px[i + 2] * 0.114).round();
      final v = g.clamp(0, 255);
      px[i] = v;
      px[i + 1] = v;
      px[i + 2] = v;
    }
  }

  /// Stretch each colour channel between its 2nd and 98th percentile so the
  /// paper background moves toward white and mid-tones gain contrast. Robust
  /// to a few blown-out or crushed pixels.
  static void _contrastStretch(Uint8List px) {
    for (var ch = 0; ch < 3; ch++) {
      final hist = List<int>.filled(256, 0);
      for (var i = ch; i < px.length; i += 4) {
        hist[px[i]]++;
      }
      final total = px.length ~/ 4;
      final lo = _percentile(hist, total, 0.02);
      final hi = _percentile(hist, total, 0.98);
      final span = (hi - lo);
      if (span <= 0) continue;
      final lut = Uint8List(256);
      for (var v = 0; v < 256; v++) {
        lut[v] = (((v - lo) * 255) / span).round().clamp(0, 255);
      }
      for (var i = ch; i < px.length; i += 4) {
        px[i] = lut[px[i]];
      }
    }
  }

  static int _percentile(List<int> hist, int total, double p) {
    final target = (total * p).floor();
    var cum = 0;
    for (var v = 0; v < 256; v++) {
      cum += hist[v];
      if (cum >= target) return v;
    }
    return 255;
  }

  /// Global Otsu threshold on an already-grayscale buffer.
  static void _otsuThreshold(Uint8List px) {
    final hist = List<int>.filled(256, 0);
    for (var i = 0; i < px.length; i += 4) {
      hist[px[i]]++;
    }
    final total = px.length ~/ 4;
    var sum = 0.0;
    for (var v = 0; v < 256; v++) {
      sum += v * hist[v];
    }
    var sumB = 0.0, wB = 0, threshold = 127;
    var maxVar = -1.0;
    for (var v = 0; v < 256; v++) {
      wB += hist[v];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += v * hist[v];
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > maxVar) {
        maxVar = between;
        threshold = v;
      }
    }
    for (var i = 0; i < px.length; i += 4) {
      final v = px[i] > threshold ? 255 : 0;
      px[i] = v;
      px[i + 1] = v;
      px[i + 2] = v;
    }
  }

  static Future<ui.Image> _imageFromRgba(Uint8List px, int w, int h) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      px,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
