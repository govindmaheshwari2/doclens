import 'dart:collection';
import 'dart:ui';

import 'quad.dart';

/// Sliding-window median filter over recently observed quads.
///
/// Each corner is independently median-filtered (median X, median Y) over
/// the last [windowSize] non-null observations. This kills single-frame
/// jitter without introducing the lag that an averaging filter would.
///
/// A null observation does not reset the buffer — it's treated as a
/// transient miss. Two consecutive nulls (configurable via [missesBeforeReset])
/// clear the window so a fresh quad isn't smoothed against a stale one.
class QuadSmoother {
  QuadSmoother({this.windowSize = 5, this.missesBeforeReset = 3})
      : assert(windowSize > 0 && windowSize.isOdd,
            'windowSize should be odd for a true median');

  final int windowSize;
  final int missesBeforeReset;

  final Queue<Quad> _buffer = Queue<Quad>();
  int _consecutiveMisses = 0;

  void reset() {
    _buffer.clear();
    _consecutiveMisses = 0;
  }

  /// Add [quad] (or null for a missed frame) and return the smoothed quad.
  /// Returns null when there's not yet any data to smooth.
  Quad? add(Quad? quad) {
    if (quad == null) {
      _consecutiveMisses++;
      if (_consecutiveMisses >= missesBeforeReset) reset();
      return _buffer.isEmpty ? null : _median();
    }
    _consecutiveMisses = 0;
    _buffer.addLast(quad);
    while (_buffer.length > windowSize) {
      _buffer.removeFirst();
    }
    return _median();
  }

  Quad _median() {
    final items = _buffer.toList();
    Offset medianOffset(Offset Function(Quad) pick) {
      final xs = items.map((q) => pick(q).dx).toList()..sort();
      final ys = items.map((q) => pick(q).dy).toList()..sort();
      final mid = xs.length ~/ 2;
      return Offset(xs[mid], ys[mid]);
    }

    return Quad(
      topLeft: medianOffset((q) => q.topLeft),
      topRight: medianOffset((q) => q.topRight),
      bottomRight: medianOffset((q) => q.bottomRight),
      bottomLeft: medianOffset((q) => q.bottomLeft),
    );
  }
}
