import 'dart:io';

import 'package:flutter/material.dart';
import 'package:doclens/doclens.dart';

import '../ocr_sheet.dart';

/// Launches the OS-native document scanner (VisionKit on iOS,
/// ML Kit Document Scanner on Android) and shows the resulting pages.
///
/// This style ships zero Flutter UI on the scanner surface itself — the
/// whole capture flow lives inside the system modal. It exists so apps
/// that want native polish (and don't need custom branding on the camera)
/// can opt in with one call.
class NativeOSScanner extends StatefulWidget {
  const NativeOSScanner({super.key});

  @override
  State<NativeOSScanner> createState() => _NativeOSScannerState();
}

class _NativeOSScannerState extends State<NativeOSScanner> {
  List<String>? _pages;
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Auto-launch on push so the user lands directly in the scanner.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final paths = await DoclensPlatform.instance.scanWithNativeUI(
        pageLimit: 20,
        allowGalleryImport: true,
      );
      if (!mounted) return;
      setState(() => _pages = paths);
    } on ScannerException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Native OS scanner')),
      backgroundColor: Colors.black,
      body: Center(
        child: _running
            ? const CircularProgressIndicator()
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _scan)
                : _pages == null
                    ? _Cancelled(onScan: _scan)
                    : _Pages(paths: _pages!, onScanAgain: _scan),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(message,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _Cancelled extends StatelessWidget {
  const _Cancelled({required this.onScan});
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('No scan',
            style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: onScan,
          icon: const Icon(Icons.document_scanner),
          label: const Text('Open native scanner'),
        ),
      ],
    );
  }
}

class _Pages extends StatelessWidget {
  const _Pages({required this.paths, required this.onScanAgain});
  final List<String> paths;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: paths.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showOcrSheet(context, paths[i], dark: true),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Stack(
                    children: [
                      Image.file(File(paths[i])),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.text_fields,
                                  size: 13, color: Colors.white),
                              SizedBox(width: 5),
                              Text('OCR',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onScanAgain,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Scan again'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(paths),
                  icon: const Icon(Icons.check),
                  label: Text('Use ${paths.length} page'
                      '${paths.length == 1 ? "" : "s"}'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
