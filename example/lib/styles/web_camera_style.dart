import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

const _kRust = Color(0xFFB5482E);

/// Camera-or-upload scanner for web/desktop, where [DoclensPlatform.supportsLiveScan]
/// is false and there's no native path-based pipeline on web either.
///
/// Live browser camera needs `getUserMedia`, which `image_picker`'s web
/// implementation doesn't use (it just opens a file input, so desktop
/// Chrome/Safari show a plain upload dialog, not a webcam view). The `camera`
/// package's web backend (`camera_web`) does call `getUserMedia`, so this
/// screen tries a real live preview via [CameraController] first; when no
/// camera is found (desktop app builds — `camera_macos`/`camera_windows`
/// aren't in this plugin's platform list — or the user denies permission) it
/// falls back to picking an existing photo. Either way the result is decoded
/// to bytes — never a [dart:io] path — so cropping works on web too, via
/// [_MemoryEditCornersScreen] below (a bytes-based fork of the package's
/// `EditCornersScreen`).
class WebCameraScanner extends StatefulWidget {
  const WebCameraScanner({super.key});

  @override
  State<WebCameraScanner> createState() => _WebCameraScannerState();
}

class _WebCameraScannerState extends State<WebCameraScanner> {
  final _picker = ImagePicker();

  ImageEnhancement _mode = ImageEnhancement.none;
  Uint8List? _resultBytes;
  bool _busy = false;
  String? _error;

  Future<void> _captureOrUpload() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Uint8List? bytes;
      try {
        final cameras = await availableCameras();
        if (cameras.isEmpty) throw StateError('no camera');
        if (!mounted) return;
        bytes = await Navigator.of(context).push<Uint8List>(
          MaterialPageRoute<Uint8List>(
            builder: (_) => _LiveCameraScreen(camera: cameras.first),
          ),
        );
        if (bytes == null) return; // user backed out of the live preview
      } catch (_) {
        // No camera available (most desktop app builds, or permission
        // denied) — fall back to letting the user upload an existing photo.
        final picked = await _picker.pickImage(source: ImageSource.gallery);
        if (picked == null || !mounted) return;
        bytes = await picked.readAsBytes();
      }
      if (!mounted) return;
      final imageBytes = bytes;
      final image = await _decode(imageBytes);
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();

      // No native detector off-mobile — seed a 10%-inset rectangle the user
      // drags into place, same fallback `ImageDetection.quadIn` uses.
      final dx = imageSize.width * 0.1;
      final dy = imageSize.height * 0.1;
      final initialQuad = Quad(
        topLeft: Offset(dx, dy),
        topRight: Offset(imageSize.width - dx, dy),
        bottomRight: Offset(imageSize.width - dx, imageSize.height - dy),
        bottomLeft: Offset(dx, imageSize.height - dy),
      );

      if (!mounted) return;
      final warped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute<Uint8List>(
          builder: (_) => _MemoryEditCornersScreen(
            imageBytes: imageBytes,
            initialQuad: initialQuad,
            imageSize: imageSize,
            saveLabel: 'Use',
            onSave: (quad) => _warp(imageBytes, quad),
          ),
        ),
      );
      if (warped == null || !mounted) return;
      setState(() => _resultBytes = warped);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List> _warp(Uint8List bytes, Quad quad) async {
    final warped = await PerspectiveWarp.warpBytes(bytes, quad);
    ui.Image enhanced;
    try {
      enhanced = await ImageEnhance.apply(warped, _mode);
    } catch (_) {
      enhanced = warped;
    }
    try {
      final data = await enhanced.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      if (!identical(enhanced, warped)) enhanced.dispose();
      warped.dispose();
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  @override
  Widget build(BuildContext context) {
    final result = _resultBytes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera / upload'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: result != null
          ? _Result(
              bytes: result,
              onPickAnother: () => setState(() => _resultBytes = null),
            )
          : _Landing(
              mode: _mode,
              busy: _busy,
              error: _error,
              onModeChanged: (m) => setState(() => _mode = m),
              onPick: _captureOrUpload,
            ),
    );
  }
}

class _Landing extends StatelessWidget {
  const _Landing({
    required this.mode,
    required this.busy,
    required this.error,
    required this.onModeChanged,
    required this.onPick,
  });

  final ImageEnhancement mode;
  final bool busy;
  final String? error;
  final ValueChanged<ImageEnhancement> onModeChanged;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined,
                color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Uses the camera when this platform has one\n'
              '(web, most mobile browsers). Otherwise upload\n'
              'a photo instead — then crop and warp it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 24),
            const Text('ENHANCEMENT',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in ImageEnhancement.values)
                  ChoiceChip(
                    label: Text(
                      _label(m),
                      style: TextStyle(
                          color: mode == m ? Colors.white : Colors.black),
                    ),
                    selected: mode == m,
                    onSelected: busy ? null : (_) => onModeChanged(m),
                    selectedColor: _kRust,
                    backgroundColor: Colors.white10,
                    labelStyle: TextStyle(
                      color: mode == m ? Colors.white : Colors.white70,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: busy ? null : onPick,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kRust,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.camera_alt_outlined),
              label: Text(busy ? 'Working…' : 'Use camera or upload'),
            ),
            if (error != null) ...[
              const SizedBox(height: 20),
              Text(error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
    );
  }

