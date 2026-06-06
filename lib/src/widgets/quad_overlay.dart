import 'package:flutter/widgets.dart';

import '../models.dart';
import '../quad.dart';

/// Visual family of quad-overlay widgets you can pass to
/// [DoclensView]'s `overlayBuilder` slot. Each constructor renders the
/// detected document quad in a different visual idiom but shares the
/// same status-driven colour behaviour:
///
///  - `aligned` / `confirming` → [accent] (brighter on `confirming`)
///  - `tilted` / `tooClose` / `tooFar` → [warning]
///  - `searching` / `noPaper` → muted white
///
/// All variants:
///  - render nothing when [quad] is `null`
///  - assume [quad] is in normalised `[0, 1]` space and scale to the
///    widget's size internally
///  - are pure `CustomPaint` so they're cheap to repaint every frame
///
/// Example usage in a [DoclensView]:
///
/// ```dart
/// DoclensView(
///   controller: controller,
///   overlayBuilder: (ctx, quad, status) =>
///       QuadOverlay.corners(quad: quad, status: status, accent: Colors.lime),
/// );
/// ```
class QuadOverlay extends StatelessWidget {
  /// Just a stroked polygon — the lightest possible overlay. Use when
  /// you want the user's eye to stay on the document, not on the chrome.
  const QuadOverlay.outline({
    super.key,
    required this.quad,
    required this.status,
    this.accent = const Color(0xFFD4FF4D),
    this.warning = const Color(0xFFFFB454),
    this.strokeWidth = 2.0,
  })  : _style = _QuadStyle.outline,
        bracketLength = 0,
        dotRadius = 0;

  /// Stroked polygon with a faint tint inside the quad. The default
  /// shipped by `DoclensView.defaultOverlayBuilder`. Good general-purpose
  /// choice when nothing more specific is wanted.
  const QuadOverlay.filled({
    super.key,
    required this.quad,
    required this.status,
    this.accent = const Color(0xFFD4FF4D),
    this.warning = const Color(0xFFFFB454),
    this.strokeWidth = 2.5,
  })  : _style = _QuadStyle.filled,
        bracketLength = 0,
        dotRadius = 0;

  /// Four corner brackets, no connecting lines. The viewfinder / CamScanner
  /// look — gives the user a clear "frame the document inside these"
  /// affordance without occluding what's in the middle.
  const QuadOverlay.corners({
    super.key,
    required this.quad,
    required this.status,
    this.accent = const Color(0xFFD4FF4D),
    this.warning = const Color(0xFFFFB454),
    this.strokeWidth = 3.0,
    this.bracketLength = 28.0,
  })  : _style = _QuadStyle.corners,
        dotRadius = 0;

  /// Corner brackets PLUS the tinted fill polygon between them — combines
  /// the "frame it" affordance with a visible quad area, so the user can
  /// see both what's recognised and the focus points.
  const QuadOverlay.cornersFilled({
    super.key,
    required this.quad,
    required this.status,
    this.accent = const Color(0xFFD4FF4D),
    this.warning = const Color(0xFFFFB454),
    this.strokeWidth = 3.0,
    this.bracketLength = 28.0,
  })  : _style = _QuadStyle.cornersFilled,
        dotRadius = 0;

  /// Just four filled dots at the corners — the minimal "we found you"
  /// signal. Pairs well with apps that already draw their own framing
  /// chrome elsewhere on screen.
  const QuadOverlay.dots({
    super.key,
    required this.quad,
    required this.status,
    this.accent = const Color(0xFFD4FF4D),
    this.warning = const Color(0xFFFFB454),
    this.dotRadius = 5.0,
  })  : _style = _QuadStyle.dots,
        strokeWidth = 0,
        bracketLength = 0;

  /// Four corner dots connected by a hairline polygon — a delicate
  /// "instrument" feel. The hairline reads as a measurement, the dots
  /// as anchor points.
  const QuadOverlay.dotsLine({
    super.key,
    required this.quad,
    required this.status,
    this.accent = const Color(0xFFD4FF4D),
    this.warning = const Color(0xFFFFB454),
    this.strokeWidth = 1.0,
    this.dotRadius = 4.5,
  })  : _style = _QuadStyle.dotsLine,
        bracketLength = 0;

