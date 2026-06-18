import 'dart:collection';

/// Decides whether the live frame is "in focus" from a stream of raw
/// variance-of-Laplacian sharpness values.
///
/// Variance-of-Laplacian is scene- and scale-dependent, so a fixed absolute
/// threshold is brittle. We instead require a frame to be both above an
/// absolute [floor] AND near the top of a short rolling window — i.e. the
/// autofocus has improved sharpness and it has plateaued.
class SharpnessTracker {
  SharpnessTracker({required this.floor, this.windowSize = 12});

  final double floor;
  final int windowSize;

  /// Fraction of the recent window max a frame must reach to count as
  /// "plateaued at the top".
  static const double _plateauRatio = 0.85;

  /// Minimum samples before a "ready" verdict — avoids declaring focus on
  /// the very first sharp-by-accident frame mid-hunt.
  static const int _minSamples = 3;

  final Queue<double> _window = Queue<double>();

  void reset() => _window.clear();

  bool update(double? sharpness) {
    // No signal from native -> degrade to "ready" so we never block capture.
    if (sharpness == null) return true;

    _window.addLast(sharpness);
    while (_window.length > windowSize) {
      _window.removeFirst();
    }

    if (sharpness < floor) return false;
    if (_window.length < _minSamples) return false;

    final recentMax = _window.fold<double>(0, (m, v) => v > m ? v : m);
    if (recentMax <= 0) return false;
    return sharpness >= _plateauRatio * recentMax;
  }
}
