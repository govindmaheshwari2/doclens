import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'large_doc_aligner.dart';
import 'large_doc_canvas.dart';

/// Where a [LargeDocSession] is in the capture → review → merge loop.
enum LargeDocPhase {
  /// No pieces yet — waiting for the first (root) capture.
  empty,

  /// At least one piece placed; showing the composite with `+` affordances on
  /// the open edges.
  review,

  /// The camera is open for a piece growing in [LargeDocSession.pendingEdge]
  /// off [LargeDocSession.pendingAnchor]; the overlap ghost is shown.
  capturing,

  /// All pieces captured; the composite is being stitched into one image.
  merging,

  /// Merge finished; [LargeDocSession.result] holds the output.
  done,
}

/// What happened to the most recent capture's alignment — drives whether the
/// UI silently accepts, or surfaces a retake/keep choice.
enum LargeDocCaptureOutcome {
  /// Aligned with confidence at or above the aligner's floor; accepted.
  accepted,

  /// Aligned below the floor (e.g. featureless overlap). The piece is held as
  /// [LargeDocSession.pendingPiece]; the caller should prompt retake/keep.
  lowConfidence,
}

/// Orchestrates a multi-piece ("can't fit in one shot") scan.
///
/// The session owns the [LargeDocCanvas] and a [LargeDocAligner] and exposes the
/// discrete steps the UI drives: tap a `+` ([beginCapture]) → shoot
/// ([commitCapture], which runs the aligner) → accept or [retakePending] →
/// [merge]. It is a [ChangeNotifier] so a widget can rebuild on phase
/// changes, but holds no camera or image-codec state itself; capture and the
/// final stitch are injected, keeping the state machine unit-testable.
class LargeDocSession extends ChangeNotifier {
  LargeDocSession({
    LargeDocAligner aligner = const ManualPlacementAligner(),
    required this.merger,
  }) : _aligner = aligner;

  final LargeDocAligner _aligner;

  /// Stitches the finished canvas into a single output path. Injected so the
  /// (native / image-codec) compositing lives outside this state machine.
  final Future<String> Function(LargeDocCanvas canvas) merger;

  final LargeDocCanvas canvas = LargeDocCanvas();

  LargeDocPhase _phase = LargeDocPhase.empty;
  LargeDocPhase get phase => _phase;

  LargeDocPiece? _pendingAnchor;
  LargeDocEdge? _pendingEdge;
  LargeDocPiece? _pendingTile;
  LargeDocCaptureOutcome? _lastOutcome;
  String? _result;

  /// The anchor piece the in-flight capture grows from (null in [empty]).
  LargeDocPiece? get pendingAnchor => _pendingAnchor;

  /// The direction the in-flight capture extends the composite.
  LargeDocEdge? get pendingEdge => _pendingEdge;

  /// A just-captured piece awaiting accept/retake when alignment was weak.
  LargeDocPiece? get pendingPiece => _pendingTile;

  LargeDocCaptureOutcome? get lastOutcome => _lastOutcome;

  /// Output path once [phase] is [LargeDocPhase.done].
  String? get result => _result;

  /// Opens capture for the root (first) piece.
  void beginRootCapture() {
    _requirePhase(LargeDocPhase.empty);
    _pendingAnchor = null;
    _pendingEdge = null;
    _setPhase(LargeDocPhase.capturing);
  }

  /// Opens capture for a piece growing off [edge] of [anchor]. The UI shows
  /// the overlap ghost on `edge.opposite` of the live preview.
  void beginCapture({required LargeDocPiece anchor, required LargeDocEdge edge}) {
    _requirePhase(LargeDocPhase.review);
    if (!canvas.openEdgesOf(anchor).contains(edge)) {
      throw StateError('Edge $edge of piece #${anchor.id} is not open.');
    }
    _pendingAnchor = anchor;
    _pendingEdge = edge;
    _setPhase(LargeDocPhase.capturing);
  }

  /// Records a captured fragment at [imagePath]. Places it on the grid, runs
  /// the aligner against its anchor, and returns the outcome. On
  /// [LargeDocCaptureOutcome.lowConfidence] the piece is retained as
  /// [pendingPiece] so the caller can offer retake/keep before continuing.
  Future<LargeDocCaptureOutcome> commitCapture(String imagePath) async {
    _requirePhase(LargeDocPhase.capturing);

    final LargeDocPiece piece;
    final AlignResult align;
    if (_pendingAnchor == null) {
      // Root piece: nothing to align against.
      piece = canvas.addRoot(imagePath);
      align = const AlignResult(shift: Offset.zero, confidence: 1);
    } else {
      final anchor = _pendingAnchor!;
      final edge = _pendingEdge!;
      // Place first so the aligner sees the real grid relationship, then
      // fold the refined shift back in.
      piece = canvas.addAdjacent(
        anchor: anchor,
        edge: edge,
        imagePath: imagePath,
      );
      align = await _aligner.align(anchor: anchor, newPiece: piece, edge: edge);
      piece.refinedShift = align.shift;
    }

    final ok = align.confidence >= _aligner.confidenceFloor;
    _lastOutcome =
        ok ? LargeDocCaptureOutcome.accepted : LargeDocCaptureOutcome.lowConfidence;
    _pendingTile = ok ? null : piece;
    if (ok) _clearPending();
    _setPhase(LargeDocPhase.review);
    return _lastOutcome!;
  }

  /// Keeps a [pendingPiece] despite weak alignment (trusts manual placement).
  void keepPending() {
    if (_pendingTile == null) return;
    _pendingTile = null;
    _clearPending();
    notifyListeners();
  }

  /// Discards a [pendingPiece] and reopens capture for the same edge so the
  /// user can re-shoot just that fragment.
  void retakePending() {
    final piece = _pendingTile;
    if (piece == null) return;
    final anchor = _pendingAnchor;
    final edge = _pendingEdge;
    canvas.remove(piece);
    _pendingTile = null;
    if (anchor == null || edge == null) {
      _setPhase(LargeDocPhase.empty);
      beginRootCapture();
    } else {
      _setPhase(LargeDocPhase.review);
      beginCapture(anchor: anchor, edge: edge);
    }
  }

  /// Aborts the in-flight capture without adding a piece.
  void cancelCapture() {
    _requirePhase(LargeDocPhase.capturing);
    _clearPending();
    _setPhase(canvas.isEmpty ? LargeDocPhase.empty : LargeDocPhase.review);
  }

  /// Stitches the canvas into one image and transitions to [done].
  Future<String> merge() async {
    _requirePhase(LargeDocPhase.review);
    if (canvas.isEmpty) {
      throw StateError('Nothing to merge.');
    }
    _setPhase(LargeDocPhase.merging);
    try {
      _result = await merger(canvas);
      _setPhase(LargeDocPhase.done);
      return _result!;
    } catch (_) {
      // Leave the user back in review with their pieces intact.
      _setPhase(LargeDocPhase.review);
      rethrow;
    }
  }

  void _clearPending() {
    _pendingAnchor = null;
    _pendingEdge = null;
  }

  void _setPhase(LargeDocPhase p) {
    _phase = p;
    notifyListeners();
  }

  void _requirePhase(LargeDocPhase expected) {
    if (_phase != expected) {
      throw StateError('Expected phase $expected but was $_phase.');
    }
  }
}
