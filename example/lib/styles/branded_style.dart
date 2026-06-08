import 'dart:async';
import 'dart:math' as math;

import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';

import 'result_screen.dart';

// =====================================================================
//  Fully custom branded scanner.
//
//  This file is a reference for "we control every pixel." Copy it into
//  your app, swap the colours and wordmark, and you have a polished,
//  on-brand scanner without losing any of the package's native
//  detection or auto-capture behaviour.
//
//  What's customised here:
//    - Animated coral halo around the detected quad
//    - Gradient shutter that breathes with the same timing
//    - Diagnostic readout in the corner (live quad coordinates)
//    - Italic-serif wordmark + mono caps eyebrow
//    - Background crosshair grid for "instrument" feel
// =====================================================================

const _coral = Color(0xFFFF6F61);
const _coralLight = Color(0xFFFFB199);
const _cream = Color(0xFFFFE8D6);
const _ink = Color(0xFF0F0E12);

/// Picker entries for the overlay-style cycler chip.
///
/// `null` slot in [_overlayStyleOrder] means "the branded animated halo"
/// — the iconic, scanner-specific look that combines a breathing coral
/// glow with the gradient stroke + corner pearls + (when capturing) a
/// rotating registration sweep. All other entries delegate to the
/// package's `QuadOverlay` family via [quadOverlayFor].
const _overlayStyleOrder = <QuadOverlayStyle?>[
  null, // animated coral halo (branded)
  QuadOverlayStyle.filled,
  QuadOverlayStyle.outline,
  QuadOverlayStyle.corners,
  QuadOverlayStyle.cornersFilled,
  QuadOverlayStyle.dots,
  QuadOverlayStyle.dotsLine,
  QuadOverlayStyle.glow,
];

String _overlayStyleLabel(QuadOverlayStyle? style) {
  if (style == null) return 'HALO';
  switch (style) {
    case QuadOverlayStyle.outline:
      return 'OUTLINE';
    case QuadOverlayStyle.filled:
      return 'FILLED';
    case QuadOverlayStyle.corners:
      return 'CORNERS';
    case QuadOverlayStyle.cornersFilled:
      return 'CORNERS+';
    case QuadOverlayStyle.dots:
      return 'DOTS';
    case QuadOverlayStyle.dotsLine:
      return 'DOTS+';
    case QuadOverlayStyle.glow:
      return 'GLOW';
  }
}

class BrandedStyleScanner extends StatefulWidget {
  const BrandedStyleScanner({super.key});
  @override
  State<BrandedStyleScanner> createState() => _BrandedStyleScannerState();
}

