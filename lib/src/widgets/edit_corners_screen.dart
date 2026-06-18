import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../quad.dart';

typedef CornerHandleBuilder = Widget Function(BuildContext context);
typedef EditCornersButtonBuilder = Widget Function(
    BuildContext context, VoidCallback onTap, String label);

/// Builds a custom magnifier loupe shown while a corner is dragged.
///
/// The returned widget is laid out in a [magnifierSize]×[magnifierSize] box
/// positioned to dodge the finger; size it to fill that box. Return `null` to
/// fall back to the bundled loupe for the current drag.
typedef MagnifierBuilder = Widget? Function(
    BuildContext context, MagnifierDetails details);

/// Everything needed to render a magnifier loupe for the active corner.
class MagnifierDetails {
  const MagnifierDetails({
    required this.image,
    required this.imageSize,
    required this.imagePoint,
    required this.quad,
    required this.size,
    required this.scale,
  });

  /// The decoded full-resolution source image to sample from.
  final ui.Image image;

  /// Logical pixel size the [quad] and [imagePoint] coordinates live in. The
  /// decoded [image] may be a different resolution; map with
  /// `image.width / imageSize.width` to find source pixels.
  final Size imageSize;

  /// The active corner's position, in [imageSize] coordinates.
  final Offset imagePoint;

  /// The current quad, in [imageSize] coordinates.
  final Quad quad;

  /// Diameter of the loupe box in logical pixels.
  final double size;

  /// Requested zoom factor.
  final double scale;
}

/// Helper screen for letting users adjust the 4 corners of a detected document.
///
/// Layout, handles, lines, and buttons are all overridable via builders.
/// Coordinates flow in raw image pixel space; the widget handles the
/// image-to-widget transform automatically.
class EditCornersScreen extends StatefulWidget {
  const EditCornersScreen({
    super.key,
    required this.imagePath,
    required this.initialQuad,
    required this.imageSize,
    required this.onSave,
    this.onCancel,
    this.handleBuilder,
    this.buttonBuilder,
    this.lineColor = Colors.white,
    this.lineWidth = 2.0,
    this.surroundColor = const Color(0x99000000),
    this.handleRadius = 28.0,
    this.title = 'Adjust corners',
    this.resetLabel = 'Reset',
    this.saveLabel = 'Continue',
    this.savingLabel = 'Saving…',
    this.buttonStyle,
    this.buttonTextStyle,
    this.showMagnifier = true,
    this.magnifierSize = 112.0,
    this.magnifierScale = 1.2,
    this.magnifierBuilder,
  });

  /// File path to the raw uncropped image.
  final String imagePath;

  /// Initial quad in raw image pixel coordinates.
  final Quad initialQuad;

  /// Raw image pixel size.
  final Size imageSize;

  /// Called when the user saves. Receives final quad in raw image pixel coords.
  /// Implementer typically calls `controller.warpImage(rawPath, finalQuad)`
  /// and returns the path of the new warped image.
  ///
  /// Do **not** pop the route from this callback — [EditCornersScreen] owns
  /// the pop and dismisses itself with the returned path once `onSave`
  /// completes. Popping here as well re-enters the Navigator mid-pop and
  /// trips the framework's `!_debugLocked` assertion.
  final Future<String> Function(Quad finalQuad) onSave;

  final VoidCallback? onCancel;
  final CornerHandleBuilder? handleBuilder;
  final EditCornersButtonBuilder? buttonBuilder;
  final Color lineColor;
  final double lineWidth;
  final Color surroundColor;
  final double handleRadius;
  final String title;
  final String resetLabel;
  final String saveLabel;
  final String savingLabel;
  final ButtonStyle? buttonStyle;
  final TextStyle? buttonTextStyle;

  /// Show a magnifying loupe while a corner is being dragged, so the finger
  /// doesn't hide the pixel being placed.
  final bool showMagnifier;

  /// Diameter of the loupe in logical pixels.
  final double magnifierSize;

  /// How much the region under the corner is zoomed inside the loupe.
  final double magnifierScale;

  /// Optional override for the loupe widget. When null (the default), a bundled
  /// loupe is rendered. Return null from the builder to fall back to it.
  final MagnifierBuilder? magnifierBuilder;

  @override
  State<EditCornersScreen> createState() => _EditCornersScreenState();
}

class _EditCornersScreenState extends State<EditCornersScreen> {
  late Quad _quad = widget.initialQuad;
  bool _saving = false;

