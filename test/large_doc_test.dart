import 'dart:math';
import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LargeDocEdge geometry', () {
    test('deltas grow the grid in the right direction', () {
      expect(LargeDocEdge.right.delta, const Point(1, 0));
      expect(LargeDocEdge.left.delta, const Point(-1, 0));
      expect(LargeDocEdge.bottom.delta, const Point(0, 1));
      expect(LargeDocEdge.top.delta, const Point(0, -1));
    });

    test('opposite is where the overlap ghost sits', () {
      expect(LargeDocEdge.right.opposite, LargeDocEdge.left);
      expect(LargeDocEdge.top.opposite, LargeDocEdge.bottom);
    });
  });

  group('LargeDocCanvas placement', () {
    test('root sits at origin', () {
      final c = LargeDocCanvas();
      final root = c.addRoot('root.jpg');
      expect(root.gridPos, const Point(0, 0));
      expect(c.length, 1);
    });

    test('rejects a second root', () {
      final c = LargeDocCanvas()..addRoot('a.jpg');
      expect(() => c.addRoot('b.jpg'), throwsStateError);
    });

    test('adjacent pieces step by the edge delta', () {
      final c = LargeDocCanvas();
      final root = c.addRoot('a.jpg');
      final right =
          c.addAdjacent(anchor: root, edge: LargeDocEdge.right, imagePath: 'b.jpg');
      final down =
          c.addAdjacent(anchor: root, edge: LargeDocEdge.bottom, imagePath: 'c.jpg');
      expect(right.gridPos, const Point(1, 0));
      expect(down.gridPos, const Point(0, 1));
    });

    test('rejects placing onto an occupied slot', () {
      final c = LargeDocCanvas();
      final root = c.addRoot('a.jpg');
      c.addAdjacent(anchor: root, edge: LargeDocEdge.right, imagePath: 'b.jpg');
      expect(
        () =>
            c.addAdjacent(anchor: root, edge: LargeDocEdge.right, imagePath: 'x.jpg'),
        throwsStateError,
      );
    });

    test('open edges exclude occupied neighbours', () {
      final c = LargeDocCanvas();
      final root = c.addRoot('a.jpg');
      expect(c.openEdgesOf(root), LargeDocEdge.values.toSet());
      c.addAdjacent(anchor: root, edge: LargeDocEdge.right, imagePath: 'b.jpg');
      expect(c.openEdgesOf(root), isNot(contains(LargeDocEdge.right)));
    });

    test('grid extent spans an L-shape', () {
      final c = LargeDocCanvas();
      final root = c.addRoot('a.jpg');
      final right =
          c.addAdjacent(anchor: root, edge: LargeDocEdge.right, imagePath: 'b.jpg');
      c.addAdjacent(anchor: right, edge: LargeDocEdge.bottom, imagePath: 'c.jpg');
      final ext = c.gridExtent();
      expect(ext.cols, 2);
      expect(ext.rows, 2);
    });

    test('cannot remove root while dependents exist', () {
      final c = LargeDocCanvas();
      final root = c.addRoot('a.jpg');
      c.addAdjacent(anchor: root, edge: LargeDocEdge.right, imagePath: 'b.jpg');
      expect(() => c.remove(root), throwsStateError);
    });
  });

  group('LargeDocSession flow', () {
    LargeDocSession newSession({LargeDocAligner? aligner}) => LargeDocSession(
          aligner: aligner ?? const ManualPlacementAligner(),
          merger: (_) async => 'merged.jpg',
        );

    test('root capture moves empty -> capturing -> review', () async {
      final s = newSession();
      expect(s.phase, LargeDocPhase.empty);
      s.beginRootCapture();
      expect(s.phase, LargeDocPhase.capturing);
      final outcome = await s.commitCapture('root.jpg');
      expect(outcome, LargeDocCaptureOutcome.accepted);
      expect(s.phase, LargeDocPhase.review);
      expect(s.canvas.length, 1);
    });

    test('adjacent capture records refined shift from aligner', () async {
      final s = newSession(aligner: const _FixedShiftAligner(Offset(3, -2)));
      s.beginRootCapture();
      await s.commitCapture('root.jpg');
      s.beginCapture(anchor: s.canvas.root, edge: LargeDocEdge.right);
      await s.commitCapture('right.jpg');
      final added = s.canvas.pieceAt(1, 0)!;
      expect(added.refinedShift, const Offset(3, -2));
    });

    test('low-confidence alignment parks piece for retake', () async {
      final s = newSession(aligner: const _WeakAligner());
      s.beginRootCapture();
      await s.commitCapture('root.jpg');
      s.beginCapture(anchor: s.canvas.root, edge: LargeDocEdge.right);
      final outcome = await s.commitCapture('right.jpg');
      expect(outcome, LargeDocCaptureOutcome.lowConfidence);
      expect(s.pendingPiece, isNotNull);

      s.retakePending();
      expect(s.phase, LargeDocPhase.capturing);
      expect(s.canvas.length, 1); // weak piece removed
    });

    test('keepPending accepts a weakly-aligned piece', () async {
      final s = newSession(aligner: const _WeakAligner());
      s.beginRootCapture();
      await s.commitCapture('root.jpg');
      s.beginCapture(anchor: s.canvas.root, edge: LargeDocEdge.right);
      await s.commitCapture('right.jpg');
      s.keepPending();
      expect(s.pendingPiece, isNull);
      expect(s.canvas.length, 2);
    });

    test('cancelCapture returns to the prior phase', () async {
      final s = newSession();
      s.beginRootCapture();
      s.cancelCapture();
      expect(s.phase, LargeDocPhase.empty);

      s.beginRootCapture();
      await s.commitCapture('root.jpg');
      s.beginCapture(anchor: s.canvas.root, edge: LargeDocEdge.right);
      s.cancelCapture();
      expect(s.phase, LargeDocPhase.review);
    });

    test('merge produces a result and ends in done', () async {
      final s = newSession();
      s.beginRootCapture();
      await s.commitCapture('root.jpg');
      final out = await s.merge();
      expect(out, 'merged.jpg');
      expect(s.phase, LargeDocPhase.done);
      expect(s.result, 'merged.jpg');
    });

    test('begin on a closed edge throws', () async {
      final s = newSession();
      s.beginRootCapture();
      await s.commitCapture('root.jpg');
      s.beginCapture(anchor: s.canvas.root, edge: LargeDocEdge.right);
      await s.commitCapture('right.jpg');
      expect(
        () => s.beginCapture(anchor: s.canvas.root, edge: LargeDocEdge.right),
        throwsStateError,
      );
    });
  });
}

class _FixedShiftAligner implements LargeDocAligner {
  const _FixedShiftAligner(this.shift);
  final Offset shift;
  @override
  double get confidenceFloor => 0.5;
  @override
  Future<AlignResult> align({
    required LargeDocPiece anchor,
    required LargeDocPiece newPiece,
    required LargeDocEdge edge,
  }) async =>
      AlignResult(shift: shift, confidence: 1);
}

class _WeakAligner implements LargeDocAligner {
  const _WeakAligner();
  @override
  double get confidenceFloor => 0.5;
  @override
  Future<AlignResult> align({
    required LargeDocPiece anchor,
    required LargeDocPiece newPiece,
    required LargeDocEdge edge,
  }) async =>
      const AlignResult(shift: Offset.zero, confidence: 0.1);
}