  static String _label(ImageEnhancement m) {
    switch (m) {
      case ImageEnhancement.none:
        return 'None';
      case ImageEnhancement.grayscale:
        return 'Grayscale';
      case ImageEnhancement.enhanced:
        return 'Enhanced';
      case ImageEnhancement.blackAndWhite:
        return 'B & W';
    }
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.bytes, required this.onPickAnother});
  final Uint8List bytes;
  final VoidCallback onPickAnother;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ElevatedButton.icon(
            onPressed: onPickAnother,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRust,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
//  Live camera preview (getUserMedia on web via camera_web) + shutter.
// =====================================================================

class _LiveCameraScreen extends StatefulWidget {
  const _LiveCameraScreen({required this.camera});
  final CameraDescription camera;

  @override
  State<_LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<_LiveCameraScreen> {
  CameraController? _controller;
  Future<void>? _initFuture;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller = controller;
    _initFuture = controller.initialize().catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _initFuture,
          builder: (context, snapshot) {
            final controller = _controller;
            if (_error != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (controller == null ||
                snapshot.connectionState != ConnectionState.done ||
                !controller.value.isInitialized) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                Center(child: CameraPreview(controller)),
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _shoot,
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _capturing ? Colors.white38 : Colors.white,
                            ),
                          ),
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
}

// =====================================================================
//  Bytes-based corner editor — a fork of the package's `EditCornersScreen`
//  with every `dart:io` touch point (FileImage/Image.file) swapped for
//  MemoryImage/Image.memory, so it runs on web too. Everything else
//  (handle drag math, magnifier, layout) is copied as-is.
// =====================================================================

class _MemoryEditCornersScreen extends StatefulWidget {
  const _MemoryEditCornersScreen({
    required this.imageBytes,
    required this.initialQuad,
    required this.imageSize,
    required this.onSave,
    this.saveLabel = 'Continue',
  });

  final Uint8List imageBytes;
  final Quad initialQuad;
  final Size imageSize;
  final Future<Uint8List> Function(Quad finalQuad) onSave;
  final String saveLabel;

  @override
  State<_MemoryEditCornersScreen> createState() =>
      _MemoryEditCornersScreenState();
}

class _MemoryEditCornersScreenState extends State<_MemoryEditCornersScreen> {
  late Quad _quad = widget.initialQuad;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Adjust corners'),
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            const horizontalInset = 24.0;
            const topInset = 12.0;
            const bottomInset = 96.0;
            final inner = Size(
              math.max(0, constraints.maxWidth - horizontalInset * 2),
              math.max(0, constraints.maxHeight - topInset - bottomInset),
            );
            final innerFit = _fitImage(widget.imageSize, inner);
            final fit = _Fit(
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
                  child: Image.memory(widget.imageBytes, fit: BoxFit.fill),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _Lines(quad: _quad, fit: fit),
                  ),
                ),
                for (final h in _handles(fit)) h,
                Positioned(
                  bottom: 24,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving
                              ? null
                              : () =>
                                  setState(() => _quad = widget.initialQuad),
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving ? null : _onSave,
                          child: Text(_saving ? 'Saving…' : widget.saveLabel),
                        ),
                      ),
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

  Future<void> _onSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final warped = await widget.onSave(_quad);
      if (mounted) Navigator.of(context).pop(warped);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Widget> _handles(_Fit fit) {
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
    return [for (final (point, setter) in pts) _handle(point, setter, fit)];
  }

  Widget _handle(
    Offset imagePoint,
    void Function(Offset newImagePoint) setPoint,
    _Fit fit,
  ) {
    final widgetPos = fit.imageToWidget(imagePoint);
    const r = 28.0;
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
        child: Container(
          width: r * 2,
          height: r * 2,
          alignment: Alignment.center,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.9),
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  _Fit _fitImage(Size image, Size widgetSize) {
    final scale = math.min(
      widgetSize.width / image.width,
      widgetSize.height / image.height,
    );
    final dst = Size(image.width * scale, image.height * scale);
    final off = Offset(
      (widgetSize.width - dst.width) / 2,
      (widgetSize.height - dst.height) / 2,
    );
    return _Fit(
      dstOffset: off,
      dstSize: dst,
      scaleX: dst.width / image.width,
      scaleY: dst.height / image.height,
    );
  }
}

class _Fit {
  const _Fit({
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

class _Lines extends CustomPainter {
  _Lines({required this.quad, required this.fit});
  final Quad quad;
  final _Fit fit;

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

    // Even-odd fill of [outer rect, quad] paints outer minus quad without
    // relying on Path.combine (boolean path ops render inconsistently on
    // some Flutter web backends).
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addPath(quadPath, Offset.zero);
    canvas.drawPath(dim, Paint()..color = const Color(0x99000000));

    canvas.drawPath(
      quadPath,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _Lines old) => old.quad != quad;
}
