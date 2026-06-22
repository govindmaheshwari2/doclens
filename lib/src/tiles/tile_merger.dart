import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'tile_canvas.dart';

/// Stitches a finished [TileCanvas] into one image.
///
/// Step 1 ships [CanvasTileMerger], a dependency-free default that pastes
/// each tile at its grid slot (offset by [Tile.refinedShift]) using a
/// `dart:ui` canvas. There is no seam feathering yet — overlaps are drawn in
/// placement order — so a future merger can implement multiband blending and
/// content-crop behind the same `Future<String> Function(TileCanvas)`
/// signature the [TileScanSession] expects.
abstract class TileMerger {
  Future<String> merge(TileCanvas canvas);
}

/// Default merger: decode each tile, paste it at
/// `gridPos * stride * (1 - overlapFraction) + refinedShift`, encode the
/// composite to PNG in the system temp dir, and return its path.
class CanvasTileMerger implements TileMerger {
  const CanvasTileMerger({
    this.overlapFraction = 0.3,
    this.background = const ui.Color(0xFFFFFFFF),
  }) : assert(overlapFraction >= 0 && overlapFraction < 1);

  /// Fraction of a tile assumed to overlap its neighbour, used to compute
  /// the grid stride. Should match the overlap the capture ghost showed.
  final double overlapFraction;

  /// Fill behind the tiles (visible only where slots are missing, e.g. the
  /// corner of an L-shaped scan).
  final ui.Color background;

  @override
  Future<String> merge(TileCanvas canvas) async {
    if (canvas.isEmpty) {
      throw StateError('Nothing to merge.');
    }

    // Decode every tile up front so we know pixel sizes.
    final images = <int, ui.Image>{};
    for (final t in canvas.tiles) {
      images[t.id] = await _decode(t.imagePath);
    }

    // Cell stride from the largest tile so differently-sized captures still
    // tile without clipping their neighbour.
    var maxW = 0, maxH = 0;
    for (final img in images.values) {
      if (img.width > maxW) maxW = img.width;
      if (img.height > maxH) maxH = img.height;
    }
    final strideX = maxW * (1 - overlapFraction);
    final strideY = maxH * (1 - overlapFraction);

    final b = canvas.gridBounds();
    ui.Offset originOf(Tile t) => ui.Offset(
          (t.col - b.minCol) * strideX + t.refinedShift.dx,
          (t.row - b.minRow) * strideY + t.refinedShift.dy,
        );

    // Composite extent.
    double w = 0, h = 0;
    for (final t in canvas.tiles) {
      final o = originOf(t);
      final img = images[t.id]!;
      w = w < o.dx + img.width ? o.dx + img.width : w;
      h = h < o.dy + img.height ? o.dy + img.height : h;
    }
    final outW = w.ceil();
    final outH = h.ceil();

    final recorder = ui.PictureRecorder();
    final canvasUi = ui.Canvas(recorder);
    canvasUi.drawRect(
      ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      ui.Paint()..color = background,
    );
    // Draw in placement order; later tiles paint over earlier overlaps.
    for (final t in canvas.tiles) {
      canvasUi.drawImage(images[t.id]!, originOf(t), ui.Paint());
    }
    final picture = recorder.endRecording();
    final composite = await picture.toImage(outW, outH);
    final bytes =
        await composite.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    for (final img in images.values) {
      img.dispose();
    }
    composite.dispose();
    if (bytes == null) {
      throw StateError('Failed to encode the merged composite.');
    }

    final path =
        '${Directory.systemTemp.path}/doclens_tiles_${DateTime.now().microsecondsSinceEpoch}.png';
    await File(path).writeAsBytes(bytes.buffer.asUint8List());
    return path;
  }

  Future<ui.Image> _decode(String path) async {
    final data = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(
      Uint8List.fromList(data),
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
