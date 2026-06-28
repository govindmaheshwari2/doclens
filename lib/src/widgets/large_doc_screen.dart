import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../quad.dart';
import '../large_doc/large_doc_aligner.dart';
import '../large_doc/large_doc_canvas.dart';
import '../large_doc/large_doc_merger.dart';
import '../large_doc/large_doc_session.dart';
import 'doclens_view.dart';

/// Builds the `+` affordance shown on an open [LargeDocEdge] of the composite.
typedef PlusButtonBuilder = Widget Function(
    BuildContext context, LargeDocEdge edge, VoidCallback onTap);

/// Builds the small "document so far" map shown during review.
typedef MiniviewBuilder = Widget Function(
    BuildContext context, LargeDocCanvas canvas);

/// Builds the coaching hint shown while a fragment is being captured.
typedef LargeDocHintBuilder = Widget Function(BuildContext context, LargeDocEdge? edge);

/// A multi-shot scanner for documents too large to fit in a single frame.
///
/// The user captures one fragment ("piece"), then taps a `+` on any edge of
/// the growing composite to shoot the adjacent piece — lining it up against a
/// translucent **overlap ghost** of the previous piece. A **miniview** shows
/// the whole document taking shape. On *Done* the pieces are stitched into one
/// image and returned.
///
/// Like the rest of doclens, every piece of chrome is overridable: pass any
/// of the `*Builder` callbacks (or the colours) to fully rebrand the screen.
/// Pass nothing and you get a clean monochrome default. The capture pipeline,
/// state machine ([LargeDocSession]), grid model ([LargeDocCanvas]), alignment
/// ([LargeDocAligner]) and stitching ([LargeDocMerger]) are all injectable too.
class DoclensLargeDocScreen extends StatefulWidget {
  const DoclensLargeDocScreen({
    super.key,
    this.config = const ScannerConfig(),
    this.aligner = const ManualPlacementAligner(),
    this.merger = const CanvasLargeDocMerger(),
    this.accentColor = const Color(0xFF000000),
    this.overlapFraction = 0.15,
    this.ghostOpacity = 0.4,
    this.plusButtonBuilder,
    this.miniviewBuilder,
    this.hintBuilder,
    this.captureButtonBuilder,
    this.title = 'Scan a large document',
  });

  final ScannerConfig config;
  final LargeDocAligner aligner;
  final LargeDocMerger merger;

  /// Accent used by the default chrome (plus buttons, Done, miniview frame).
  final Color accentColor;

  /// How much of the previous piece is shown as the alignment ghost, as a
  /// fraction of the preview's short edge. Should match the merger's overlap.
  final double overlapFraction;

  /// Opacity of the overlap ghost strip (`0`–`1`).
  final double ghostOpacity;

  final PlusButtonBuilder? plusButtonBuilder;
  final MiniviewBuilder? miniviewBuilder;
  final LargeDocHintBuilder? hintBuilder;
  final CaptureButtonBuilder? captureButtonBuilder;
  final String title;

  /// Pushes the screen and resolves with the merged image path, or `null`
  /// if the user backed out without finishing.
  static Future<String?> scan(
    BuildContext context, {
    ScannerConfig config = const ScannerConfig(),
    LargeDocAligner aligner = const ManualPlacementAligner(),
    LargeDocMerger merger = const CanvasLargeDocMerger(),
    Color accentColor = const Color(0xFF000000),
    double overlapFraction = 0.15,
    double ghostOpacity = 0.4,
    PlusButtonBuilder? plusButtonBuilder,
    MiniviewBuilder? miniviewBuilder,
    LargeDocHintBuilder? hintBuilder,
    CaptureButtonBuilder? captureButtonBuilder,
    String title = 'Scan a large document',
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => DoclensLargeDocScreen(
          config: config,
          aligner: aligner,
          merger: merger,
          accentColor: accentColor,
          overlapFraction: overlapFraction,
          ghostOpacity: ghostOpacity,
          plusButtonBuilder: plusButtonBuilder,
          miniviewBuilder: miniviewBuilder,
          hintBuilder: hintBuilder,
          captureButtonBuilder: captureButtonBuilder,
          title: title,
        ),
      ),
    );
  }

  @override
  State<DoclensLargeDocScreen> createState() => _DoclensLargeDocScreenState();
}

