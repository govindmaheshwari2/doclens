import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:doclens/doclens.dart';
import 'package:doclens/src/fallback/fallback_engine.dart';
import 'package:doclens/src/fallback/file_io.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the pure-Dart off-mobile fallback: the perspective warp, the
/// enhancement passes, and the file-based engine methods. These all use only
/// `dart:ui`, so they run under `flutter test` on the desktop VM.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> solid(int w, int h, Color c) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = c,
    );
    final picture = recorder.endRecording();
    return picture.toImage(w, h);
  }

  Future<ui.Image> twoTone(int w, int h, Color left, Color right) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = left,
    );
    canvas.drawRect(
      Rect.fromLTWH(w / 2, 0, w / 2, h.toDouble()),
      ui.Paint()..color = right,
    );
    final picture = recorder.endRecording();
    return picture.toImage(w, h);
  }

  Future<Uint8List> rgba(ui.Image img) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  }

  Future<List<int>> pixel(ui.Image img, int x, int y) async {
    final px = await rgba(img);
    final i = (y * img.width + x) * 4;
    return [px[i], px[i + 1], px[i + 2], px[i + 3]];
  }

  Future<Uint8List> pngBytes(ui.Image img) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Quad fullQuad(int w, int h) => Quad(
        topLeft: const Offset(0, 0),
        topRight: Offset(w.toDouble(), 0),
        bottomRight: Offset(w.toDouble(), h.toDouble()),
        bottomLeft: Offset(0, h.toDouble()),
      );

  group('PerspectiveWarp', () {
    test('identity quad preserves size and colour', () async {
      final src = await solid(60, 40, const Color(0xFFFF0000));
      final out = await PerspectiveWarp.warpImage(src, fullQuad(60, 40));
      expect(out.width, 60);
      expect(out.height, 40);
      final centre = await pixel(out, 30, 20);
      expect(centre[0], 255);
      expect(centre[1], 0);
      expect(centre[2], 0);
    });

    test('quad selects a sub-region, not the whole image', () async {
      // Left half red, right half blue. Warp only the right half → all blue.
      final src = await twoTone(
        100,
        100,
        const Color(0xFFFF0000),
        const Color(0xFF0000FF),
      );
      final rightHalf = Quad(
        topLeft: const Offset(50, 0),
        topRight: const Offset(100, 0),
        bottomRight: const Offset(100, 100),
        bottomLeft: const Offset(50, 100),
      );
      final out = await PerspectiveWarp.warpImage(src, rightHalf);
      // Output width tracks the selected edge length (~50).
      expect(out.width, closeTo(50, 1));
      final centre = await pixel(out, out.width ~/ 2, out.height ~/ 2);
      expect(centre[2], greaterThan(200)); // blue
      expect(centre[0], lessThan(60)); // not red
    });

    test('output size derives from the longer opposing edge', () async {
      // A trapezoid whose bottom edge (80) is longer than the top (40).
      final q = Quad(
        topLeft: const Offset(30, 10),
        topRight: const Offset(70, 10),
        bottomRight: const Offset(90, 90),
        bottomLeft: const Offset(10, 90),
      );
      final src = await solid(100, 100, const Color(0xFF00FF00));
      final out = await PerspectiveWarp.warpImage(src, q);
      // Bottom edge is 80px; the slanted sides are sqrt(20^2 + 80^2) ≈ 82.5.
      expect(out.width, closeTo(80, 1));
      expect(out.height, closeTo(82, 1));
    });
  });

  group('ImageEnhance', () {
    test('grayscale equalises channels', () async {
      final src = await solid(8, 8, const Color(0xFF3060C0));
      final out = await ImageEnhance.apply(src, ImageEnhancement.grayscale);
      final p = await pixel(out, 4, 4);
      expect(p[0], p[1]);
      expect(p[1], p[2]);
    });

    test('none returns the same instance', () async {
      final src = await solid(4, 4, const Color(0xFF112233));
      final out = await ImageEnhance.apply(src, ImageEnhancement.none);
      expect(identical(out, src), isTrue);
    });

    test('blackAndWhite yields only 0 or 255', () async {
      final src = await twoTone(
        20,
        20,
        const Color(0xFF202020),
        const Color(0xFFE0E0E0),
      );
      final out = await ImageEnhance.apply(src, ImageEnhancement.blackAndWhite);
      final px = await rgba(out);
      for (var i = 0; i < px.length; i += 4) {
        expect(px[i] == 0 || px[i] == 255, isTrue);
      }
    });
  });

  group('FallbackEngine (file pipeline)', () {
    test('is available off-web (dart:io present under flutter test)', () {
      expect(FallbackEngine.isAvailable, isTrue);
    });

    test('warpImage reads a file and writes a cropped PNG', () async {
      final src = await solid(80, 50, const Color(0xFFFF9900));
      final path = await _writeTemp(await pngBytes(src));
      final outPath = await FallbackEngine.warpImage(
        rawImagePath: path,
        quad: fullQuad(80, 50),
      );
      expect(outPath, endsWith('.png'));
      final decoded = await _decodeFile(outPath);
      expect(decoded.width, 80);
      expect(decoded.height, 50);
    });

    test('rotateImage by one quarter turn swaps dimensions', () async {
      final src = await solid(80, 50, const Color(0xFF00AAFF));
      final path = await _writeTemp(await pngBytes(src));
      final outPath =
          await FallbackEngine.rotateImage(imagePath: path, quarterTurns: 1);
      final decoded = await _decodeFile(outPath);
      expect(decoded.width, 50);
      expect(decoded.height, 80);
    });

    test('rotateImage with 0 turns keeps dimensions', () async {
      final src = await solid(30, 20, const Color(0xFF00AAFF));
      final path = await _writeTemp(await pngBytes(src));
      final outPath =
          await FallbackEngine.rotateImage(imagePath: path, quarterTurns: 0);
      final decoded = await _decodeFile(outPath);
      expect(decoded.width, 30);
      expect(decoded.height, 20);
    });

    test('detectInImage returns image size and a null quad', () async {
      final src = await solid(64, 48, const Color(0xFF888888));
      final path = await _writeTemp(await pngBytes(src));
      final det = await FallbackEngine.detectInImage(imagePath: path);
      expect(det, isNotNull);
      expect(det!.quad, isNull);
      expect(det.imageSize, const Size(64, 48));
      // quadIn falls back to a 10% inset so the user has draggable corners.
      expect(det.quadIn.topLeft.dx, closeTo(6.4, 0.01));
    });

    test('recognizeText returns an empty (not error) result', () async {
      final res = await FallbackEngine.recognizeText(imagePath: 'ignored');
      expect(res.isEmpty, isTrue);
    });
  });

  group('capability flags', () {
    test('import flow is supported where dart:io exists', () {
      expect(DoclensPlatform.supportsImportFlow, isTrue);
    });
  });
}

// --- small file helpers (desktop VM) ---------------------------------------

Future<String> _writeTemp(Uint8List bytes) => writeTempImage(bytes, 'png');

Future<ui.Image> _decodeFile(String path) async {
  final bytes = await readFileBytes(path);
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}
