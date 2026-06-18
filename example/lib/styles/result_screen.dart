import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';

import '../ocr_sheet.dart';

// =====================================================================
//  Review screen used by the branded scanner.
//
//  Editorial / instrument vocabulary: ink background, mono caps for
//  labels, italic serif for chrome, accent strip in the corner pulled
//  from the caller's style. Buttons are flat ghost + filled-accent.
// =====================================================================

const _kInk = Color(0xFF0A0B0D);
const _kSurface = Color(0xFF13151A);
const _kSurfaceHi = Color(0xFF1A1D24);
const _kBorder = Color(0x22FFFFFF);
const _kBorderHairline = Color(0x14FFFFFF);
const _kTextPrimary = Color(0xFFF4F4F2);
const _kTextSecondary = Color(0xFF8C8E93);
const _kTextDim = Color(0xFF5A5C61);
const _kAccent = Color(0xFFD4FF4D);

TextStyle _mono({
  double size = 11,
  FontWeight weight = FontWeight.w400,
  Color color = _kTextSecondary,
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

TextStyle _serif({
  double size = 22,
  FontWeight weight = FontWeight.w400,
  Color color = _kTextPrimary,
  bool italic = true,
  double height = 1.1,
}) =>
    TextStyle(
      fontFamily: 'Georgia',
      fontFamilyFallback: const ['Iowan Old Style', 'serif'],
      fontSize: size,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: color,
      height: height,
    );

/// Review screen used by the branded scanner. [accent] tints the
/// eyebrow, the corner brackets, and the primary action so the screen
/// reads as part of the calling style's visual identity.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.result,
    required this.controller,
    this.accent = _kAccent,
  });

  final ScanResult result;
  final DoclensController controller;
  final Color accent;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late ScanResult _result = widget.result;
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final cropped = _result.croppedImagePath;
    return Scaffold(
      backgroundColor: _kInk,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              accent: widget.accent,
              onBack: () => Navigator.of(context).pop(),
              hasWarpError: _result.warpError != null,
            ),
            Expanded(
              child: cropped == null
                  ? _Empty(
                      hasWarpError: _result.warpError != null,
                      accent: widget.accent,
                    )
                  : _PreviewCard(path: cropped, accent: widget.accent),
            ),
            _Actions(
              accent: widget.accent,
              busy: _editing,
              onRetake: () => Navigator.of(context).pop(),
              onEditCorners: _editCorners,
              onOcr: cropped == null ? null : _runOcr,
              onUse: () => Navigator.of(context).pop(_result),
            ),
          ],
        ),
      ),
    );
  }

  /// Extract text from the cropped scan. The shared OCR sheet runs the
  /// package's `recognizeText` on-device and renders the transcript; it's
  /// dark-themed and tinted with this style's accent to match the screen.
  void _runOcr() {
    final cropped = _result.croppedImagePath;
    if (cropped == null) return;
    showOcrSheet(context, cropped, accent: widget.accent, dark: true);
  }

  Future<void> _editCorners() async {
    setState(() => _editing = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EditCornersScreen(
            imagePath: _result.rawImagePath,
            initialQuad: _result.detectedQuad,
            imageSize: _result.rawImageSize,
            onSave: (q) async {
              final newPath = await widget.controller.warpImage(
                _result.rawImagePath,
                q,
              );
              if (!mounted) return newPath;
              setState(() {
                _result = ScanResult(
                  croppedImagePath: newPath,
                  rawImagePath: _result.rawImagePath,
                  detectedQuad: q,
                  rawImageSize: _result.rawImageSize,
                );
              });
              Navigator.of(context).pop();
              return newPath;
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }
}

// ---- header ----------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.accent,
    required this.onBack,
    required this.hasWarpError,
  });
  final Color accent;
  final VoidCallback onBack;
  final bool hasWarpError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _SquareIcon(icon: Icons.arrow_back, onTap: onBack),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: hasWarpError ? const Color(0xFFFF6B6B) : accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hasWarpError ? 'CROP UNAVAILABLE' : 'CAPTURED',
                      style: _mono(
                        size: 10,
                        color: hasWarpError ? const Color(0xFFFF6B6B) : accent,
                        weight: FontWeight.w700,
                        letterSpacing: 0.28,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  hasWarpError ? 'Needs a nudge' : 'Scan result',
                  style: _serif(size: 22),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SquareIcon extends StatelessWidget {
  const _SquareIcon({required this.icon, required this.onTap});
  final IconData icon;
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
          color: _kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
        ),
        child: Icon(icon, color: _kTextPrimary, size: 18),
      ),
    );
  }
}

