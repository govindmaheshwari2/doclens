import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doclens/doclens.dart';

import 'styles/branded_style.dart';
import 'styles/native_os_style.dart';

void main() => runApp(const ExampleApp());

// =====================================================================
//  Paper palette — warm off-white, ink, one rust accent.
//  The camera screens stay dark; the showroom reads like a manpage.
// =====================================================================

const _kPaper = Color(0xFFF4F0E8);
const _kPaperHi = Color(0xFFFAF7F0);
const _kPaperRecessed = Color(0xFFEDE7DA);
const _kRule = Color(0x1A1A1815);
const _kRuleSoft = Color(0x0D1A1815);

const _kInk = Color(0xFF1A1815);
const _kInkSoft = Color(0xFF5C5852);
const _kInkDim = Color(0xFF8E8A83);

const _kRust = Color(0xFFB5482E);
const _kInkBlue = Color(0xFF1E3A5F);
const _kCharcoal = Color(0xFF3A3833);

const _kMono = <String>['SF Mono', 'Menlo', 'Roboto Mono', 'monospace'];
const _kSerif = <String>['Iowan Old Style', 'Georgia', 'serif'];

TextStyle _mono({
  double size = 11,
  FontWeight weight = FontWeight.w400,
  Color color = _kInkSoft,
  double letterSpacing = 0.12,
  double? height,
}) =>
    TextStyle(
      fontFamily: _kMono.first,
      fontFamilyFallback: _kMono.sublist(1),
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );

TextStyle _serifS({
  double size = 22,
  FontWeight weight = FontWeight.w400,
  Color color = _kInk,
  bool italic = true,
  double height = 1.1,
  double letterSpacing = -0.2,
}) =>
    TextStyle(
      fontFamily: _kSerif.first,
      fontFamilyFallback: _kSerif.sublist(1),
      fontSize: size,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    return MaterialApp(
      title: 'flutter_native_doc_scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: _kPaper,
        colorScheme: const ColorScheme.light(
          surface: _kPaper,
          primary: _kRust,
          onPrimary: _kPaperHi,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: _kRust,
        ),
      ),
      home: const ShowroomHome(),
    );
  }
}

// =====================================================================
//  Showroom
// =====================================================================

class ShowroomHome extends StatelessWidget {
  const ShowroomHome({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = <_StyleEntry>[
      _StyleEntry(
        index: '01',
        eyebrow: 'PACKAGE UI',
        title: 'Drop-in scanner',
        subtitle:
            'One call returns a polished scanner: live preview, auto-capture '
            'with confirmation, built-in review screen.',
        tags: const [
          'DoclensScreen.scan()',
          'auto-capture',
          'edit corners',
        ],
        accent: _kRust,
        preview: const _DropInPreview(),
        onTap: (ctx) async {
          final result = await DoclensScreen.scan(ctx);
          if (result == null || !ctx.mounted) return;
          await Navigator.of(ctx).push<void>(
            MaterialPageRoute(
              builder: (_) => _ReturnedResult(result: result),
            ),
          );
        },
      ),
      _StyleEntry(
        index: '02',
        eyebrow: 'FULL CUSTOM',
        title: 'Branded scanner',
        subtitle: 'Bring your own brand. Animated halo, gradient shutter, live '
            'diagnostic readout — a reference for "every pixel ours."',
        tags: const [
          'DoclensView widget',
          'builder slots',
          'custom paint',
        ],
        accent: _kInkBlue,
        preview: const _BrandedPreview(),
        onTap: (ctx) => Navigator.of(ctx).push(
          MaterialPageRoute<void>(builder: (_) => const BrandedStyleScanner()),
        ),
      ),
      _StyleEntry(
        index: '03',
        eyebrow: 'OS NATIVE',
        title: 'System scanner',
        subtitle: 'Hand off to the OS. Vision document camera on iOS, ML Kit '
            'document scanner on Android. Multi-page, no Flutter UI.',
        tags: const [
          'scanWithNativeUI()',
          'multi-page',
          'no Flutter UI',
        ],
        accent: _kCharcoal,
        preview: const _NativePreview(),
        onTap: (ctx) => Navigator.of(ctx).push(
          MaterialPageRoute<void>(builder: (_) => const NativeOSScanner()),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: _kPaper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
          children: [
            const _ShowroomMasthead(),
            const SizedBox(height: 24),
            for (final e in entries) ...[
              _StyleCard(entry: e),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 14),
            const _ShowroomFooter(),
          ],
        ),
      ),
    );
  }
}

// ---- masthead ----------------------------------------------------------

class _ShowroomMasthead extends StatelessWidget {
  const _ShowroomMasthead();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: _kRust,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'DOCLENS · v0.1',
                  style: _mono(
                    size: 10.5,
                    color: _kInkSoft,
                    weight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'A precision\nscanning instrument.',
            style: _serifS(
              size: 36,
              italic: true,
              height: 1.02,
              color: _kInk,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Three ways to ship a document scanner — a polished drop-in, '
            'a fully custom UI on the package widget, or a hand-off to the '
            'system scanner.',
            style: _mono(
              size: 12.5,
              color: _kInkSoft,
              height: 1.55,
              letterSpacing: 0.05,
            ),
          ),
          const SizedBox(height: 28),
          Container(height: 1, color: _kRule),
        ],
      ),
    );
  }
}

