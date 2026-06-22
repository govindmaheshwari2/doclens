import 'dart:io';

import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';

// =====================================================================
//  Customised large-document tile scanner.
//
//  A reference for "you own the UI" on the multi-shot capture flow:
//  capture a document too big for one frame as overlapping tiles, then
//  stitch them into a single image. Every piece of chrome below is a
//  builder passed to `TileScanScreen` — swap the colours and widgets and
//  the capture / alignment / stitch pipeline stays exactly the same.
//
//  What's customised here:
//    - Branded `+` affordance with an arrow pointing the way to grow
//    - Mono-caps coaching hint pill
//    - Framed "PAGE MAP" miniview of the composite so far
// =====================================================================

const _violet = Color(0xFF6C5CE7);
const _violetSoft = Color(0xFFA29BFE);
const _ink = Color(0xFF12101A);

/// Pushable demo screen, mirroring `BrandedStyleScanner`. Returns the
/// stitched image path via [Navigator.pop] when the user taps Done.
class LargeDocScanner extends StatelessWidget {
  const LargeDocScanner({super.key});

  @override
  Widget build(BuildContext context) {
    return TileScanScreen(
      accentColor: _violet,
      title: 'Tile a large document',
      plusButtonBuilder: _plus,
      hintBuilder: _hint,
      miniviewBuilder: _miniview,
    );
  }

  static IconData _arrowFor(TileEdge edge) => switch (edge) {
        TileEdge.left => Icons.arrow_back,
        TileEdge.right => Icons.arrow_forward,
        TileEdge.top => Icons.arrow_upward,
        TileEdge.bottom => Icons.arrow_downward,
      };

  static Widget _plus(BuildContext context, TileEdge edge, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_violet, _violetSoft]),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 8)],
        ),
        child: Icon(_arrowFor(edge), color: Colors.white, size: 22),
      ),
    );
  }

  static Widget _hint(BuildContext context, TileEdge? edge) {
    final text = edge == null
        ? 'CAPTURE THE FIRST PIECE'
        : 'LINE UP WITH THE GHOST · THEN CAPTURE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _ink.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _violetSoft.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static Widget _miniview(BuildContext context, TileCanvas canvas) {
    if (canvas.isEmpty) return const SizedBox.shrink();
    final b = canvas.gridBounds();
    final ext = canvas.gridExtent();
    const maxSide = 84.0;
    final cell = maxSide / (ext.cols > ext.rows ? ext.cols : ext.rows);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _ink.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _violet),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 4, left: 1),
            child: Text(
              'PAGE MAP',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 8,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: ext.cols * cell,
            height: ext.rows * cell,
            child: Stack(
              children: [
                for (final t in canvas.tiles)
                  Positioned(
                    left: (t.col - b.minCol) * cell,
                    top: (t.row - b.minRow) * cell,
                    width: cell,
                    height: cell,
                    child: Padding(
                      padding: const EdgeInsets.all(0.5),
                      child: Image.file(File(t.imagePath), fit: BoxFit.cover),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