  /// Decoded source image, used to sample full-resolution pixels into the
  /// loupe. Null until [_decodeImage] completes.
  ui.Image? _sourceImage;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  /// Image-space position of the corner currently being dragged, and the
  /// widget-space point of the finger. Both null when no drag is active.
  Offset? _activeImagePoint;
  Offset? _activeWidgetPoint;

  @override
  void initState() {
    super.initState();
    if (widget.showMagnifier) _decodeImage();
  }

  @override
  void dispose() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _sourceImage?.dispose();
    super.dispose();
  }

  void _decodeImage() {
    final provider = FileImage(File(widget.imagePath));
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener((info, _) {
      if (!mounted) {
        info.image.dispose();
        return;
      }
      setState(() => _sourceImage = info.image);
    }, onError: (_, __) {
      // Loupe is a non-critical enhancement; fail silently and let editing
      // continue without it.
    });
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  /// Dismiss the screen without saving. Pops directly (not via maybePop,
  /// which PopScope's canPop:false would swallow). A no-op while a warp is
  /// in flight so we don't pop mid-save.
  void _cancel() {
    if (_saving) return;
    if (widget.onCancel != null) {
      widget.onCancel!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block the system back gesture from bypassing the cancel/save flow,
      // but route an intentional system-back into _cancel so it still works.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _cancel,
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            // Inset the fittable area so handles near the photo edge sit
            // comfortably away from the screen edges — much easier to grab
            // a top-left handle when the image isn't flush with the bezel.
            // The handle clamping in `_buildHandle` uses `fit.dstOffset` /
            // `fit.dstSize`, so the inset is honoured automatically.
            const horizontalInset = 24.0;
            const topInset = 12.0;
            const bottomInset = 96.0; // room for the Reset / Save row
            final inner = Size(
              math.max(0, constraints.maxWidth - horizontalInset * 2),
              math.max(0, constraints.maxHeight - topInset - bottomInset),
            );
            final innerFit = _fitImage(widget.imageSize, inner);
            // Translate the fit back into widget coordinates.
            final fit = _ImageFit(
              dstOffset: Offset(
                innerFit.dstOffset.dx + horizontalInset,
                innerFit.dstOffset.dy + topInset,
              ),
              dstSize: innerFit.dstSize,
              scaleX: innerFit.scaleX,
              scaleY: innerFit.scaleY,
            );
            return Stack(
              children: [
                Positioned(
                  left: fit.dstOffset.dx,
                  top: fit.dstOffset.dy,
                  width: fit.dstSize.width,
                  height: fit.dstSize.height,
                  child: Image.file(File(widget.imagePath), fit: BoxFit.fill),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CornerLinesPainter(
                      quad: _quad,
                      fit: fit,
                      lineColor: widget.lineColor,
                      lineWidth: widget.lineWidth,
                      surroundColor: widget.surroundColor,
                    ),
                  ),
                ),
                ..._buildHandles(fit, constraints.biggest),
                if (widget.showMagnifier)
                  ..._buildMagnifier(fit, constraints.biggest),
                Positioned(
                  bottom: 24,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      Expanded(child: _button(context, widget.resetLabel,
                          () => setState(() => _quad = widget.initialQuad))),
                      const SizedBox(width: 12),
                      Expanded(child: _button(context, _saving ? widget.savingLabel : widget.saveLabel, _onSave)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _button(BuildContext context, String label, VoidCallback onTap) {
    if (widget.buttonBuilder != null) {
      return widget.buttonBuilder!(context, onTap, label);
    }
    return ElevatedButton(
      onPressed: _saving ? null : onTap,
      style: widget.buttonStyle,
      child: Text(label, style: widget.buttonTextStyle),
    );
  }

  Future<void> _onSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final warpedPath = await widget.onSave(_quad);
      if (mounted) Navigator.of(context).pop(warpedPath);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clearActiveHandle() {
    if (_activeImagePoint == null && _activeWidgetPoint == null) return;
    setState(() {
      _activeImagePoint = null;
      _activeWidgetPoint = null;
    });
  }

  /// The loupe: a circular window showing the full-resolution region under the
  /// active corner, zoomed, with a crosshair on the exact point. Positioned to
  /// dodge the finger — above the handle, flipping below when near the top.
  List<Widget> _buildMagnifier(_ImageFit fit, Size widgetSize) {
    final image = _sourceImage;
    final imagePoint = _activeImagePoint;
    final widgetPoint = _activeWidgetPoint;
    if (image == null || imagePoint == null || widgetPoint == null) {
      return const [];
    }

    final d = widget.magnifierSize;
    const gap = 24.0; // space between finger and loupe
    const margin = 8.0; // keep the loupe on-screen

    // Prefer placing the loupe above the finger; flip below if it would clip
    // the top of the screen.
    double top = widgetPoint.dy - gap - d;
    if (top < margin) top = widgetPoint.dy + gap;

    double left = widgetPoint.dx - d / 2;
    left = left.clamp(margin, math.max(margin, widgetSize.width - d - margin));

    final custom = widget.magnifierBuilder?.call(
      context,
      MagnifierDetails(
        image: image,
        imageSize: widget.imageSize,
        imagePoint: imagePoint,
        quad: _quad,
        size: d,
        scale: widget.magnifierScale,
      ),
    );

    final loupe = custom ??
        CustomPaint(
          painter: _MagnifierPainter(
            image: image,
            imageSize: widget.imageSize,
            imagePoint: imagePoint,
            scale: widget.magnifierScale,
            quad: _quad,
            lineColor: widget.lineColor,
            lineWidth: widget.lineWidth,
          ),
        );

    return [
      Positioned(
        left: left,
        top: top,
        width: d,
        height: d,
        child: IgnorePointer(child: loupe),
      ),
    ];
  }

  List<Widget> _buildHandles(_ImageFit fit, Size widgetSize) {
    final pts = [
      (
        _quad.topLeft,
        (Offset p) => _quad = Quad(
              topLeft: p,
              topRight: _quad.topRight,
              bottomRight: _quad.bottomRight,
              bottomLeft: _quad.bottomLeft,
            )
      ),
      (
        _quad.topRight,
        (Offset p) => _quad = Quad(
              topLeft: _quad.topLeft,
              topRight: p,
              bottomRight: _quad.bottomRight,
              bottomLeft: _quad.bottomLeft,
            )
      ),
      (
        _quad.bottomRight,
        (Offset p) => _quad = Quad(
              topLeft: _quad.topLeft,
              topRight: _quad.topRight,
              bottomRight: p,
              bottomLeft: _quad.bottomLeft,
            )
      ),
      (
        _quad.bottomLeft,
        (Offset p) => _quad = Quad(
              topLeft: _quad.topLeft,
              topRight: _quad.topRight,
              bottomRight: _quad.bottomRight,
              bottomLeft: p,
            )
      ),
    ];
    return [
      for (final (point, setter) in pts)
        _buildHandle(point, setter, fit, widgetSize),
    ];
  }

  Widget _buildHandle(
    Offset imagePoint,
    void Function(Offset newImagePoint) setPoint,
    _ImageFit fit,
    Size widgetSize,
  ) {
    final widgetPos = fit.imageToWidget(imagePoint);
    final r = widget.handleRadius;
    return Positioned(
      left: widgetPos.dx - r,
      top: widgetPos.dy - r,
      child: GestureDetector(
        onPanDown: (_) {
          if (!widget.showMagnifier) return;
          setState(() {
            _activeImagePoint = imagePoint;
            _activeWidgetPoint = widgetPos;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            final newWidgetPos = widgetPos + details.delta;
            final clamped = Offset(
              newWidgetPos.dx.clamp(
                  fit.dstOffset.dx, fit.dstOffset.dx + fit.dstSize.width),
              newWidgetPos.dy.clamp(
                  fit.dstOffset.dy, fit.dstOffset.dy + fit.dstSize.height),
            );
            final newImagePoint = fit.widgetToImage(clamped);
            setPoint(newImagePoint);
            if (widget.showMagnifier) {
              _activeImagePoint = newImagePoint;
              _activeWidgetPoint = clamped;
            }
          });
        },
        onPanEnd: (_) => _clearActiveHandle(),
        onPanCancel: _clearActiveHandle,
        child: widget.handleBuilder?.call(context) ??
            Container(
              width: r * 2,
              height: r * 2,
              alignment: Alignment.center,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.9),
                  border: Border.all(color: widget.lineColor, width: 2),
                ),
              ),
            ),
      ),
    );
  }

  _ImageFit _fitImage(Size image, Size widgetSize) {
    final scale = math.min(
      widgetSize.width / image.width,
      widgetSize.height / image.height,
    );
    final dst = Size(image.width * scale, image.height * scale);
    final off = Offset(
      (widgetSize.width - dst.width) / 2,
      (widgetSize.height - dst.height) / 2,
    );
    return _ImageFit(
      dstOffset: off,
      dstSize: dst,
      scaleX: dst.width / image.width,
      scaleY: dst.height / image.height,
    );
  }
}

class _ImageFit {
  const _ImageFit({
    required this.dstOffset,
    required this.dstSize,
    required this.scaleX,
    required this.scaleY,
  });
  final Offset dstOffset;
  final Size dstSize;
  final double scaleX;
  final double scaleY;

  Offset imageToWidget(Offset p) =>
      Offset(dstOffset.dx + p.dx * scaleX, dstOffset.dy + p.dy * scaleY);

  Offset widgetToImage(Offset p) => Offset(
        (p.dx - dstOffset.dx) / scaleX,
        (p.dy - dstOffset.dy) / scaleY,
      );
}

class _CornerLinesPainter extends CustomPainter {
  _CornerLinesPainter({
    required this.quad,
    required this.fit,
    required this.lineColor,
    required this.lineWidth,
    required this.surroundColor,
  });
  final Quad quad;
  final _ImageFit fit;
  final Color lineColor;
  final double lineWidth;
  final Color surroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final tl = fit.imageToWidget(quad.topLeft);
    final tr = fit.imageToWidget(quad.topRight);
    final br = fit.imageToWidget(quad.bottomRight);
    final bl = fit.imageToWidget(quad.bottomLeft);

    final quadPath = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();

    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final dim = Path.combine(ui.PathOperation.difference, outer, quadPath);
    canvas.drawPath(dim, Paint()..color = surroundColor);

    canvas.drawPath(
      quadPath,
      Paint()
        ..color = lineColor
        ..strokeWidth = lineWidth
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _CornerLinesPainter old) =>
      old.quad != quad ||
      old.lineColor != lineColor ||
      old.surroundColor != surroundColor;
}

/// Paints the magnifier loupe: a circular, zoomed crop of the full-resolution
/// source image centered on the active corner, with the quad edges and a
/// crosshair drawn on top so the user can place the corner precisely.
class _MagnifierPainter extends CustomPainter {
  _MagnifierPainter({
    required this.image,
    required this.imageSize,
    required this.imagePoint,
    required this.scale,
    required this.quad,
    required this.lineColor,
    required this.lineWidth,
  });

  final ui.Image image;

  /// Logical pixel size the [Quad] coordinates live in. The decoded [image]
  /// may be a different resolution (e.g. an EXIF-downscaled cache entry), so we
  /// map quad/point coords into image pixels via this ratio.
  final Size imageSize;

  /// The corner position, in [imageSize] coordinates.
  final Offset imagePoint;
  final double scale;
  final Quad quad;
  final Color lineColor;
  final double lineWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final clip = Path()..addOval(Rect.fromCircle(center: center, radius: size.width / 2));
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawColor(Colors.black, BlendMode.src);

    // Ratio between the decoded image's actual pixels and the quad coordinate
    // space, so the loupe samples the right region regardless of cache scaling.
    final pxRatio = image.width / imageSize.width;

    // loupe-space = center + (imageCoord - imagePoint) * scale
    // Invert to find which source rect fills the loupe.
    final halfImageCoords = (size.width / 2) / scale;
    final src = Rect.fromCenter(
      center: Offset(imagePoint.dx * pxRatio, imagePoint.dy * pxRatio),
      width: halfImageCoords * 2 * pxRatio,
      height: halfImageCoords * 2 * pxRatio,
    );
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );

    // Quad edges, mapped from image-space into loupe-space.
    Offset toLoupe(Offset p) => center + (p - imagePoint) * scale;
    final tl = toLoupe(quad.topLeft);
    final tr = toLoupe(quad.topRight);
    final br = toLoupe(quad.bottomRight);
    final bl = toLoupe(quad.bottomLeft);
    final edges = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();
    canvas.drawPath(
      edges,
      Paint()
        ..color = lineColor
        ..strokeWidth = lineWidth
        ..style = PaintingStyle.stroke,
    );

    canvas.restore();

    // Rim.
    canvas.drawCircle(
      center,
      size.width / 2 - 1,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _MagnifierPainter old) =>
      old.image != image ||
      old.imagePoint != imagePoint ||
      old.scale != scale ||
      old.quad != quad;
}
