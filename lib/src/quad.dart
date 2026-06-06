import 'dart:math' as math;
import 'dart:ui';

/// A four-point quadrilateral.
///
/// Coordinates are platform-agnostic. In streaming context, points are
/// emitted in normalized space `[0, 1]` with origin at top-left, in
/// `topLeft → topRight → bottomRight → bottomLeft` order on both platforms.
/// After a capture, coordinates are converted to the raw image's pixel space.
class Quad {
  const Quad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  List<Offset> get points => [topLeft, topRight, bottomRight, bottomLeft];

  Offset get centroid {
    final p = points;
    final cx = p.fold<double>(0, (a, b) => a + b.dx) / 4.0;
    final cy = p.fold<double>(0, (a, b) => a + b.dy) / 4.0;
    return Offset(cx, cy);
  }

  /// Shoelace formula. Returns absolute area in whatever units the points use.
  double get area {
    final p = points;
    double sum = 0;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum.abs() / 2.0;
  }

  /// True if `point` lies inside this quad (assumes convex, which detected
  /// document quads always are).
  bool contains(Offset point) {
    int sign = 0;
    final p = points;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      final cross =
          (b.dx - a.dx) * (point.dy - a.dy) - (b.dy - a.dy) * (point.dx - a.dx);
      if (cross == 0) continue;
      final s = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (sign != s) {
        return false;
      }
    }
    return true;
  }

  /// Linearly interpolate corner-by-corner between two quads.
  static Quad interpolate(Quad a, Quad b, double t) {
    Offset lerp(Offset x, Offset y) =>
        Offset(x.dx + (y.dx - x.dx) * t, x.dy + (y.dy - x.dy) * t);
    return Quad(
      topLeft: lerp(a.topLeft, b.topLeft),
      topRight: lerp(a.topRight, b.topRight),
      bottomRight: lerp(a.bottomRight, b.bottomRight),
      bottomLeft: lerp(a.bottomLeft, b.bottomLeft),
    );
  }

  /// Convert this quad from normalized [0,1] coordinates to pixel coordinates
  /// in an image of the given [size].
  Quad scaleToSize(Size size) {
    Offset s(Offset o) => Offset(o.dx * size.width, o.dy * size.height);
    return Quad(
      topLeft: s(topLeft),
      topRight: s(topRight),
      bottomRight: s(bottomRight),
      bottomLeft: s(bottomLeft),
    );
  }

  /// Max distance from any corner to the corresponding corner of [other].
  double maxCornerDistance(Quad other) {
    double d(Offset a, Offset b) {
      final dx = a.dx - b.dx;
      final dy = a.dy - b.dy;
      return math.sqrt(dx * dx + dy * dy);
    }

    return [
      d(topLeft, other.topLeft),
      d(topRight, other.topRight),
      d(bottomRight, other.bottomRight),
      d(bottomLeft, other.bottomLeft),
    ].reduce(math.max);
  }

  Map<String, dynamic> toMap() => {
        'topLeft': [topLeft.dx, topLeft.dy],
        'topRight': [topRight.dx, topRight.dy],
        'bottomRight': [bottomRight.dx, bottomRight.dy],
        'bottomLeft': [bottomLeft.dx, bottomLeft.dy],
      };

  static Quad fromMap(Map<dynamic, dynamic> m) {
    Offset o(dynamic v) {
      final l = v as List;
      return Offset((l[0] as num).toDouble(), (l[1] as num).toDouble());
    }

    return Quad(
      topLeft: o(m['topLeft']),
      topRight: o(m['topRight']),
      bottomRight: o(m['bottomRight']),
      bottomLeft: o(m['bottomLeft']),
    );
  }

  @override
  String toString() =>
      'Quad(TL=$topLeft, TR=$topRight, BR=$bottomRight, BL=$bottomLeft)';

  @override
  bool operator ==(Object other) =>
      other is Quad &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);
}
