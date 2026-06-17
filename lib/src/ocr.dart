import 'dart:ui';

/// Structured result of on-device text recognition (OCR) over an image.
///
/// Produced by `DoclensController.recognizeText` /
/// `DoclensPlatform.instance.recognizeText`. Recognition runs entirely
/// on-device using the OS text APIs already present on each platform — Apple
/// Vision's `VNRecognizeTextRequest` on iOS and Play-services ML Kit text
/// recognition on Android — so **no model is bundled** (the Android model is
/// delivered on demand by Google Play services, exactly like the OS-native
/// scanner).
///
/// Script coverage follows the underlying recogniser: Android uses ML Kit's
/// default **Latin-script** recogniser, while iOS Vision recognises the full
/// set of languages it ships with. For non-Latin scripts on Android, run a
/// dedicated ML Kit script model on [ScanResult.croppedImagePath] yourself.
///
/// All bounding boxes are in the recognised image's **pixel** coordinates with
/// the origin at the top-left (the same convention as [ScanResult.detectedQuad]
/// in raw image pixels). Use [imageSize] to map boxes onto a scaled preview.
class OcrResult {
  const OcrResult({
    required this.text,
    required this.blocks,
    required this.imageSize,
  });

  /// The full recognised text, with [blocks] joined by newlines in reading
  /// order. Empty when nothing was recognised.
  final String text;

  /// The recognised text blocks (paragraph-ish groupings on Android; one per
  /// recognised line on iOS, which has no native block concept). Each block
  /// carries its own [OcrBlock.lines].
  final List<OcrBlock> blocks;

  /// Pixel size of the image the [OcrBlock.boundingBox] / [OcrLine.boundingBox]
  /// coordinates are expressed in.
  final Size imageSize;

  /// `true` when no text was recognised (blank/graphical page, or the
  /// recogniser was unavailable). [text] is empty and [blocks] is empty.
  bool get isEmpty => blocks.isEmpty;

  bool get isNotEmpty => blocks.isNotEmpty;

  /// Every recognised line across all [blocks], in order.
  List<OcrLine> get lines => [for (final b in blocks) ...b.lines];

  static OcrResult fromMap(Map<dynamic, dynamic> m) {
    final sizeRaw = m['imageSize'];
    final size = (sizeRaw is List && sizeRaw.length >= 2)
        ? Size((sizeRaw[0] as num).toDouble(), (sizeRaw[1] as num).toDouble())
        : Size.zero;
    final blocksRaw = m['blocks'];
    final blocks = <OcrBlock>[
      if (blocksRaw is List)
        for (final b in blocksRaw)
          if (b is Map) OcrBlock.fromMap(b),
    ];
    return OcrResult(
      text: (m['text'] as String?) ?? '',
      blocks: blocks,
      imageSize: size,
    );
  }
}

/// A block of recognised text — a paragraph-like grouping of [lines].
class OcrBlock {
  const OcrBlock({
    required this.text,
    required this.boundingBox,
    required this.lines,
    this.recognizedLanguage,
  });

  /// The block's text, lines joined by newlines.
  final String text;

  /// Axis-aligned bounding box in image pixel coordinates (origin top-left).
  final Rect boundingBox;

  /// The lines that make up this block, in reading order.
  final List<OcrLine> lines;

  /// BCP-47 language tag the platform guessed for this block (e.g. `en`), when
  /// available. `null` on iOS, which does not report a per-block language.
  final String? recognizedLanguage;

  static OcrBlock fromMap(Map<dynamic, dynamic> m) {
    final linesRaw = m['lines'];
    return OcrBlock(
      text: (m['text'] as String?) ?? '',
      boundingBox: _rectFromList(m['boundingBox']),
      recognizedLanguage: m['recognizedLanguage'] as String?,
      lines: [
        if (linesRaw is List)
          for (final l in linesRaw)
            if (l is Map) OcrLine.fromMap(l),
      ],
    );
  }
}

/// A single recognised line of text.
class OcrLine {
  const OcrLine({
    required this.text,
    required this.boundingBox,
    this.confidence,
  });

  final String text;

  /// Axis-aligned bounding box in image pixel coordinates (origin top-left).
  final Rect boundingBox;

  /// Recogniser confidence in `[0, 1]`, or `null` when the platform did not
  /// report one for this line.
  final double? confidence;

  static OcrLine fromMap(Map<dynamic, dynamic> m) {
    final conf = m['confidence'];
    return OcrLine(
      text: (m['text'] as String?) ?? '',
      boundingBox: _rectFromList(m['boundingBox']),
      confidence: conf == null ? null : (conf as num).toDouble(),
    );
  }
}

/// Decode a `[left, top, width, height]` list into a [Rect]. Returns
/// [Rect.zero] for malformed input.
Rect _rectFromList(Object? raw) {
  if (raw is List && raw.length >= 4) {
    return Rect.fromLTWH(
      (raw[0] as num).toDouble(),
      (raw[1] as num).toDouble(),
      (raw[2] as num).toDouble(),
      (raw[3] as num).toDouble(),
    );
  }
  return Rect.zero;
}
