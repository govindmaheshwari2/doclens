import 'dart:ui';

import 'tile_canvas.dart';

/// Result of fine-aligning a freshly captured tile against its anchor.
class AlignResult {
  const AlignResult({
    required this.shift,
    required this.confidence,
  });

  /// Pixel translation to apply to the new tile (on top of its grid slot) so
  /// the overlap band matches the anchor.
  final Offset shift;

  /// `0..1` quality of the match. Low values mean the overlap band had too
  /// little texture to register (e.g. it fell on a blank page margin) — the
  /// caller should offer a retake or fall back to manual placement.
  final double confidence;

  /// Whether the match cleared [TileAligner.confidenceFloor]. Set by
  /// [TileAligner.align]; see [AlignResult.ok] usage in the session.
  bool get hasShift => shift != Offset.zero;

  static const none = AlignResult(shift: Offset.zero, confidence: 0);
}

/// Computes the fine pixel correction between two adjacent tiles.
///
/// Because the user coarsely lines up each capture by hand against an overlap
/// ghost, an aligner only ever needs to refine a small, mostly-pre-registered
/// band — a bounded, run-once-per-tile problem, not per-frame tracking.
///
/// Step 1 of the feature ships [ManualPlacementAligner], which trusts the
/// hand placement and applies no correction. A phase-correlation / ORB
/// implementation can be dropped in later without touching the session or UI.
abstract class TileAligner {
  /// Matches above this confidence are treated as trustworthy.
  double get confidenceFloor;

  /// Aligns [newTile] against [anchor], knowing the composite was grown
  /// toward [edge] (so the overlap sits on `edge.opposite` of [newTile]).
  Future<AlignResult> align({
    required Tile anchor,
    required Tile newTile,
    required TileEdge edge,
  });
}

/// Default aligner: no computer vision. Trusts the user's manual alignment
/// against the overlap ghost and reports a confident zero-shift result.
///
/// This makes the whole tile-scan flow usable end-to-end with naive
/// paste-at-grid compositing, which is exactly what step 1 needs to validate
/// the `+`/ghost/miniview interaction before any CV is written.
class ManualPlacementAligner implements TileAligner {
  const ManualPlacementAligner();

  @override
  double get confidenceFloor => 0;

  @override
  Future<AlignResult> align({
    required Tile anchor,
    required Tile newTile,
    required TileEdge edge,
  }) async =>
      const AlignResult(shift: Offset.zero, confidence: 1);
}
