import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../quad.dart';

typedef CornerHandleBuilder = Widget Function(BuildContext context);
typedef EditCornersButtonBuilder = Widget Function(
    BuildContext context, VoidCallback onTap, String label);

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
  });

  /// File path to the raw uncropped image.
  final String imagePath;

  /// Initial quad in raw image pixel coordinates.
  final Quad initialQuad;

  /// Raw image pixel size.
  final Size imageSize;

  /// Called when the user saves. Receives final quad in raw image pixel coords.
  /// Implementer typically calls `controller.warpImage(rawPath, finalQuad)`.
  /// Return the path of the new warped image.
  final Future<String> Function(Quad finalQuad) onSave;

  final VoidCallback? onCancel;
  final CornerHandleBuilder? handleBuilder;
  final EditCornersButtonBuilder? buttonBuilder;
  final Color lineColor;
  final double lineWidth;
  final Color surroundColor;
  final double handleRadius;
  final String title;

  @override
  State<EditCornersScreen> createState() => _EditCornersScreenState();
}

class _EditCornersScreenState extends State<EditCornersScreen> {
  late Quad _quad = widget.initialQuad;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed:
                widget.onCancel ?? () => Navigator.of(context).maybePop(),
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
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _button(context, 'Reset',
                          () => setState(() => _quad = widget.initialQuad)),
                      _button(context, _saving ? 'Saving…' : 'Save', _onSave),
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
        onPressed: _saving ? null : onTap, child: Text(label));
  }

  Future<void> _onSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_quad);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
        onPanUpdate: (details) {
          setState(() {
            final newWidgetPos = widgetPos + details.delta;
            final clamped = Offset(
              newWidgetPos.dx.clamp(
                  fit.dstOffset.dx, fit.dstOffset.dx + fit.dstSize.width),
              newWidgetPos.dy.clamp(
                  fit.dstOffset.dy, fit.dstOffset.dy + fit.dstSize.height),
            );
            setPoint(fit.widgetToImage(clamped));
          });
        },
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