// ---- entry model + card ----------------------------------------------

class _StyleEntry {
  const _StyleEntry({
    required this.index,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.accent,
    required this.preview,
    required this.onTap,
  });
  final String index;
  final String eyebrow;
  final String title;
  final String subtitle;
  final List<String> tags;
  final Color accent;
  final Widget preview;
  final void Function(BuildContext) onTap;
}

class _StyleCard extends StatefulWidget {
  const _StyleCard({required this.entry});
  final _StyleEntry entry;

  @override
  State<_StyleCard> createState() => _StyleCardState();
}

class _StyleCardState extends State<_StyleCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: () => e.onTap(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..scaleByDouble(
              _pressed ? 0.992 : 1.0, _pressed ? 0.992 : 1.0, 1.0, 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: _kPaperHi,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kRule),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A1A1815),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _EyebrowRow(
                        index: e.index,
                        label: e.eyebrow,
                        accent: e.accent,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        e.title,
                        style: _serifS(
                          size: 22,
                          italic: true,
                          color: _kInk,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        e.subtitle,
                        style: _mono(
                          size: 11,
                          color: _kInkSoft,
                          height: 1.5,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Flexible(child: _Tag(label: e.tags.first)),
                          const SizedBox(width: 6),
                          _LaunchHint(accent: e.accent),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 132,
                height: 132,
                child: _StyleCardPreviewFrame(
                  accent: e.accent,
                  child: e.preview,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EyebrowRow extends StatelessWidget {
  const _EyebrowRow({
    required this.index,
    required this.label,
    required this.accent,
  });
  final String index;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          index,
          style: _mono(
            size: 11,
            color: _kInkDim,
            weight: FontWeight.w600,
            letterSpacing: 0.24,
          ),
        ),
        const SizedBox(width: 10),
        Container(height: 1, width: 14, color: accent.withValues(alpha: 0.55)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            style: _mono(
              size: 10,
              color: accent,
              weight: FontWeight.w700,
              letterSpacing: 0.26,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kPaperRecessed,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _kRuleSoft),
      ),
      child: Text(
        label,
        style: _mono(
          size: 10,
          color: _kInkSoft,
          letterSpacing: 0.12,
        ),
      ),
    );
  }
}

class _LaunchHint extends StatelessWidget {
  const _LaunchHint({required this.accent});
  final Color accent;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'LAUNCH',
            style: _mono(
              size: 10,
              color: _kPaperHi,
              weight: FontWeight.w700,
              letterSpacing: 0.26,
            ),
          ),
          const SizedBox(width: 5),
          const Icon(Icons.arrow_forward, size: 11, color: _kPaperHi),
        ],
      ),
    );
  }
}

class _StyleCardPreviewFrame extends StatelessWidget {
  const _StyleCardPreviewFrame({required this.child, required this.accent});
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF14130F),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _kRuleSoft),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MicroReticlePainter(color: accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MicroReticlePainter extends CustomPainter {
  _MicroReticlePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const margin = 6.0;
    const len = 8.0;
    final p = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.0;
    void corner(Offset o, Offset dx, Offset dy) {
      canvas.drawLine(o, o + dx, p);
      canvas.drawLine(o, o + dy, p);
    }

    corner(const Offset(margin, margin), const Offset(len, 0),
        const Offset(0, len));
    corner(Offset(size.width - margin, margin), const Offset(-len, 0),
        const Offset(0, len));
    corner(Offset(margin, size.height - margin), const Offset(len, 0),
        const Offset(0, -len));
    corner(Offset(size.width - margin, size.height - margin),
        const Offset(-len, 0), const Offset(0, -len));
  }

  @override
  bool shouldRepaint(covariant _MicroReticlePainter old) => old.color != color;
}

// ---- per-style mini previews ----------------------------------------

class _MiniDoc extends StatelessWidget {
  const _MiniDoc({this.skew = 0.04, this.opacity = 0.92});
  final double skew;
  final double opacity;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateX(skew)
          ..rotateZ(skew * 0.6),
        child: Container(
          width: 84,
          height: 112,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F0E8).withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(2),
          ),
          padding: const EdgeInsets.all(7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 6, width: 38, color: const Color(0xFF14130F)),
              const SizedBox(height: 5),
              for (var i = 0; i < 7; i++) ...[
                Container(
                  height: 2,
                  width: 60 - (i * 2).toDouble().clamp(0, 30),
                  color: const Color(0xFF14130F).withValues(alpha: 0.4),
                ),
                const SizedBox(height: 3),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DropInPreview extends StatelessWidget {
  const _DropInPreview();
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const _MiniDoc(),
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: _kRust,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'ALIGNED',
                    style: _mono(
                      size: 7.5,
                      color: Colors.white,
                      weight: FontWeight.w700,
                      letterSpacing: 0.28,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 6,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _kRust, width: 1.4),
              ),
              child: const Padding(
                padding: EdgeInsets.all(2.5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _kRust,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _QuadBracketsPainter(color: _kRust),
          ),
        ),
      ],
    );
  }
}

