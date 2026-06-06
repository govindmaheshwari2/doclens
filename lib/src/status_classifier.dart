import 'dart:math' as math;
import 'dart:ui';

import 'models.dart';
import 'quad.dart';

/// Heuristics that derive a [DetectionStatus] from a detected quad.
///
/// All thresholds are tuned for normalized [0,1] preview coordinates.
/// Values were chosen against a corpus of ~20 real bills/receipts; see
/// `docs/tuning.md` for methodology.
class StatusClassifier {
  const StatusClassifier({
    this.minArea = 0.10,
    this.maxArea = 0.85,
    this.maxAspectSkew = 0.35,
  });

  /// Minimum quad area (normalized) before we say "too far".
  final double minArea;

  /// Maximum quad area (normalized) before we say "too close".
  final double maxArea;

  /// How far the four edges' lengths may deviate from their pair before
  /// we consider the quad "tilted" (perspective too aggressive). Computed
  /// as `|opposite_edges_ratio - 1|`.
  final double maxAspectSkew;

  /// Returns the coarse status for [quad].
  ///
  /// [noFrameYet] is true between session start and the first frame
  /// arriving. Stability is **not** part of this classifier — call
  /// [StabilityTracker] alongside if you want a "hold still" signal.
  DetectionStatus classify({
    required Quad? quad,
    bool noFrameYet = false,
  }) {
    if (noFrameYet) return DetectionStatus.searching;
    if (quad == null) return DetectionStatus.noPaper;

    final area = quad.area; // normalized 0..1
    if (area < minArea) return DetectionStatus.tooFar;
    if (area > maxArea) return DetectionStatus.tooClose;

    final tl = quad.topLeft, tr = quad.topRight;
    final br = quad.bottomRight, bl = quad.bottomLeft;
    final top = _dist(tl, tr);
    final bottom = _dist(bl, br);
    final left = _dist(tl, bl);
    final right = _dist(tr, br);
    final hSkew = (top - bottom).abs() / math.max(top, bottom);
    final vSkew = (left - right).abs() / math.max(left, right);
    if (hSkew > maxAspectSkew || vSkew > maxAspectSkew) {
      return DetectionStatus.tilted;
    }
    return DetectionStatus.aligned;
  }

  static double _dist(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return math.sqrt(dx * dx + dy * dy);
  }
}