class _DoclensLargeDocScreenState extends State<DoclensLargeDocScreen> {
  late final DoclensController _controller =
      DoclensController(config: widget.config);
  late final LargeDocSession _session = LargeDocSession(
    aligner: widget.aligner,
    merger: widget.merger.merge,
  );

  /// Latest live document quad (normalized `[0,1]`), used to pin the overlap
  /// ghost to the page the user is framing rather than the whole preview.
  Quad? _liveQuad;
  StreamSubscription<Quad?>? _quadSub;

  @override
  void initState() {
    super.initState();
    _controller.initialize().catchError((Object _) {});
    _quadSub = _controller.quadStream.listen((q) {
      if (mounted) setState(() => _liveQuad = q);
    });
    _session.addListener(_onSession);
  }

  @override
  void dispose() {
    _quadSub?.cancel();
    _session.removeListener(_onSession);
    _controller.dispose();
    _session.dispose();
    super.dispose();
  }

  void _onSession() {
    _syncCamera();
    setState(() {});
  }

  bool _committing = false;
  bool? _cameraLive;

  /// Run the camera only while a fragment is actually being captured. During
  /// review/merge it would keep auto-capturing into a phase with no handler
  /// and burn battery. Tracks the last requested state to avoid spamming
  /// pause/resume on every notification.
  void _syncCamera() {
    if (!_controller.isInitialized) return;
    final live = _session.phase == LargeDocPhase.empty ||
        _session.phase == LargeDocPhase.capturing;
    if (_cameraLive == live) return;
    _cameraLive = live;
    (live ? _controller.resume() : _controller.pause())
        .catchError((Object _) {});
  }

  /// Single entry point for both the manual capture button and auto-capture:
  /// take the cropped (or raw) result into the session.
  Future<void> _onCaptured(ScanResult result) async {
    if (_committing) return;
    // The very first shot starts in `empty`; move it into capturing so the
    // root piece commits through the same path as every later fragment.
    if (_session.phase == LargeDocPhase.empty) _session.beginRootCapture();
    if (_session.phase != LargeDocPhase.capturing) return;
    _committing = true;
    try {
      final path = result.croppedImagePath ?? result.rawImagePath;
      final outcome = await _session.commitCapture(path);
      if (outcome == LargeDocCaptureOutcome.lowConfidence && mounted) {
        _promptRetake();
      }
    } catch (_) {
      if (_session.phase == LargeDocPhase.capturing) _session.cancelCapture();
    } finally {
      _committing = false;
    }
  }

