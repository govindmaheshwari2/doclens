import 'dart:io';

import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ocr_sheet.dart';
import 'styles/branded_style.dart';
import 'styles/gallery_import_style.dart';
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
            'with confirmation, built-in review screen. Pick an enhancement '
            'mode first.',
        tags: const [
          'DoclensScreen.scan()',
          'auto-capture',
          'enhancement',
        ],
        accent: _kRust,
        preview: const _DropInPreview(),
        requiresLiveScan: true,
        onTap: (ctx) async {
          final mode = await _pickEnhancement(ctx);
          if (mode == null || !ctx.mounted) return;
          final result = await DoclensScreen.scan(
            ctx,
            imageEnhancement: mode,
            // Detect the page's text direction and straighten the crop upright.
            autoOrientation: AutoOrientation.auto,
          );
          if (result == null || !ctx.mounted) return;
          await Navigator.of(ctx).push<void>(
            MaterialPageRoute(
              builder: (_) =>
                  _ReturnedResult(result: result, enhancement: mode),
            ),
          );
        },
      ),
      _StyleEntry(
        index: '02',
        eyebrow: 'PACKAGE UI',
        title: 'Multi-page batch',
        subtitle:
            'Keep the camera open and stack pages. Thumbnail rail, reorder + '
            'delete from a built-in manager, then return the whole '
            'List<ScanResult>.',
        tags: const [
          'DoclensMultiScreen.scan()',
          'batch',
          'reorder',
        ],
        accent: _kRust,
        preview: const _DropInPreview(),
        requiresLiveScan: true,
        onTap: (ctx) async {
          final pages = await DoclensMultiScreen.scan(
            ctx,
            autoOrientation: AutoOrientation.auto,
          );
          if (pages == null || pages.isEmpty || !ctx.mounted) return;
          await Navigator.of(ctx).push<void>(
            MaterialPageRoute(builder: (_) => _ReturnedBatch(pages: pages)),
          );
        },
      ),
      _StyleEntry(
        index: '03',
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
        requiresLiveScan: true,
        onTap: (ctx) => Navigator.of(ctx).push(
          MaterialPageRoute<void>(builder: (_) => const BrandedStyleScanner()),
        ),
      ),
      _StyleEntry(
        index: '04',
        eyebrow: 'PACKAGE UI',
        title: 'Large-document scan',
        subtitle:
            "Capture a document too big for one frame. Shoot a piece, tap a + "
            'on any edge, line the next shot up against the overlap ghost; a '
            'miniview shows the whole page forming, then it stitches to one '
            'image.',
        tags: const [
          'DoclensLargeDocScreen.scan()',
          'overlap ghost',
          'auto-stitch',
        ],
        accent: _kRust,
        preview: const _LargeDocPreview(),
        requiresLiveScan: true,
        onTap: (ctx) async {
          final path = await DoclensLargeDocScreen.scan(ctx);
          if (path == null || !ctx.mounted) return;
          await Navigator.of(ctx).push<void>(
            MaterialPageRoute(builder: (_) => _ReturnedLargeDoc(path: path)),
          );
        },
      ),
      _StyleEntry(
        index: '05',
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
        requiresLiveScan: true,
        onTap: (ctx) => Navigator.of(ctx).push(
          MaterialPageRoute<void>(builder: (_) => const NativeOSScanner()),
        ),
      ),
      _StyleEntry(
        index: '06',
        eyebrow: 'GALLERY IMPORT',
        title: 'Import a photo',
        subtitle: 'Pick an existing photo from the gallery, then run the same '
            'detect → edit-corners → warp pipeline on it. No camera needed.',
        tags: const [
          'detectInImage()',
          'EditCornersScreen',
          'warpImage()',
        ],
        accent: _kRust,
        preview: const _GalleryPreview(),
        requiresImportFlow: true,
        onTap: (ctx) => Navigator.of(ctx).push(
          MaterialPageRoute<void>(builder: (_) => const GalleryImportScanner()),
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
            if (!DoclensPlatform.supportsLiveScan) ...[
              _PlatformBanner(
                importSupported: DoclensPlatform.supportsImportFlow,
              ),
              const SizedBox(height: 16),
            ],
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

// ---- off-mobile platform notice ----------------------------------------

/// Shown on web/desktop (where the native live scanner can't run) to explain
/// why the camera cards are disabled and point at the flow that still works.
class _PlatformBanner extends StatelessWidget {
  const _PlatformBanner({required this.importSupported});

  final bool importSupported;

  @override
  Widget build(BuildContext context) {
    final message = importSupported
        ? 'No native camera on this platform. Live scanning is Android / iOS '
            'only — but “Import a photo” runs the full detect → edit → warp '
            'pipeline here in pure Dart.'
        : 'No native camera and no filesystem on web. Decode an image to bytes '
            'and call PerspectiveWarp.warpBytes / ImageEnhance.apply directly.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kPaperRecessed,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kRule),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.desktop_windows_outlined,
              size: 18, color: _kInkSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: _mono(size: 11, color: _kInkSoft, height: 1.5),
            ),
          ),
        ],
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
    this.requiresLiveScan = false,
    this.requiresImportFlow = false,
  });
  final String index;
  final String eyebrow;
  final String title;
  final String subtitle;
  final List<String> tags;
  final Color accent;
  final Widget preview;
  final void Function(BuildContext) onTap;

  /// Needs the native live camera + edge detector (Android / iOS only).
  final bool requiresLiveScan;

  /// Needs the path-based import → warp pipeline (mobile + desktop; not web).
  final bool requiresImportFlow;

  /// Whether this entry can run on the current platform. Disabled entries are
  /// dimmed and explain why on tap rather than throwing.
  bool get isSupported =>
      (!requiresLiveScan || DoclensPlatform.supportsLiveScan) &&
      (!requiresImportFlow || DoclensPlatform.supportsImportFlow);

  /// Why a disabled entry can't run here, for the tap hint.
  String get unsupportedReason {
    if (requiresLiveScan && !DoclensPlatform.supportsLiveScan) {
      return 'Live camera scanning runs on Android and iOS. On this platform, '
          'try “Import a photo”.';
    }
    return 'The path-based import pipeline needs a filesystem, which web '
        "doesn't provide. Decode to bytes and use PerspectiveWarp directly.";
  }
}