class _BrandedPreview extends StatelessWidget {
  const _BrandedPreview();
  @override
  Widget build(BuildContext context) {
    const accent = _kInkBlue;
    const lightOnDark = Color(0xFFEDEAE0);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.9,
                colors: [
                  accent.withValues(alpha: 0.22),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        const _MiniDoc(skew: 0.05, opacity: 0.9),
        Positioned.fill(
          child: CustomPaint(
            painter: _GlowQuadPainter(color: accent),
          ),
        ),
        Positioned(
          bottom: 6,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent, lightOnDark],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.55),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.fiber_manual_record, color: accent, size: 9),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: Text(
              'STUDIO',
              style: _mono(
                size: 7,
                color: lightOnDark,
                weight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlowQuadPainter extends CustomPainter {
  _GlowQuadPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      size.width * 0.22,
      size.height * 0.22,
      size.width * 0.56,
      size.height * 0.56,
    );
    final dx = size.width * 0.04;
    final path = Path()
      ..moveTo(r.left + dx, r.top)
      ..lineTo(r.right - dx * 0.5, r.top + r.height * 0.04)
      ..lineTo(r.right, r.bottom - r.height * 0.06)
      ..lineTo(r.left - dx * 0.3, r.bottom)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant _GlowQuadPainter old) => old.color != color;
}

class _NativePreview extends StatelessWidget {
  const _NativePreview();
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Container(color: const Color(0xFF1C1C1E)),
        ),
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.close, size: 10, color: Colors.white),
              Text(
                '1 of 3',
                style: _mono(size: 8, color: Colors.white, letterSpacing: 0.2),
              ),
              const Icon(Icons.flash_auto, size: 10, color: Colors.white),
            ],
          ),
        ),
        const Center(child: _MiniDoc(opacity: 0.95, skew: 0.0)),
        Positioned(
          bottom: 6,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Padding(
                padding: EdgeInsets.all(2.5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuadBracketsPainter extends CustomPainter {
  _QuadBracketsPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      size.width * 0.22,
      size.height * 0.22,
      size.width * 0.56,
      size.height * 0.56,
    );
    final dx = size.width * 0.04;
    final corners = <Offset>[
      Offset(r.left + dx, r.top),
      Offset(r.right - dx * 0.5, r.top + r.height * 0.04),
      Offset(r.right, r.bottom - r.height * 0.06),
      Offset(r.left - dx * 0.3, r.bottom),
    ];
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.square;
    const len = 10.0;
    for (final c in corners) {
      final cdx = (size.width / 2 - c.dx).sign;
      final cdy = (size.height / 2 - c.dy).sign;
      canvas.drawLine(c, c + Offset(cdx * len, 0), paint);
      canvas.drawLine(c, c + Offset(0, cdy * len), paint);
      canvas.drawCircle(c, 1.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _QuadBracketsPainter old) => old.color != color;
}

// ---- footer ----------------------------------------------------------

class _ShowroomFooter extends StatelessWidget {
  const _ShowroomFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: _kRule),
        const SizedBox(height: 22),
        Text(
          'iOS — Vision document segmentation (15+), with rectangle\n'
          'detection fallback on older devices.\n\n'
          'Android — CameraX with a native Kotlin Sobel pipeline.',
          style: _mono(
            size: 11,
            color: _kInkDim,
            height: 1.7,
          ),
        ),
      ],
    );
  }
}

// =====================================================================
//  Returned-result preview (drop-in entry)
// =====================================================================

class _ReturnedResult extends StatelessWidget {
  const _ReturnedResult({required this.result});
  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final path = result.croppedImagePath ?? result.rawImagePath;
    return Scaffold(
      backgroundColor: _kPaper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      height: 36,
                      width: 36,
                      decoration: BoxDecoration(
                        color: _kPaperHi,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: _kRule),
                      ),
                      child:
                          const Icon(Icons.arrow_back, color: _kInk, size: 18),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RETURNED SCANRESULT',
                          style: _mono(
                            size: 10,
                            color: _kRust,
                            weight: FontWeight.w700,
                            letterSpacing: 0.26,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Drop-in scanner output',
                          style: _serifS(size: 22, italic: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  decoration: BoxDecoration(
                    color: _kPaperHi,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kRule),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(File(path), fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kPaperHi,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kRuleSoft),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv('rawImagePath', result.rawImagePath),
                    _kv('croppedImagePath',
                        result.croppedImagePath ?? '— (none)'),
                    _kv('rawImageSize',
                        '${result.rawImageSize.width.toInt()} × ${result.rawImageSize.height.toInt()}'),
                    _kv('warpError', result.warpError ?? '— (none)'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              k.toUpperCase(),
              style: _mono(
                size: 10,
                color: _kInkSoft,
                weight: FontWeight.w600,
                letterSpacing: 0.24,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: _mono(
                size: 11,
                color: _kInk,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