  /// Blurred halo around the detected polygon — distinctive "branded"
  /// look. Use sparingly; the blur is more GPU-expensive than the other
  /// variants and can feel busy in cluttered scenes.
  const QuadOverlay.glow({
    super.key,
    required this.quad,
    required this.status,
    this.accent = const Color(0xFFD4FF4D),
    this.warning = const Color(0xFFFFB454),
    this.strokeWidth = 2.0,
  })  : _style = _QuadStyle.glow,
        bracketLength = 0,
        dotRadius = 0;

  /// The currently detected quad in normalised `[0, 1]` widget space.
  /// `null` renders nothing.
  final Quad? quad;

  /// Current detection status. Drives the overlay colour via [accent] /
  /// [warning].
  final DetectionStatus status;

  /// Colour used when the quad is `aligned` or `confirming`.
  final Color accent;

  /// Colour used when the quad is `tilted`, `tooClose`, or `tooFar`.
  final Color warning;

  /// Stroke width for the outline / connecting line.
  final double strokeWidth;

  /// Length of each corner bracket in pixels (where the style draws
  /// brackets).
  final double bracketLength;

  /// Radius of each corner dot in pixels (where the style draws dots).
  final double dotRadius;

  final _QuadStyle _style;

  Color get _resolvedColor {
    switch (status) {
      case DetectionStatus.confirming:
        return accent;
      case DetectionStatus.aligned:
        return accent.withValues(alpha: 0.95);
      case DetectionStatus.tilted:
      case DetectionStatus.tooClose:
      case DetectionStatus.tooFar:
        return warning;
      case DetectionStatus.searching:
      case DetectionStatus.noPaper:
        return const Color(0x99FFFFFF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _QuadOverlayPainter(
        quad: quad,
        color: _resolvedColor,
        style: _style,
        status: status,
        strokeWidth: strokeWidth,
        bracketLength: bracketLength,
        dotRadius: dotRadius,
      ),
    );
  }
}

/// Visual style for [QuadOverlay]. Use with [DoclensScreen.overlayStyle]
/// to switch the drop-in scanner's overlay without writing a builder.
enum QuadOverlayStyle {
  /// Just a stroked polygon. Lightest visual footprint.
  outline,

  /// Stroked polygon + tinted fill. The package default.
  filled,

  /// Four corner brackets only.
  corners,

  /// Four corner brackets + tinted fill polygon between them.
  cornersFilled,

  /// Four filled dots at the corners.
  dots,

  /// Four corner dots + hairline polygon between them.
  dotsLine,

  /// Blurred halo + stroked polygon.
  glow,
}

enum _QuadStyle { outline, filled, corners, cornersFilled, dots, dotsLine, glow }

class _QuadOverlayPainter extends CustomPainter {
  _QuadOverlayPainter({
    required this.quad,
    required this.color,
    required this.style,
    required this.status,
    required this.strokeWidth,
    required this.bracketLength,
    required this.dotRadius,
  });

  final Quad? quad;
  final Color color;
  final _QuadStyle style;
  final DetectionStatus status;
  final double strokeWidth;
  final double bracketLength;
  final double dotRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final q = quad;
    if (q == null) return;
    final scaled = q.scaleToSize(size);
    final path = _buildQuadPath(scaled);

    switch (style) {
      case _QuadStyle.outline:
        _strokePath(canvas, path);
        break;
      case _QuadStyle.filled:
        _fillPath(canvas, path, alpha: 0.12);
        _strokePath(canvas, path);
        break;
      case _QuadStyle.corners:
        _paintCornerBrackets(canvas, scaled);
        break;
      case _QuadStyle.cornersFilled:
        _fillPath(canvas, path, alpha: 0.10);
        _paintCornerBrackets(canvas, scaled);
        break;
      case _QuadStyle.dots:
        _paintCornerDots(canvas, scaled);
        break;
      case _QuadStyle.dotsLine:
        _strokePath(canvas, path, alpha: 0.65);
        _paintCornerDots(canvas, scaled);
        break;
      case _QuadStyle.glow:
        _paintGlow(canvas, path);
        _strokePath(canvas, path);
        break;
    }
  }