class _StyleCard extends StatefulWidget {
  const _StyleCard({required this.entry});
  final _StyleEntry entry;

  @override
  State<_StyleCard> createState() => _StyleCardState();
}

class _StyleCardState extends State<_StyleCard> {
  bool _pressed = false;

  void _handleTap() {
    final e = widget.entry;
    if (e.isSupported) {
      e.onTap(context);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${e.title} — ${e.unsupportedReason}'),
          backgroundColor: _kInk,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final enabled = e.isSupported;
    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTap: _handleTap,
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

    if (enabled) return card;
    // Off-platform: dim the card and badge why it can't run here. The tap
    // still fires (see _handleTap) to explain instead of silently failing.
    return Stack(
      children: [
        Opacity(opacity: 0.45, child: card),
        Positioned(
          top: 10,
          right: 10,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _kInk,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                e.requiresLiveScan ? 'CAMERA ONLY' : 'MOBILE / DESKTOP',
                style: _mono(
                  size: 9,
                  color: _kPaperHi,
                  weight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ],
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

class _LargeDocPreview extends StatelessWidget {
  const _LargeDocPreview();

  @override
  Widget build(BuildContext context) {
    Widget frag(double opacity) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF4F0E8).withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(1.5),
            border: Border.all(color: const Color(0xFF14130F), width: 0.5),
          ),
        );
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: SizedBox(
            width: 96,
            height: 116,
            // A 2x2 block of fragments — the composite taking shape.
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
              children: [
                frag(0.95),
                frag(0.6),
                frag(0.6),
                frag(0.35),
              ],
            ),
          ),
        ),
        // A `+` affordance on the open right edge.
        Positioned(
          right: 28,
          top: 0,
          bottom: 0,
          child: Center(
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: _kRust,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, size: 13, color: Colors.white),
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(painter: _QuadBracketsPainter(color: _kInkBlue)),
        ),
      ],
    );
  }
}