class _BrandedStyleScannerState extends State<BrandedStyleScanner>
    with SingleTickerProviderStateMixin {
  late final DoclensController _controller = DoclensController(
    config: const ScannerConfig(
      detectionThrottleHz: 18,
      autoCaptureStabilityDuration: Duration(milliseconds: 1100),
    ),
  );

  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  // Live state for the diagnostic readout — sourced from the package's
  // per-frame streams, NOT from `_controller.lastQuad`/`status` (those
  // are silent fields; the controller does not call notifyListeners on
  // every detection frame).
  Quad? _liveQuad;
  DetectionStatus _liveStatus = DetectionStatus.searching;
  StreamSubscription<Quad?>? _quadSub;
  StreamSubscription<DetectionStatus>? _statusSub;

  // Cycled by the chip next to the flash button. `null` is the iconic
  // branded animated halo; other entries are package-shipped
  // `QuadOverlay` variants from `_overlayStyleOrder`.
  int _overlayIndex = 0;
  QuadOverlayStyle? get _overlayStyle => _overlayStyleOrder[_overlayIndex];

  @override
  void initState() {
    super.initState();
    _controller.initialize();
    _quadSub = _controller.quadStream.listen((q) {
      if (mounted) setState(() => _liveQuad = q);
    });
    _statusSub = _controller.statusStream.listen((s) {
      if (mounted) setState(() => _liveStatus = s);
    });
  }

  @override
  void dispose() {
    _quadSub?.cancel();
    _statusSub?.cancel();
    _halo.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onCaptured(ScanResult r) async {
    // Pause the live session while the user reviews the capture — without
    // this the camera keeps detecting and auto-capture re-fires on the
    // result screen. Resume when they come back.
    await _controller.pause().catchError((_) {});
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ResultScreen(
          result: r,
          controller: _controller,
          accent: _coral,
        ),
      ),
    );
    if (!mounted) return;
    await _controller.resume().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: _ink,
      body: Stack(
        children: [
          // Background grain + crosshair grid.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _HudGridPainter()),
            ),
          ),
          DoclensView(
            controller: _controller,
            backgroundColor: _ink,
            overlayBuilder: (ctx, quad, status) {
              // The first slot of `_overlayStyleOrder` is `null`, which
              // means "render the iconic branded halo." Anything else
              // delegates to the package's `QuadOverlay` family so this
              // example doubles as a live tour of the shipped variants.
              final s = _overlayStyle;
              if (s == null) {
                return _HaloOverlay(
                  quad: quad,
                  status: status,
                  animation: _halo,
                );
              }
              return quadOverlayFor(
                style: s,
                quad: quad,
                status: status,
                accent: _coral,
                warning: _coralLight,
              );
            },
            captureButtonBuilder: (ctx, onTap) =>
                _GradientShutter(onTap: onTap, animation: _halo),
            // Flash and debug readout handled by us below — passing
            // `null` here tells the package widget not to position them
            // itself (the package's defaults use hard-coded coordinates
            // that overlap our safe-area chrome).
            flashButtonBuilder: null,
            debugOverlayBuilder: null,
            onCapture: _onCaptured,
          ),
          // Top row: close + flash chip, both safe-area-aware.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  _CloseDot(onTap: () => Navigator.of(context).maybePop()),
                  const Spacer(),
                  _Chip(
                    onTap: () => setState(() {
                      _overlayIndex =
                          (_overlayIndex + 1) % _overlayStyleOrder.length;
                    }),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.layers_outlined,
                          color: _cream,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _overlayStyleLabel(_overlayStyle),
                          style: _mono(size: 10, color: _cream),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => _Chip(
                      onTap: () => _controller.cycleFlashMode(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _flashIcon(_controller.flashMode),
                            color: _cream,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _controller.flashMode.name.toUpperCase(),
                            style: _mono(size: 10, color: _cream),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Diagnostic readout — placed below the top safe-area row so it
          // never overlaps the close button or the flash chip.
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom,
            right: 5,
            child: IgnorePointer(
              child: _DiagnosticReadout(
                quad: _liveQuad,
                status: _liveStatus,
              ),
            ),
          ),
          // Bottom legend — sits *above* the shutter band. The shutter
          // floats around y=`bottom: 32` per the package, so we push the
          // legend to ~140 to keep the two from touching even on phones
          // with a tall home indicator.
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset + 140,
            child: const IgnorePointer(child: _BottomLegend()),
          ),
        ],
      ),
    );
  }

  IconData _flashIcon(FlashMode mode) {
    switch (mode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.on:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
    }
  }
}

class _CloseDot extends StatelessWidget {
  const _CloseDot({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: _cream, size: 18),
      ),
    );
  }
}

// ---- the coral halo overlay (the iconic part) -------------------------

class _HaloOverlay extends StatelessWidget {
  const _HaloOverlay({
    required this.quad,
    required this.status,
    required this.animation,
  });
  final Quad? quad;
  final DetectionStatus status;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => CustomPaint(
        painter: _HaloPainter(
          quad: quad,
          status: status,
          t: animation.value,
        ),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({
    required this.quad,
    required this.status,
    required this.t,
  });
  final Quad? quad;
  final DetectionStatus status;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final q = quad;
    if (q == null) return;
    final scaled = q.scaleToSize(size);

    final isCapturing = status == DetectionStatus.confirming;
    final isReady = status == DetectionStatus.aligned || isCapturing;

    final path = Path()
      ..moveTo(scaled.topLeft.dx, scaled.topLeft.dy)
      ..lineTo(scaled.topRight.dx, scaled.topRight.dy)
      ..lineTo(scaled.bottomRight.dx, scaled.bottomRight.dy)
      ..lineTo(scaled.bottomLeft.dx, scaled.bottomLeft.dy)
      ..close();

    // Outer halo — soft blurred coral glow, breathing.
    final breathing = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    final haloAlpha = isReady ? 0.4 + 0.25 * breathing : 0.16;
    canvas.drawPath(
      path,
      Paint()
        ..color = _coral.withValues(alpha: haloAlpha)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          isReady ? 22.0 : 16.0,
        ),
    );

    // Inner cream fill — like paper showing through.
    canvas.drawPath(
      path,
      Paint()..color = _cream.withValues(alpha: 0.05),
    );

