import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

var _seq = 0;

/// Writes a solid-colour PNG of [w]x[h] to a temp file and returns its path.
Future<String> _png(int w, int h, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = color,
  );
  final img = await recorder.endRecording().toImage(w, h);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  final path =
      '${Directory.systemTemp.path}/doclens_test_${DateTime.now().microsecondsSinceEpoch}_${_seq++}.png';
  await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  return path;
}

Future<ui.Image> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(
    Uint8List.fromList(await File(path).readAsBytes()),
  );
  return (await codec.getNextFrame()).image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const merger = CanvasTileMerger(overlapFraction: 0.3);

  test('single tile merges to an image of the same size', () async {
    final canvas = TileCanvas()..addRoot(await _png(100, 60, const ui.Color(0xFFFF0000)));
    final out = await merger.merge(canvas);
    expect(File(out).existsSync(), isTrue);
    final img = await _decode(out);
    expect(img.width, 100);
    expect(img.height, 60);
  });

  test('two tiles in a row span one stride wider than a single tile', () async {
    final c = TileCanvas();
    final root = c.addRoot(await _png(100, 60, const ui.Color(0xFFFF0000)));
    c.addAdjacent(
      anchor: root,
      edge: TileEdge.right,
      imagePath: await _png(100, 60, const ui.Color(0xFF00FF00)),
    );
    final out = await merger.merge(c);
    final img = await _decode(out);
    // stride = 100 * (1 - 0.3) = 70; composite = 70 + 100 = 170 wide.
    expect(img.width, 170);
    expect(img.height, 60);
  });

  test('negative refined shift is not clipped off-canvas', () async {
    final c = TileCanvas();
    final root = c.addRoot(await _png(100, 60, const ui.Color(0xFFFF0000)));
    // Nudge the second tile up by 10px; the composite must grow to include it
    // rather than clipping at y=0.
    c.addAdjacent(
      anchor: root,
      edge: TileEdge.right,
      imagePath: await _png(100, 60, const ui.Color(0xFF00FF00)),
      refinedShift: const ui.Offset(0, -10),
    );
    final out = await merger.merge(c);
    final img = await _decode(out);
    expect(img.height, 70); // 60 + 10 of upward overhang
  });
}