class _ReturnedLargeDoc extends StatelessWidget {
  const _ReturnedLargeDoc({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14130F),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  _OverlayIconButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'STITCHED COMPOSITE',
                    style: _mono(
                      size: 10.5,
                      color: Colors.white,
                      weight: FontWeight.w700,
                      letterSpacing: 0.28,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                maxScale: 6,
                child: Center(child: Image.file(File(path))),
              ),
            ),
          ],
        ),
      ),
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

class _GalleryPreview extends StatelessWidget {
  const _GalleryPreview();
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const _MiniDoc(skew: 0.0, opacity: 0.92),
        Positioned.fill(
          child: CustomPaint(painter: _QuadBracketsPainter(color: _kRust)),
        ),
        // A small "photos" badge to signal the source is the gallery, not
        // the live camera.
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Icon(Icons.photo_library_outlined,
                size: 12, color: Colors.white),
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
      children: [
        Container(height: 1, color: _kRule),
        const SizedBox(height: 22),
        Text(
          'Govind Maheshwari',
          style: _mono(
            size: 11,
            color: _kInkDim,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _FooterLink(
              label: 'github',
              url: 'https://github.com/govindmaheshwari2',
            ),
            _FooterLink(
              label: 'email',
              url: 'mailto:govindmh14@gmail.com',
            ),
            _FooterLink(
              label: 'linkedin',
              url: 'https://www.linkedin.com/in/govind-maheshwari-214a20190/',
            ),
          ],
        ),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Text(
        label,
        style: _mono(
          size: 11,
          color: _kRust,
          height: 1.7,
        ).copyWith(
            decoration: TextDecoration.underline, decorationColor: _kRust),
      ),
    );
  }
}

// =====================================================================
//  Enhancement-mode picker (drop-in entry)
// =====================================================================

/// One row of metadata per [ImageEnhancement] value, in display order.
const _kEnhancementOptions = <(ImageEnhancement, String, String)>[
  (ImageEnhancement.none, 'None', 'Pure dewarp — original pixels, untouched'),
  (ImageEnhancement.grayscale, 'Grayscale', 'Plain desaturate'),
  (
    ImageEnhancement.enhanced,
    'Enhanced',
    'Shadow removal + whitened background, colour kept ("magic colour")'
  ),
  (
    ImageEnhancement.blackAndWhite,
    'Black & white',
    'Shadow removal + bitonal — best for OCR on faint text'
  ),
];

