import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'tile_aligner.dart';
import 'tile_canvas.dart';

/// Where a [TileScanSession] is in the capture → review → merge loop.
enum TileScanPhase {
  /// No tiles yet — waiting for the first (root) capture.
  empty,

  /// At least one tile placed; showing the composite with `+` affordances on
  /// the open edges.
  review,

  /// The camera is open for a tile growing in [TileScanSession.pendingEdge]
  /// off [TileScanSession.pendingAnchor]; the overlap ghost is shown.
  capturing,

  /// All tiles captured; the composite is being stitched into one image.
  merging,

  /// Merge finished; [TileScanSession.result] holds the output.
  done,
}

/// What happened to the most recent capture's alignment — drives whether the
/// UI silently accepts, or surfaces a retake/keep choice.
enum TileCaptureOutcome {
  /// Aligned with confidence at or above the aligner's floor; accepted.
  accepted,

  /// Aligned below the floor (e.g. featureless overlap). The tile is held as
  /// [TileScanSession.pendingTile]; the caller should prompt retake/keep.
  lowConfidence,
}

/// Orchestrates a multi-tile ("can't fit in one shot") scan.
///
/// The session owns the [TileCanvas] and a [TileAligner] and exposes the
/// discrete steps the UI drives: tap a `+` ([beginCapture]) → shoot
/// ([commitCapture], which runs the aligner) → accept or [retakePending] →
/// [merge]. It is a [ChangeNotifier] so a widget can rebuild on phase
/// changes, but holds no camera or image-codec state itself; capture and the
/// final stitch are injected, keeping the state machine unit-testable.
class TileScanSession extends ChangeNotifier {
  TileScanSession({
    TileAligner aligner = const ManualPlacementAligner(),
    required this.merger,
  }) : _aligner = aligner;

  final TileAligner _aligner;

  /// Stitches the finished canvas into a single output path. Injected so the
  /// (native / image-codec) compositing lives outside this state machine.
  final Future<String> Function(TileCanvas canvas) merger;

  final TileCanvas canvas = TileCanvas();

  TileScanPhase _phase = TileScanPhase.empty;
  TileScanPhase get phase => _phase;

  Tile? _pendingAnchor;
  TileEdge? _pendingEdge;
  Tile? _pendingTile;
  TileCaptureOutcome? _lastOutcome;
  String? _result;

  /// The anchor tile the in-flight capture grows from (null in [empty]).
  Tile? get pendingAnchor => _pendingAnchor;

  /// The direction the in-flight capture extends the composite.
  TileEdge? get pendingEdge => _pendingEdge;

  /// A just-captured tile awaiting accept/retake when alignment was weak.
  Tile? get pendingTile => _pendingTile;

  TileCaptureOutcome? get lastOutcome => _lastOutcome;

  /// Output path once [phase] is [TileScanPhase.done].
  String? get result => _result;

  /// Opens capture for the root (first) tile.
  void beginRootCapture() {
    _requirePhase(TileScanPhase.empty);
    _pendingAnchor = null;
    _pendingEdge = null;
    _setPhase(TileScanPhase.capturing);
  }

  /// Opens capture for a tile growing off [edge] of [anchor]. The UI shows
  /// the overlap ghost on `edge.opposite` of the live preview.
  void beginCapture({required Tile anchor, required TileEdge edge}) {
    _requirePhase(TileScanPhase.review);
    if (!canvas.openEdgesOf(anchor).contains(edge)) {
      throw StateError('Edge $edge of tile #${anchor.id} is not open.');
    }
    _pendingAnchor = anchor;
    _pendingEdge = edge;
    _setPhase(TileScanPhase.capturing);
  }

  /// Records a captured fragment at [imagePath]. Places it on the grid, runs
  /// the aligner against its anchor, and returns the outcome. On
  /// [TileCaptureOutcome.lowConfidence] the tile is retained as
  /// [pendingTile] so the caller can offer retake/keep before continuing.
  Future<TileCaptureOutcome> commitCapture(String imagePath) async {
    _requirePhase(TileScanPhase.capturing);

    final Tile tile;
    final AlignResult align;
    if (_pendingAnchor == null) {
      // Root tile: nothing to align against.
      tile = canvas.addRoot(imagePath);
      align = const AlignResult(shift: Offset.zero, confidence: 1);
    } else {
      final anchor = _pendingAnchor!;
      final edge = _pendingEdge!;
      // Place first so the aligner sees the real grid relationship, then
      // fold the refined shift back in.
      tile = canvas.addAdjacent(
        anchor: anchor,
        edge: edge,
        imagePath: imagePath,
      );
      align = await _aligner.align(anchor: anchor, newTile: tile, edge: edge);
      tile.refinedShift = align.shift;
    }

    final ok = align.confidence >= _aligner.confidenceFloor;
    _lastOutcome =
        ok ? TileCaptureOutcome.accepted : TileCaptureOutcome.lowConfidence;
    _pendingTile = ok ? null : tile;
    if (ok) _clearPending();
    _setPhase(TileScanPhase.review);
    return _lastOutcome!;
  }

  /// Keeps a [pendingTile] despite weak alignment (trusts manual placement).
  void keepPending() {
    if (_pendingTile == null) return;
    _pendingTile = null;
    _clearPending();
    notifyListeners();
  }

  /// Discards a [pendingTile] and reopens capture for the same edge so the
  /// user can re-shoot just that fragment.
  void retakePending() {
    final tile = _pendingTile;
    if (tile == null) return;
    final anchor = _pendingAnchor;
    final edge = _pendingEdge;
    canvas.remove(tile);
    _pendingTile = null;
    if (anchor == null || edge == null) {
      _setPhase(TileScanPhase.empty);
      beginRootCapture();
    } else {
      _setPhase(TileScanPhase.review);
      beginCapture(anchor: anchor, edge: edge);
    }
  }

  /// Aborts the in-flight capture without adding a tile.
  void cancelCapture() {
    _requirePhase(TileScanPhase.capturing);
    _clearPending();
    _setPhase(canvas.isEmpty ? TileScanPhase.empty : TileScanPhase.review);
  }

  /// Stitches the canvas into one image and transitions to [done].
  Future<String> merge() async {
    _requirePhase(TileScanPhase.review);
    if (canvas.isEmpty) {
      throw StateError('Nothing to merge.');
    }
    _setPhase(TileScanPhase.merging);
    try {
      _result = await merger(canvas);
      _setPhase(TileScanPhase.done);
      return _result!;
    } catch (_) {
      // Leave the user back in review with their tiles intact.
      _setPhase(TileScanPhase.review);
      rethrow;
    }
  }

  void _clearPending() {
    _pendingAnchor = null;
    _pendingEdge = null;
  }

  void _setPhase(TileScanPhase p) {
    _phase = p;
    notifyListeners();
  }

  void _requirePhase(TileScanPhase expected) {
    if (_phase != expected) {
      throw StateError('Expected phase $expected but was $_phase.');
    }
  }
}