// ---- preview card ----------------------------------------------------

class _PreviewCard extends StatefulWidget {
  const _PreviewCard({required this.path, required this.accent});
  final String path;
  final Color accent;
  @override
  State<_PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<_PreviewCard> {
  Future<Size>? _sizeFuture;
  String? _resolvedPath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolvedPath != widget.path) {
      _resolvedPath = widget.path;
      _sizeFuture = _decodeSize(File(widget.path));
    }
  }

  Future<Size> _decodeSize(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width.toDouble();
    final h = frame.image.height.toDouble();
    frame.image.dispose();
    codec.dispose();
    return Size(w, h);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorder),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: FutureBuilder<Size>(
                future: _sizeFuture,
                builder: (context, snap) {
                  final img = Image.file(
                    File(widget.path),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  );
                  final size = snap.data;
                  if (size == null) return img;
                  final turns = size.width > size.height ? 1 : 0;
                  return RotatedBox(quarterTurns: turns, child: img);
                },
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _CornerFrame(color: widget.accent)),
            ),
          ),
          Positioned(
            top: 16,
            left: 20,
            child: Text(
              'CROPPED',
              style: _mono(
                size: 9,
                color: widget.accent,
                weight: FontWeight.w700,
                letterSpacing: 0.28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerFrame extends CustomPainter {
  _CornerFrame({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    const len = 18.0;
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.square;
    void corner(Offset o, Offset dx, Offset dy) {
      canvas.drawLine(o, o + dx, p);
      canvas.drawLine(o, o + dy, p);
    }

    corner(Offset.zero, const Offset(len, 0), const Offset(0, len));
    corner(Offset(size.width, 0), const Offset(-len, 0), const Offset(0, len));
    corner(Offset(0, size.height), const Offset(len, 0), const Offset(0, -len));
    corner(Offset(size.width, size.height), const Offset(-len, 0),
        const Offset(0, -len));
  }

  @override
  bool shouldRepaint(covariant _CornerFrame old) => old.color != color;
}

// ---- empty state -----------------------------------------------------

class _Empty extends StatelessWidget {
  const _Empty({required this.hasWarpError, required this.accent});
  final bool hasWarpError;
  final Color accent;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CROP UNAVAILABLE',
            style: _mono(
              size: 10,
              color: accent,
              weight: FontWeight.w700,
              letterSpacing: 0.28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            hasWarpError
                ? 'The detected corners could not be warped into a flat document. Tap “Edit corners” to nudge them by hand, or retake the photo.'
                : 'No cropped output was produced for this capture.',
            style: _serif(size: 18, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ---- actions ---------------------------------------------------------

class _Actions extends StatelessWidget {
  const _Actions({
    required this.accent,
    required this.busy,
    required this.onRetake,
    required this.onEditCorners,
    required this.onOcr,
    required this.onUse,
  });
  final Color accent;
  final bool busy;
  final VoidCallback onRetake;
  final VoidCallback onEditCorners;
  final VoidCallback? onOcr;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, mediaPadding + 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kBorderHairline)),
      ),
      child: Row(
        children: [
          _Ghost(icon: Icons.refresh, onTap: onRetake),
          const SizedBox(width: 10),
          _Ghost(icon: Icons.crop, onTap: onEditCorners),
          if (onOcr != null) ...[
            const SizedBox(width: 10),
            _Ghost(icon: Icons.text_fields, onTap: busy ? null : onOcr!),
          ],
          const Spacer(),
          _Primary(accent: accent, onTap: onUse, busy: busy),
        ],
      ),
    );
  }
}

class _Ghost extends StatelessWidget {
  const _Ghost({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _kSurfaceHi,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: enabled ? _kTextSecondary : _kTextDim, size: 16),
          ],
        ),
      ),
    );
  }
}

class _Primary extends StatelessWidget {
  const _Primary({
    required this.accent,
    required this.onTap,
    required this.busy,
  });
  final Color accent;
  final VoidCallback onTap;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: busy ? _kTextDim : accent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: busy
              ? null
              : [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: const Icon(Icons.arrow_forward, color: _kInk, size: 16),
      ),
    );
  }
}