/// Presents the enhancement options and resolves with the chosen mode, or
/// `null` if the sheet is dismissed.
Future<ImageEnhancement?> _pickEnhancement(BuildContext context) {
  return showModalBottomSheet<ImageEnhancement>(
    context: context,
    backgroundColor: _kPaper,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'IMAGE ENHANCEMENT',
                style: _mono(
                  size: 10,
                  color: _kRust,
                  weight: FontWeight.w700,
                  letterSpacing: 0.26,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Applied to the cropped scan',
                style: _serifS(size: 22, italic: true),
              ),
              const SizedBox(height: 16),
              for (final (mode, label, blurb) in _kEnhancementOptions) ...[
                _EnhancementOptionTile(
                  label: label,
                  blurb: blurb,
                  onTap: () => Navigator.of(sheetCtx).pop(mode),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _EnhancementOptionTile extends StatelessWidget {
  const _EnhancementOptionTile({
    required this.label,
    required this.blurb,
    required this.onTap,
  });
  final String label;
  final String blurb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _kPaperHi,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kRule),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: _serifS(size: 17, italic: false, height: 1.1),
                  ),
                  const SizedBox(height: 3),
                  Text(blurb, style: _mono(size: 10.5, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward, size: 14, color: _kRust),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
//  Returned-result preview (drop-in entry)
// =====================================================================

class _ReturnedResult extends StatefulWidget {
  const _ReturnedResult({required this.result, this.enhancement});
  final ScanResult result;
  final ImageEnhancement? enhancement;

  @override
  State<_ReturnedResult> createState() => _ReturnedResultState();
}

class _ReturnedResultState extends State<_ReturnedResult> {
  late String _path =
      widget.result.croppedImagePath ?? widget.result.rawImagePath;
  bool _rotating = false;

  ScanResult get result => widget.result;
  ImageEnhancement? get enhancement => widget.enhancement;

  /// Run on-device OCR on the displayed image. The shared sheet calls the
  /// package's `recognizeText` itself (a pure file op — no camera session or
  /// controller needed) on the current, possibly-rotated, crop path.
  void _runOcr() => showOcrSheet(context, _path, accent: _kRust);

  /// Show the returned [ScanResult] metadata in a bottom sheet.
  void _showDetails() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kPaper,
      showDragHandle: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                Text('Drop-in scanner output',
                    style: _serifS(size: 22, italic: true)),
                const SizedBox(height: 16),
                if (enhancement != null)
                  _kv('imageEnhancement', enhancement!.name),
                _kv('rawImageSize',
                    '${result.rawImageSize.width.toInt()} × ${result.rawImageSize.height.toInt()}'),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Manual rotate — a pure file op via the platform instance, so it needs no
  /// camera session or controller. `evict` clears the old file from Flutter's
  /// image cache so the rotated bytes actually show.
  Future<void> _rotate(int quarterTurns) async {
    if (_rotating) return;
    setState(() => _rotating = true);
    try {
      final out = await DoclensPlatform.instance
          .rotateImage(imagePath: _path, quarterTurns: quarterTurns);
      await FileImage(File(out)).evict();
      if (!mounted) return;
      setState(() => _path = out);
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    return Scaffold(
      backgroundColor: const Color(0xFF14130F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen image.
          Positioned.fill(
            child: Image.file(File(path), fit: BoxFit.contain),
          ),

          // Top bar — back + rotate, over a subtle scrim for legibility.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Colors.transparent],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Row(
                    children: [
                      _OverlayIconButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      _OverlayIconButton(
                        icon: Icons.rotate_left,
                        enabled: !_rotating,
                        onTap: () => _rotate(-1),
                      ),
                      const SizedBox(width: 10),
                      _OverlayIconButton(
                        icon: Icons.rotate_right,
                        enabled: !_rotating,
                        onTap: () => _rotate(1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom action bar — Details + OCR, each opening a bottom sheet.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xCC000000), Colors.transparent],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _OverlayActionButton(
                          icon: Icons.info_outline,
                          label: 'DETAILS',
                          onTap: _showDetails,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _OverlayActionButton(
                          icon: Icons.text_fields,
                          label: 'OCR',
                          filled: true,
                          onTap: _runOcr,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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

// =====================================================================
//  Returned-batch preview (multi-page entry)
// =====================================================================

class _ReturnedBatch extends StatefulWidget {
  const _ReturnedBatch({required this.pages});
  final List<ScanResult> pages;

  @override
  State<_ReturnedBatch> createState() => _ReturnedBatchState();
}

class _ReturnedBatchState extends State<_ReturnedBatch> {
  late final List<ScanResult> pages = List.of(widget.pages);

  @override
  Widget build(BuildContext context) {
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
                      child: const Icon(Icons.arrow_back, color: _kInk, size: 18),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RETURNED BATCH',
                          style: _mono(
                            size: 10,
                            color: _kRust,
                            weight: FontWeight.w700,
                            letterSpacing: 0.26,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${pages.length} page${pages.length == 1 ? '' : 's'}',
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
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemCount: pages.length,
                itemBuilder: (context, i) {
                  final page = pages[i];
                  final path = page.croppedImagePath ?? page.rawImagePath;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => _BatchPageViewer(
                          pages: pages,
                          initialIndex: i,
                          onRotated: (index, rotatedPath) => setState(() {
                            pages[index] = pages[index]
                                .copyWith(croppedImagePath: rotatedPath);
                          }),
                        ),
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _kPaperHi,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kRule),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Page ${i + 1}', style: _mono(size: 10)),
                              const Spacer(),
                              const Icon(Icons.open_in_full,
                                  size: 13, color: _kRust),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.file(File(path), fit: BoxFit.cover,
                                  width: double.infinity),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('TAP TO OPEN',
                              style: _mono(
                                size: 8,
                                color: _kInkDim,
                                letterSpacing: 0.2,
                              )),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
//  Full-screen swipeable viewer for a multi-page batch
// =====================================================================

class _BatchPageViewer extends StatefulWidget {
  const _BatchPageViewer({
    required this.pages,
    required this.initialIndex,
    required this.onRotated,
  });
  final List<ScanResult> pages;
  final int initialIndex;

  /// Called with the page index and the new image path after a manual rotate,
  /// so the caller can persist it back into its [ScanResult] list.
  final void Function(int index, String rotatedPath) onRotated;

  @override
  State<_BatchPageViewer> createState() => _BatchPageViewerState();
}

class _BatchPageViewerState extends State<_BatchPageViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// Current display path per page — seeded from each scan, replaced in place
  /// when a page is rotated.
  late final List<String> _paths = [
    for (final p in widget.pages) p.croppedImagePath ?? p.rawImagePath,
  ];
  bool _rotating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runOcr() => showOcrSheet(context, _paths[_index], accent: _kRust);

  Future<void> _rotate(int quarterTurns) async {
    if (_rotating) return;
    setState(() => _rotating = true);
    final i = _index;
    try {
      final out = await DoclensPlatform.instance
          .rotateImage(imagePath: _paths[i], quarterTurns: quarterTurns);
      await FileImage(File(out)).evict();
      if (!mounted) return;
      setState(() => _paths[i] = out);
      widget.onRotated(i, out);
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14130F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.pages.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) =>
                Image.file(File(_paths[i]), fit: BoxFit.contain),
          ),

          // Top bar — back + page counter + rotate.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Colors.transparent],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Row(
                    children: [
                      _OverlayIconButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18)),
                        ),
                        child: Text(
                          '${_index + 1} / ${widget.pages.length}',
                          style: _mono(
                            size: 11,
                            color: Colors.white,
                            weight: FontWeight.w700,
                            letterSpacing: 0.24,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _OverlayIconButton(
                        icon: Icons.rotate_left,
                        enabled: !_rotating,
                        onTap: () => _rotate(-1),
                      ),
                      const SizedBox(width: 10),
                      _OverlayIconButton(
                        icon: Icons.rotate_right,
                        enabled: !_rotating,
                        onTap: () => _rotate(1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom bar — OCR.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xCC000000), Colors.transparent],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                  child: _OverlayActionButton(
                    icon: Icons.text_fields,
                    label: 'OCR',
                    filled: true,
                    onTap: _runOcr,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular icon button rendered over the full-screen image (top bar).
class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: enabled ? 1 : 0.4),
          size: 19,
        ),
      ),
    );
  }
}

/// Pill action button rendered over the full-screen image (bottom bar).
class _OverlayActionButton extends StatelessWidget {
  const _OverlayActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? _kPaperHi : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: filled ? _kRust : Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: filled
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: fg),
            const SizedBox(width: 9),
            Text(
              label,
              style: _mono(
                size: 11,
                color: fg,
                weight: FontWeight.w700,
                letterSpacing: 0.26,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
//  OCR — extract text from a scan (recognizeText)
// =====================================================================