  void _promptRetake() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Couldn't line that edge up"),
        content: const Text(
            'The overlap had too little detail to match automatically. '
            'Retake it, or keep it on your manual alignment.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _session.keepPending();
            },
            child: const Text('Keep anyway'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _session.retakePending();
            },
            child: const Text('Retake'),
          ),
        ],
      ),
    );
  }

  Future<void> _done() async {
    try {
      final path = await _session.merge();
      if (mounted) Navigator.of(context).pop(path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not stitch the pages.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: switch (_session.phase) {
          LargeDocPhase.empty ||
          LargeDocPhase.capturing =>
            _buildCapture(),
          LargeDocPhase.review => _buildReview(),
          LargeDocPhase.merging => const Center(
              child: CircularProgressIndicator(color: Colors.white)),
          LargeDocPhase.done => const SizedBox.shrink(),
        },
      ),
    );
  }

  // ---- capture phase ---------------------------------------------------

  Widget _buildCapture() {
    final ghostEdge = _session.pendingEdge?.opposite;
    final anchor = _session.pendingAnchor;
    return Stack(
      fit: StackFit.expand,
      children: [
        DoclensView(
          controller: _controller,
          overlayBuilder: DoclensView.defaultOverlayBuilder,
          captureButtonBuilder:
              widget.captureButtonBuilder ?? DoclensView.defaultCaptureButton,
          // Routes both the manual button and auto-capture into the session.
          onCapture: _onCaptured,
        ),
        // The overlap ghost: a strip of the anchor piece pinned to the edge
        // the new fragment must continue from.
        if (anchor != null && ghostEdge != null)
          _GhostStrip(
            imagePath: anchor.imagePath,
            edge: ghostEdge,
            fraction: widget.overlapFraction,
            opacity: widget.ghostOpacity,
            liveQuad: _liveQuad,
          ),
        Positioned(
          top: 12,
          left: 8,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () {
              if (_session.phase == LargeDocPhase.capturing &&
                  !_session.canvas.isEmpty) {
                _session.cancelCapture();
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
        ),
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(
            child: widget.hintBuilder?.call(context, _session.pendingEdge) ??
                _DefaultHint(edge: _session.pendingEdge),
          ),
        ),
        if (!_session.canvas.isEmpty)
          Positioned(
            bottom: 24,
            right: 16,
            child: _miniview(),
          ),
      ],
    );
  }

  // ---- review phase ----------------------------------------------------

  Widget _buildReview() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _CompositeBoard(
              canvas: _session.canvas,
              accent: widget.accentColor,
              plusBuilder: widget.plusButtonBuilder ?? _defaultPlus,
              onPlus: (anchor, edge) {
                _session.beginCapture(anchor: anchor, edge: edge);
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _miniview(),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: widget.accentColor),
                onPressed: _done,
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniview() =>
      widget.miniviewBuilder?.call(context, _session.canvas) ??
      _Miniview(canvas: _session.canvas, accent: widget.accentColor);

  Widget _defaultPlus(
          BuildContext context, LargeDocEdge edge, VoidCallback onTap) =>
      _PlusButton(edge: edge, color: widget.accentColor, onTap: onTap);
}

// =====================================================================
//  Default chrome
// =====================================================================

/// Translucent slice of the previous piece, pinned to one edge of the page
/// the user is framing so they can slide the real page under it before
/// shooting.
///
/// When a live document quad is detected, the strip is sized and placed over
/// that quad's bounding box — so the ghost overlays the actual page region and
/// lines up at the same scale, instead of being pinned to the whole preview
/// frame (which includes background the user isn't trying to match). Without a
/// quad it falls back to the full preview edge.
class _GhostStrip extends StatelessWidget {
  const _GhostStrip({
    required this.imagePath,
    required this.edge,
    required this.fraction,
    required this.opacity,
    this.liveQuad,
  });

  final String imagePath;
  final LargeDocEdge edge;
  final double fraction;
  final double opacity;
  final Quad? liveQuad;

  @override
  Widget build(BuildContext context) {
    // Fill the stack, then position the strip ourselves against the page box —
    // the geometry depends on the live quad, which a plain `Positioned` can't
    // express.
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, c) {
            final preview = Size(c.maxWidth, c.maxHeight);
            // Box to pin the ghost against: the live page if detected, else
            // the whole preview.
            final box = _quadBounds(liveQuad, preview) ?? Offset.zero & preview;

            final horizontal =
                edge == LargeDocEdge.left || edge == LargeDocEdge.right;
            final stripW = horizontal ? box.width * fraction : box.width;
            final stripH = horizontal ? box.height : box.height * fraction;
            final left = switch (edge) {
              LargeDocEdge.left || LargeDocEdge.top || LargeDocEdge.bottom =>
                box.left,
              LargeDocEdge.right => box.right - stripW,
            };
            final top = switch (edge) {
              LargeDocEdge.left || LargeDocEdge.right || LargeDocEdge.top =>
                box.top,
              LargeDocEdge.bottom => box.bottom - stripH,
            };

            // Show the matching slice of the anchor image (its far edge meets
            // the seam), so content visually continues across the join. The
            // image fills the whole box, then is clipped to the strip.
            final sliceAlign = switch (edge) {
              LargeDocEdge.left => Alignment.centerRight,
              LargeDocEdge.right => Alignment.centerLeft,
              LargeDocEdge.top => Alignment.bottomCenter,
              LargeDocEdge.bottom => Alignment.topCenter,
            };
            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: stripW,
                  height: stripH,
                  child: Opacity(
                    opacity: opacity,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: sliceAlign,
                        maxWidth: box.width,
                        maxHeight: box.height,
                        child: Image.file(
                          File(imagePath),
                          fit: BoxFit.cover,
                          width: box.width,
                          height: box.height,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Axis-aligned bounding box of [quad] (normalized `[0,1]`) in preview
  /// pixels, or `null` when no quad is available.
  static Rect? _quadBounds(Quad? quad, Size preview) {
    if (quad == null) return null;
    final px = quad.scaleToSize(preview).points;
    var minX = px.first.dx, maxX = px.first.dx;
    var minY = px.first.dy, maxY = px.first.dy;
    for (final p in px) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

class _DefaultHint extends StatelessWidget {
  const _DefaultHint({required this.edge});
  final LargeDocEdge? edge;

  @override
  Widget build(BuildContext context) {
    final text = edge == null
        ? 'Capture the first part of the document'
        : 'Slide the page so it lines up with the faded edge, then capture';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}

/// The review board: occupied grid cells render their piece; open edges of
/// boundary pieces get a `+`.
class _CompositeBoard extends StatelessWidget {
  const _CompositeBoard({
    required this.canvas,
    required this.accent,
    required this.plusBuilder,
    required this.onPlus,
  });

  final LargeDocCanvas canvas;
  final Color accent;
  final PlusButtonBuilder plusBuilder;
  final void Function(LargeDocPiece anchor, LargeDocEdge edge) onPlus;

  @override
  Widget build(BuildContext context) {
    final b = canvas.gridBounds();
    final ext = canvas.gridExtent();
    // Reserve a half-cell margin all around for the `+` buttons.
    return LayoutBuilder(
      builder: (context, c) {
        final cell = (c.maxWidth / (ext.cols + 1))
            .clamp(0.0, c.maxHeight / (ext.rows + 1));
        final boardW = cell * ext.cols;
        final boardH = cell * ext.rows;
        final left = (c.maxWidth - boardW) / 2;
        final top = (c.maxHeight - boardH) / 2;

        double cx(int col) => left + (col - b.minCol) * cell;
        double cy(int row) => top + (row - b.minRow) * cell;

        final children = <Widget>[];
        for (final t in canvas.pieces) {
          children.add(Positioned(
            left: cx(t.col),
            top: cy(t.row),
            width: cell,
            height: cell,
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: Image.file(File(t.imagePath), fit: BoxFit.cover),
            ),
          ));
          for (final edge in canvas.openEdgesOf(t)) {
            final d = edge.delta;
            children.add(Positioned(
              left: cx(t.col) + d.x * cell * 0.5,
              top: cy(t.row) + d.y * cell * 0.5,
              width: cell,
              height: cell,
              child: Center(
                child: plusBuilder(context, edge, () => onPlus(t, edge)),
              ),
            ));
          }
        }
        return Stack(children: children);
      },
    );
  }
}

class _PlusButton extends StatelessWidget {
  const _PlusButton(
      {required this.edge, required this.color, required this.onTap});
  final LargeDocEdge edge;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
        ),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

/// Small live map of the whole document: a shrunk version of the review grid.
class _Miniview extends StatelessWidget {
  const _Miniview({required this.canvas, required this.accent});
  final LargeDocCanvas canvas;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (canvas.isEmpty) return const SizedBox.shrink();
    final b = canvas.gridBounds();
    final ext = canvas.gridExtent();
    const maxSide = 72.0;
    final cell = maxSide / (ext.cols > ext.rows ? ext.cols : ext.rows);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: SizedBox(
        width: ext.cols * cell,
        height: ext.rows * cell,
        child: Stack(
          children: [
            for (final t in canvas.pieces)
              Positioned(
                left: (t.col - b.minCol) * cell,
                top: (t.row - b.minRow) * cell,
                width: cell,
                height: cell,
                child: Padding(
                  padding: const EdgeInsets.all(0.5),
                  child: Image.file(File(t.imagePath), fit: BoxFit.cover),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