    // Stroke — gradient coral → cream.
    final rect = path.getBounds();
    final stroke = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_coral, _coralLight, _cream.withValues(alpha: 0.9)],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isCapturing ? 3.2 : 2.2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, stroke);

    // Corner pearls.
    for (final c in [
      scaled.topLeft,
      scaled.topRight,
      scaled.bottomRight,
      scaled.bottomLeft,
    ]) {
      canvas.drawCircle(c, 5, Paint()..color = _cream);
      canvas.drawCircle(
          c,
          5,
          Paint()
            ..color = _coral.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }

    // Rotating sweep when capturing — like a film registration mark.
    if (isCapturing) {
      final centroid = scaled.centroid;
      final radius = (rect.width + rect.height) * 0.18;
      final sweep = Path()
        ..moveTo(centroid.dx, centroid.dy)
        ..arcTo(
          Rect.fromCircle(center: centroid, radius: radius),
          t * 2 * math.pi,
          math.pi * 0.5,
          false,
        )
        ..close();
      canvas.drawPath(
        sweep,
        Paint()..color = _coral.withValues(alpha: 0.3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HaloPainter old) =>
      old.quad != quad || old.status != status || old.t != t;
}

// ---- gradient shutter ------------------------------------------------

class _GradientShutter extends StatefulWidget {
  const _GradientShutter({required this.onTap, required this.animation});
  final VoidCallback onTap;
  final Animation<double> animation;

  @override
  State<_GradientShutter> createState() => _GradientShutterState();
}

class _GradientShutterState extends State<_GradientShutter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapCancel: () => _press.reverse(),
      onTapUp: (_) {
        _press.reverse();
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_press, widget.animation]),
        builder: (context, _) {
          final breathing =
              0.5 + 0.5 * math.sin(widget.animation.value * 2 * math.pi);
          final pressScale = 1 - 0.08 * _press.value;
          // Solid cream face with a thin coral ring — reads as the
          // familiar iOS-style camera button while still feeling on-brand.
          // The breathing coral halo carries the rhythm; the face itself
          // stays calm so it doesn't fight the camera preview.
          return Transform.scale(
            scale: pressScale,
            child: Container(
              width: 84,
              height: 84,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _coral.withValues(alpha: 0.18 + 0.25 * breathing),
                boxShadow: [
                  BoxShadow(
                    color: _coral.withValues(alpha: 0.35 * breathing),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _cream,
                  border: Border.all(
                    color: _coral.withValues(alpha: 0.55),
                    width: 1.4,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---- HUD grid + crosshair background ----------------------------------

class _HudGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 0.6;
    const step = 56.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    // Center crosshair
    final cx = size.width / 2;
    final cy = size.height / 2;
    final cross = Paint()
      ..color = _coral.withValues(alpha: 0.15)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(cx - 14, cy), Offset(cx + 14, cy), cross);
    canvas.drawLine(Offset(cx, cy - 14), Offset(cx, cy + 14), cross);
  }

  @override
  bool shouldRepaint(covariant _HudGridPainter old) => false;
}

// ---- chrome primitives ------------------------------------------------

class _Chip extends StatelessWidget {
  const _Chip({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _ink.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _coral.withValues(alpha: 0.4)),
        ),
        child: child,
      ),
    );
  }
}

class _DiagnosticReadout extends StatelessWidget {
  const _DiagnosticReadout({required this.quad, required this.status});
  final Quad? quad;
  final DetectionStatus status;

  String _coord(double v) => v.toStringAsFixed(2).padLeft(4, ' ');

  @override
  Widget build(BuildContext context) {
    final q = quad;
    final s = status.name.toUpperCase();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: _ink.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _coral.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: _coral,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text('STATE  $s',
                  style: _mono(
                    size: 10,
                    color: _coral,
                    weight: FontWeight.w700,
                    letterSpacing: 0.24,
                  )),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            q == null
                ? 'QUAD'
                : 'TL ${_coord(q.topLeft.dx)},${_coord(q.topLeft.dy)}\n'
                    'TR ${_coord(q.topRight.dx)},${_coord(q.topRight.dy)}\n'
                    'BR ${_coord(q.bottomRight.dx)},${_coord(q.bottomRight.dy)}\n'
                    'BL ${_coord(q.bottomLeft.dx)},${_coord(q.bottomLeft.dy)}',
            style: _mono(
              size: 10,
              color: _cream.withValues(alpha: 0.85),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomLegend extends StatelessWidget {
  const _BottomLegend();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Hold the document still',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontStyle: FontStyle.italic,
              fontSize: 14,
              color: _cream.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- typography helper -----------------------------------------------

TextStyle _mono({
  double size = 11,
  FontWeight weight = FontWeight.w400,
  Color color = _cream,
  double letterSpacing = 0.18,
  double? height,
}) =>
    TextStyle(
      fontFamily: 'SF Mono',
      fontFamilyFallback: const ['Menlo', 'Roboto Mono', 'monospace'],
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
