import 'dart:math';
import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TileEdge geometry', () {
    test('deltas grow the grid in the right direction', () {
      expect(TileEdge.right.delta, const Point(1, 0));
      expect(TileEdge.left.delta, const Point(-1, 0));
      expect(TileEdge.bottom.delta, const Point(0, 1));
      expect(TileEdge.top.delta, const Point(0, -1));
    });

    test('opposite is where the overlap ghost sits', () {
      expect(TileEdge.right.opposite, TileEdge.left);
      expect(TileEdge.top.opposite, TileEdge.bottom);
    });
  });

  group('TileCanvas placement', () {
    test('root sits at origin', () {
      final c = TileCanvas();
      final root = c.addRoot('root.jpg');
      expect(root.gridPos, const Point(0, 0));
      expect(c.length, 1);
    });

    test('rejects a second root', () {
      final c = TileCanvas()..addRoot('a.jpg');
      expect(() => c.addRoot('b.jpg'), throwsStateError);
    });

    test('adjacent tiles step by the edge delta', () {
      final c = TileCanvas();
      final root = c.addRoot('a.jpg');
      final right =
          c.addAdjacent(anchor: root, edge: TileEdge.right, imagePath: 'b.jpg');
      final down =
          c.addAdjacent(anchor: root, edge: TileEdge.bottom, imagePath: 'c.jpg');
      expect(right.gridPos, const Point(1, 0));
      expect(down.gridPos, const Point(0, 1));
    });

    test('rejects placing onto an occupied slot', () {
      final c = TileCanvas();
      final root = c.addRoot('a.jpg');
      c.addAdjacent(anchor: root, edge: TileEdge.right, imagePath: 'b.jpg');
      expect(
        () =>
            c.addAdjacent(anchor: root, edge: TileEdge.right, imagePath: 'x.jpg'),
        throwsStateError,
      );
    });

    test('open edges exclude occupied neighbours', () {
      final c = TileCanvas();
      final root = c.addRoot('a.jpg');
      expect(c.openEdgesOf(root), TileEdge.values.toSet());
      c.addAdjacent(anchor: root, edge: TileEdge.right, imagePath: 'b.jpg');
      expect(c.openEdgesOf(root), isNot(contains(TileEdge.right)));
    });

    test('grid extent spans an L-shape', () {
      final c = TileCanvas();
      final root = c.addRoot('a.jpg');
      final right =
          c.addAdjacent(anchor: root, edge: TileEdge.right, imagePath: 'b.jpg');
      c.addAdjacent(anchor: right, edge: TileEdge.bottom, imagePath: 'c.jpg');
      final ext = c.gridExtent();
      expect(ext.cols, 2);
      expect(ext.rows, 2);
    });

    test('cannot remove root while dependents exist', () {
      final c = TileCanvas();
      final root = c.addRoot('a.jpg');
      c.addAdjacent(anchor: root, edge: TileEdge.right, imagePath: 'b.jpg');
      expect(() => c.remove(root), throwsStateError);
    });
  });

  group('TileScanSession flow', () {
    TileScanSession newSession({TileAligner? aligner}) => TileScanSession(
          aligner: aligner ?? const ManualPlacementAligner(),
          merger: (_) async => 'merged.jpg',
        );

    test('root capture moves empty -> capturing -> review', () async {
      final s = newSession();
      expect(s.phase, TileScanPhase.empty);
      s.beginRootCapture();
      expect(s.phase, TileScanPhase.capturing);
      final outcome = await s.commitCapture('root.jpg');
      expect(outcome, TileCaptureOutcome.accepted);
      expect(s.phase, TileScanPhase.review);
      expect(s.canvas.length, 1);
    });

    test('adjacent capture records refined shift from aligner', () async {
      final s = newSession(aligner: const _FixedShiftAligner(Offset(3, -2)));
      s.beginRootCapture();
      await s.commitCapture('root.jpg');
      s.beginCapture(anchor: s.canvas.root, edge: TileEdge.right);
      await s.commitCapture('right.jpg');
      final added = s.canvas.tileAt(1, 0)!;
      expect(added.refinedShift, const Offset(3, -2));
    });

    test('low-confidence alignment parks tile for retake', () async {
      final s = newSession(aligner: const _WeakAligner());
      s.beginRootCapture();
      await s.commitCapture('root.jpg');
      s.beginCapture(anchor: s.canvas.root, edge: TileEdge.right);
      final outcome = await s.commitCapture('right.jpg');
      expect(outcome, TileCaptureOutcome.lowConfidence);
      expect(s.pendingTile, isNotNull);

      s.retakePending();
      expect(s.phase, TileScanPhase.capturing);
      expect(s.canvas.length, 1); // weak tile removed
    });

    test('keepPending accepts a weakly-aligned tile', () async {
      final s = newSession(aligner: const _WeakAligner());
      s.beginRootCapture();
      await s.commitCapture('root.jpg');
      s.beginCapture(anchor: s.canvas.root, edge: TileEdge.right);
      await s.commitCapture('right.jpg');
      s.keepPending();
      expect(s.pendingTile, isNull);
      expect(s.canvas.length, 2);
    });

    test('cancelCapture returns to the prior phase', () async {
      final s = newSession();
      s.beginRootCapture();
      s.cancelCapture();
      expect(s.phase, TileScanPhase.empty);

      s.beginRootCapture();
      await s.commitCapture('root.jpg');
      s.beginCapture(anchor: s.canvas.root, edge: TileEdge.right);
      s.cancelCapture();
      expect(s.phase, TileScanPhase.review);
    });

    test('merge produces a result and ends in done', () async {
      final s = newSession();
      s.beginRootCapture();
      await s.commitCapture('root.jpg');
      final out = await s.merge();
      expect(out, 'merged.jpg');
      expect(s.phase, TileScanPhase.done);
      expect(s.result, 'merged.jpg');
    });

    test('begin on a closed edge throws', () async {
      final s = newSession();
      s.beginRootCapture();
      await s.commitCapture('root.jpg');
      s.beginCapture(anchor: s.canvas.root, edge: TileEdge.right);
      await s.commitCapture('right.jpg');
      expect(
        () => s.beginCapture(anchor: s.canvas.root, edge: TileEdge.right),
        throwsStateError,
      );
    });
  });
}

class _FixedShiftAligner implements TileAligner {
  const _FixedShiftAligner(this.shift);
  final Offset shift;
  @override
  double get confidenceFloor => 0.5;
  @override
  Future<AlignResult> align({
    required Tile anchor,
    required Tile newTile,
    required TileEdge edge,
  }) async =>
      AlignResult(shift: shift, confidence: 1);
}

class _WeakAligner implements TileAligner {
  const _WeakAligner();
  @override
  double get confidenceFloor => 0.5;
  @override
  Future<AlignResult> align({
    required Tile anchor,
    required Tile newTile,
    required TileEdge edge,
  }) async =>
      const AlignResult(shift: Offset.zero, confidence: 0.1);
}
