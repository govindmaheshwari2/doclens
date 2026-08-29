import 'dart:io';

import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ocr_sheet.dart';

const _kRust = Color(0xFFB5482E);

/// Imports a photo from the device gallery and runs the package's **own**
/// pipeline on it — the same `detect → edit-corners → warp` flow the live
/// scanner uses, just without the camera.
///
///   1. **detect** — [DoclensPlatform.detectInImage] runs the native edge
///      detector on the picked still image and returns a quad + the image's
///      pixel size. Off mobile (desktop) there's no native detector, so it
///      returns the image size with a `null` quad — [ImageDetection.quadIn]
///      then seeds a 10% inset the user drags into place (manual crop).
///   2. **edit**   — [EditCornersScreen] lets the user nudge the corners,
///      seeded from the detection (or a 10% inset when nothing was found).
///   3. **warp**   — on save, [DoclensPlatform.warpImage] dewarps the photo
///      using the final corners and the selected enhancement.
///
/// Every step here is a pure file operation — no camera session is created,
/// so none of these calls need an `initialize()`d controller.
class GalleryImportScanner extends StatefulWidget {
  const GalleryImportScanner({super.key});

  @override
  State<GalleryImportScanner> createState() => _GalleryImportScannerState();
}

class _GalleryImportScannerState extends State<GalleryImportScanner> {
  final _picker = ImagePicker();

  ImageEnhancement _mode = ImageEnhancement.none;
  String? _resultPath;
  bool _busy = false;
  String? _error;

  Future<void> _pickAndRun() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      final path = picked.path;

      // 1. DETECT — native edge detection on the still image.
      final detection =
          await DoclensPlatform.instance.detectInImage(imagePath: path);
      if (!mounted) return;
      if (detection == null) {
        setState(() => _error = "Couldn't read that image.");
        return;
      }

      // 2. EDIT (+ 3. WARP on save). EditCornersScreen owns its own pop and
      //    resolves with the warped crop's path. Warp applies the selected
      //    enhancement + auto-orientation, just like a live capture.
      final warpedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => EditCornersScreen(
            imagePath: path,
            initialQuad: detection.quadIn,
            imageSize: detection.imageSize,
            saveLabel: 'Use',
            onSave: (quad) => DoclensPlatform.instance.warpImage(
              rawImagePath: path,
              quad: quad,
              enhancement: _mode,
              autoOrientation: AutoOrientation.auto,
            ),
          ),
        ),
      );
      if (warpedPath == null || !mounted) return;
      setState(() => _resultPath = warpedPath);
    } on ScannerException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _resultPath;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery import'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: result != null
          ? _Result(
              path: result,
              onPickAnother: () => setState(() => _resultPath = null),
            )
          : _Landing(
              mode: _mode,
              busy: _busy,
              error: _error,
              onModeChanged: (m) => setState(() => _mode = m),
              onPick: _pickAndRun,
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
            const Icon(Icons.photo_library_outlined,
                color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Pick a photo, then run the same\ndetect → edit → warp pipeline on it.',
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
                    label: Text(_label(m)),
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
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(busy ? 'Working…' : 'Pick from gallery'),
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
  const _Result({required this.path, required this.onPickAnother});
  final String path;
  final VoidCallback onPickAnother;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickAnother,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Pick another'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => showOcrSheet(context, path, dark: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kRust,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.text_fields),
                  label: const Text('OCR'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
