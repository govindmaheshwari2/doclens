import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Offset, Rect, Size;

import '../models.dart';
import '../ocr.dart';
import '../quad.dart';
import 'file_io.dart';
import 'image_enhance.dart';
import 'perspective_warp.dart';

/// Pure-Dart implementations of the platform methods that don't need a camera
/// or an OS document API: perspective warp, rotate, and single-image detect.
///
/// These power the **off-mobile fallback** — when the native plugin is missing
/// (web, desktop, or a misconfigured host), [MethodChannelDoclens] routes the
/// pure-compute methods here instead of hard-failing with a
/// `MissingPluginException`. The result is that the *import → edit-corners →
/// warp* pipeline keeps working everywhere `dart:io` exists (desktop, and as a
/// safety net on mobile). Live camera scanning still requires native.
///
/// All output is encoded as **PNG** (lossless); the `jpegQuality` knob is
/// ignored here. `autoOrientation` is a no-op in the fallback because upright
/// detection needs on-device OCR, which isn't available off-platform.
class FallbackEngine {
  const FallbackEngine._();

  /// Whether this engine can actually do path-based work on the current
  /// platform. `false` on web (no filesystem).
  static bool get isAvailable => fileIoAvailable;

  /// Dewarp [rawImagePath] with [quad] (raw-image pixel coords) and apply
  /// [enhancement], writing a new PNG and returning its path.
  static Future<String> warpImage({
    required String rawImagePath,
    required Quad quad,
    ImageEnhancement enhancement = ImageEnhancement.none,
  }) async {
    final bytes = await readFileBytes(rawImagePath);
    final warped = await PerspectiveWarp.warpBytes(bytes, quad);
    ui.Image enhanced;
    try {
      enhanced = await ImageEnhance.apply(warped, enhancement);
    } catch (_) {
      enhanced = warped;
    }
    try {
      final png = await _encodePng(enhanced);
      return writeTempImage(png, 'png');
    } finally {
      if (!identical(enhanced, warped)) enhanced.dispose();
      warped.dispose();
    }
  }

  /// Rotate the image at [imagePath] by [quarterTurns] clockwise 90° steps and
  /// write a new PNG, returning its path. `0` re-encodes a copy.
  static Future<String> rotateImage({
    required String imagePath,
    required int quarterTurns,
  }) async {
    final bytes = await readFileBytes(imagePath);
    final src = await _decode(bytes);
    final turns = ((quarterTurns % 4) + 4) % 4;
    try {
      final rotated = await _rotate(src, turns);
      try {
        final png = await _encodePng(rotated);
        return writeTempImage(png, 'png');
      } finally {
        if (!identical(rotated, src)) rotated.dispose();
      }
    } finally {
      src.dispose();
    }
  }

  /// "Detect" a document in [imagePath]. The fallback has no edge detector, so
  /// it returns a `null` quad with the correct [ImageDetection.imageSize] —
  /// [ImageDetection.quadIn] then yields a 10%-inset rectangle the user drags
  /// into place in `EditCornersScreen` (manual crop).
  static Future<ImageDetection?> detectInImage({
    required String imagePath,
  }) async {
    final bytes = await readFileBytes(imagePath);
    final src = await _decode(bytes);
    try {
      return ImageDetection(
        quad: null,
        imageSize: Size(src.width.toDouble(), src.height.toDouble()),
      );
    } finally {
      src.dispose();
    }
  }

  /// The fallback has no OS text recogniser, so OCR yields an empty result
  /// (not an error), matching the "recogniser unavailable" contract.
  static Future<OcrResult> recognizeText({required String imagePath}) async {
    return const OcrResult(text: '', blocks: [], imageSize: Size.zero);
  }

  static Future<ui.Image> _rotate(ui.Image src, int turns) async {
    if (turns == 0) return src;
    final w = src.width, h = src.height;
    final swapped = turns == 1 || turns == 3;
    final outW = swapped ? h : w;
    final outH = swapped ? w : h;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    );
    canvas.translate(outW / 2, outH / 2);
    canvas.rotate(turns * 3.141592653589793 / 2);
    canvas.translate(-w / 2, -h / 2);
    canvas.drawImage(src, Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(outW, outH);
    } finally {
      picture.dispose();
    }
  }

  static Future<Uint8List> _encodePng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const ScannerCaptureException('Fallback PNG encode returned null');
    }
    return data.buffer.asUint8List();
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}
