import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =====================================================================
//  Reusable OCR result sheet — shared by every example flow.
//
//  `showOcrSheet(context, imagePath)` opens a modal that runs the
//  package's on-device `recognizeText` itself (showing a spinner while it
//  works), then renders the transcript: full text with copy-to-clipboard,
//  a per-line breakdown with confidence, and clean empty / error states.
//
//  It is theme-aware (light "paper" by default, `dark: true` for the
//  branded / native dark surfaces) and tintable via `accent`, so the one
//  component matches each style's identity.
// =====================================================================

/// Open the OCR sheet for the image at [imagePath]. The sheet runs
/// `DoclensPlatform.instance.recognizeText` internally — callers just point it
/// at a file (typically a `ScanResult.croppedImagePath`).
Future<void> showOcrSheet(
  BuildContext context,
  String imagePath, {
  Color accent = const Color(0xFFB5482E),
  bool dark = false,
}) {
  final palette = dark ? _OcrPalette.dark(accent) : _OcrPalette.light(accent);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: palette.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _OcrSheet(imagePath: imagePath, palette: palette),
  );
}

class _OcrPalette {
  const _OcrPalette({
    required this.accent,
    required this.background,
    required this.surface,
    required this.border,
    required this.onSurface,
    required this.onSurfaceDim,
  });

  factory _OcrPalette.light(Color accent) => _OcrPalette(
        accent: accent,
        background: const Color(0xFFF4F0E8),
        surface: const Color(0xFFFAF7F0),
        border: const Color(0x1A1A1815),
        onSurface: const Color(0xFF1A1815),
        onSurfaceDim: const Color(0xFF8E8A83),
      );

  factory _OcrPalette.dark(Color accent) => _OcrPalette(
        accent: accent,
        background: const Color(0xFF13151A),
        surface: const Color(0xFF1A1D24),
        border: const Color(0x22FFFFFF),
        onSurface: const Color(0xFFF4F4F2),
        onSurfaceDim: const Color(0xFF8C8E93),
      );

  final Color accent;
  final Color background;
  final Color surface;
  final Color border;
  final Color onSurface;
  final Color onSurfaceDim;
}

const _kMono = <String>['SF Mono', 'Menlo', 'Roboto Mono', 'monospace'];

TextStyle _mono({
  required Color color,
  double size = 11,
  FontWeight weight = FontWeight.w400,
  double letterSpacing = 0.12,
  double height = 1.4,
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

class _OcrSheet extends StatefulWidget {
  const _OcrSheet({required this.imagePath, required this.palette});
  final String imagePath;
  final _OcrPalette palette;

  @override
  State<_OcrSheet> createState() => _OcrSheetState();
}

class _OcrSheetState extends State<_OcrSheet> {
  OcrResult? _ocr;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _recognize();
  }

  Future<void> _recognize() async {
    try {
      final ocr =
          await DoclensPlatform.instance.recognizeText(imagePath: widget.imagePath);
      if (!mounted) return;
      setState(() {
        _ocr = ocr;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final ocr = _ocr;
    final hasText = !_loading && _error == null && ocr != null && ocr.isNotEmpty;

    final String eyebrow;
    if (_loading) {
      eyebrow = 'RECOGNISING…';
    } else if (_error != null) {
      eyebrow = 'OCR FAILED';
    } else if (!hasText) {
      eyebrow = 'NO TEXT FOUND';
    } else {
      final n = ocr.lines.length;
      eyebrow = '$n LINE${n == 1 ? '' : 'S'} RECOGNISED';
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: p.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow,
                        style: _mono(
                          color: p.accent,
                          size: 10,
                          weight: FontWeight.w700,
                          letterSpacing: 0.26,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Recognised text',
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontFamilyFallback: const ['Iowan Old Style', 'serif'],
                          fontStyle: FontStyle.italic,
                          fontSize: 22,
                          color: p.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasText) _CopyButton(text: ocr.text, palette: p),
              ],
            ),
            const SizedBox(height: 14),
            Flexible(child: _body(hasText: hasText, ocr: ocr)),
          ],
        ),
      ),
    );
  }

  Widget _body({required bool hasText, required OcrResult? ocr}) {
    final p = widget.palette;
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
          ),
        ),
      );
    }
    if (_error != null) {
      return _message('$_error');
    }
    if (!hasText) {
      return _message(
        'The recogniser did not find confident text on this page. Try the '
        'Black & white enhancement for faint print.',
      );
    }
    return _OcrLineList(ocr: ocr!, palette: p);
  }

  Widget _message(String text) {
    final p = widget.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Text(text, style: _mono(color: p.onSurface, size: 12, height: 1.5)),
    );
  }
}

class _OcrLineList extends StatelessWidget {
  const _OcrLineList({required this.ocr, required this.palette});
  final OcrResult ocr;
  final _OcrPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final maxHeight = MediaQuery.of(context).size.height * 0.5;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.border),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          itemCount: ocr.lines.length,
          separatorBuilder: (_, __) => Divider(height: 14, color: p.border),
          itemBuilder: (context, i) {
            final line = ocr.lines[i];
            final conf = line.confidence;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    line.text,
                    style: _mono(color: p.onSurface, size: 12.5),
                  ),
                ),
                if (conf != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    '${(conf * 100).round()}%',
                    style: _mono(
                      color: p.onSurfaceDim,
                      size: 10,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text, required this.palette});
  final String text;
  final _OcrPalette palette;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _copy,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _copied ? p.accent : p.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _copied ? p.accent : p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? Icons.check : Icons.copy,
              size: 13,
              color: _copied ? p.background : p.onSurface,
            ),
            const SizedBox(width: 6),
            Text(
              _copied ? 'COPIED' : 'COPY',
              style: _mono(
                color: _copied ? p.background : p.onSurface,
                size: 10,
                weight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
