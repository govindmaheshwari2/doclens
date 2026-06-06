import 'quad.dart';

/// Tracks how stable a stream of detected quads is over time.
///
/// A quad is "stable" when the maximum per-corner movement between
/// consecutive frames stays below [cornerThreshold] for at least
/// [stabilityDuration]. [cornerThreshold] is in **the same units as the
/// incoming quad coordinates** — for the streaming detection pipeline
/// that's normalized `[0, 1]`, so `0.02` means "no corner moved more
/// than 2% of the frame."
class StabilityTracker {
  StabilityTracker({
    required this.cornerThreshold,
    required this.stabilityDuration,
  });

  final double cornerThreshold;
  final Duration stabilityDuration;

  Quad? _lastQuad;
  DateTime? _stableSince;

  /// Reset internal state — call when detection is lost.
  void reset() {
    _lastQuad = null;
    _stableSince = null;
  }

  /// Update with a freshly detected quad. Returns true if the quad has been
  /// stable for at least [stabilityDuration].
  bool update(Quad? quad, {DateTime? now}) {
    now ??= DateTime.now();
    if (quad == null) {
      reset();
      return false;
    }
    final last = _lastQuad;
    _lastQuad = quad;
    if (last == null) {
      _stableSince = now;
      return false;
    }
    final movement = quad.maxCornerDistance(last);
    if (movement > cornerThreshold) {
      _stableSince = now;
      return false;
    }
    final since = _stableSince ??= now;
    return now.difference(since) >= stabilityDuration;
  }
}