  Path _buildQuadPath(Quad q) => Path()
    ..moveTo(q.topLeft.dx, q.topLeft.dy)
    ..lineTo(q.topRight.dx, q.topRight.dy)
    ..lineTo(q.bottomRight.dx, q.bottomRight.dy)
    ..lineTo(q.bottomLeft.dx, q.bottomLeft.dy)
    ..close();

  void _fillPath(Canvas canvas, Path path, {required double alpha}) {
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: alpha));
  }

  void _strokePath(Canvas canvas, Path path, {double alpha = 1.0}) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintCornerBrackets(Canvas canvas, Quad q) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = status == DetectionStatus.confirming
          ? strokeWidth + 0.6
          : strokeWidth
      ..strokeCap = StrokeCap.round;
    final corners = [q.topLeft, q.topRight, q.bottomRight, q.bottomLeft];
    final neighbours = [
      [q.topRight, q.bottomLeft],
      [q.topLeft, q.bottomRight],
      [q.topRight, q.bottomLeft],
      [q.bottomRight, q.topLeft],
    ];
    for (var i = 0; i < 4; i++) {
      final c = corners[i];
      for (final n in neighbours[i]) {
        final delta = n - c;
        final mag = delta.distance;
        if (mag < 0.001) continue;
        final unit = Offset(delta.dx / mag, delta.dy / mag);
        canvas.drawLine(c, c + unit * bracketLength, paint);
      }
    }
  }

  void _paintCornerDots(Canvas canvas, Quad q) {
    final fill = Paint()..color = color;
    final corners = [q.topLeft, q.topRight, q.bottomRight, q.bottomLeft];
    for (final c in corners) {
      canvas.drawCircle(c, dotRadius, fill);
    }
  }

  void _paintGlow(Canvas canvas, Path path) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    // Inner tint so the centre isn't entirely empty.
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.06));
  }

  @override
  bool shouldRepaint(covariant _QuadOverlayPainter old) =>
      old.quad != quad ||
      old.color != color ||
      old.style != style ||
      old.status != status ||
      old.strokeWidth != strokeWidth ||
      old.bracketLength != bracketLength ||
      old.dotRadius != dotRadius;
}

/// Internal helper used by [DoclensScreen] to materialise a
/// [QuadOverlayStyle] into the matching [QuadOverlay] constructor.
/// Public so consumers can use the same mapping when building their own
/// builder wrapper around the style enum.
QuadOverlay quadOverlayFor({
  required QuadOverlayStyle style,
  required Quad? quad,
  required DetectionStatus status,
  Color accent = const Color(0xFFD4FF4D),
  Color warning = const Color(0xFFFFB454),
}) {
  switch (style) {
    case QuadOverlayStyle.outline:
      return QuadOverlay.outline(
          quad: quad, status: status, accent: accent, warning: warning);
    case QuadOverlayStyle.filled:
      return QuadOverlay.filled(
          quad: quad, status: status, accent: accent, warning: warning);
    case QuadOverlayStyle.corners:
      return QuadOverlay.corners(
          quad: quad, status: status, accent: accent, warning: warning);
    case QuadOverlayStyle.cornersFilled:
      return QuadOverlay.cornersFilled(
          quad: quad, status: status, accent: accent, warning: warning);
    case QuadOverlayStyle.dots:
      return QuadOverlay.dots(
          quad: quad, status: status, accent: accent, warning: warning);
    case QuadOverlayStyle.dotsLine:
      return QuadOverlay.dotsLine(
          quad: quad, status: status, accent: accent, warning: warning);
    case QuadOverlayStyle.glow:
      return QuadOverlay.glow(
          quad: quad, status: status, accent: accent, warning: warning);
  }
}
