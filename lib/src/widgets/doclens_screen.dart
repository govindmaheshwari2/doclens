import 'dart:io';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../quad.dart';
import 'doclens_view.dart';
import 'edit_corners_screen.dart';

// =====================================================================
//  Aesthetic tokens — a tiny private design system. Editorial /
//  instrument-panel: precision tool with a side of Hasselblad reticle.
// =====================================================================

const _kBgInk = Color(0xFF0A0B0D);
const _kSurface = Color(0xFF13151A);
const _kSurfaceHi = Color(0xFF1A1D24);
const _kBorderHairline = Color(0x14FFFFFF);
const _kBorderSoft = Color(0x22FFFFFF);
const _kTextPrimary = Color(0xFFF4F4F2);
const _kTextSecondary = Color(0xFF8C8E93);
const _kTextDim = Color(0xFF5A5C61);
const _kErrorTint = Color(0xFFFF6B6B);

const _kMonoFamilies = <String>['SF Mono', 'Menlo', 'Roboto Mono', 'monospace'];
const _kSerifFamilies = <String>['Georgia', 'Iowan Old Style', 'serif'];

TextStyle _mono({
  double size = 11,
  FontWeight weight = FontWeight.w400,
  Color color = _kTextSecondary,
  double letterSpacing = 0.14,
  double? height,
}) =>
    TextStyle(
      fontFamily: _kMonoFamilies.first,
      fontFamilyFallback: _kMonoFamilies.sublist(1),
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
  bool italic = false,
  double height = 1.1,
}) =>
    TextStyle(
      fontFamily: _kSerifFamilies.first,
      fontFamilyFallback: _kSerifFamilies.sublist(1),
      fontSize: size,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: color,
      height: height,
    );

/// Drop-in document scanner screen. Owns its own controller, runs the live
/// preview, auto-captures, then presents a built-in review screen with
/// retake / edit-corners / accept buttons.
///
/// The fastest path to a working scanner is:
///
/// ```dart
/// final ScanResult? result = await DoclensScreen.scan(context);
/// ```
///
/// Returns `null` if the user cancels. Otherwise the returned [ScanResult]
/// has the same shape produced by [DoclensController.capture].
///
/// Customisation is offered at three levels, in order of effort:
///
/// 1. **Top-level parameters** — colours, labels, auto-capture timing,
///    flash mode, lens, JPEG quality, etc. Cover the common 80% of apps.
/// 2. **`config`** — a full [ScannerConfig] for fine-grained tuning
///    (smoothing, detection throttle, lifecycle, telemetry). Top-level
///    parameters override matching fields on this config.
/// 3. **Drop down to [DoclensView] + [DoclensController]
///    directly** when you need custom builders or your own result flow.
class DoclensScreen extends StatefulWidget {
  const DoclensScreen({
    super.key,
    // --- behavior knobs (override matching fields on [config]) ---
    this.enableAutoCapture,
    this.autoCaptureStabilityDuration,
    this.autoCaptureConfirmationDelay,
    this.autoCaptureCornerThreshold,
    this.enablePerspectiveWarp,
    this.jpegQuality,
    this.initialFlashMode,
    this.initialLens,
    this.enableTapToFocus,
    this.enablePinchToZoom,
    this.detectionThrottleHz,
    // --- UI knobs ---
    this.accentColor,
    this.warningColor,
    this.backgroundColor = Colors.black,
    this.appBarTitle = 'Scan result',
    this.captureHintText = 'Hold steady — auto capturing',
    this.retakeLabel = 'Retake',
    this.editCornersLabel = 'Edit corners',
    this.useLabel = 'Use',
    this.showHint = true,
    this.showCloseButton = true,
    this.enableEditCorners = true,
    // --- escape hatches ---
    this.config = const ScannerConfig(),
    this.onCapture,
  });

  /// Whether the scanner should auto-fire the shutter when the user
  /// holds a document still for long enough.
  ///
  /// When `false`, the user must tap the on-screen shutter button to
  /// capture — useful if your flow involves arranging documents on a
  /// surface and tapping when ready.
  ///
  /// When `null` (default), inherits `true` from [config] /
  /// [ScannerConfig.enableAutoCapture].
  final bool? enableAutoCapture;

  /// How long the document quad must hold still **before** the
  /// confirmation phase starts.
  ///
  /// - Shorter (`400 ms`) → snappier, riskier on shaky hands.
  /// - Longer (`1500 ms`) → safer, feels sluggish on tripod-like holds.
  ///
  /// Default (from [ScannerConfig]) is **800 ms**. Total time from
  /// "document detected" → shutter is roughly
  /// `autoCaptureStabilityDuration + autoCaptureConfirmationDelay`.
  final Duration? autoCaptureStabilityDuration;

  /// How long the on-screen overlay pulses the confirmation colour
  /// **before** the shutter actually fires.
  ///
  /// The user can move the camera during this window to abort the
  /// capture. Mirrors VisionKit's "found a document — hold still" cue.
  ///
  /// Default **350 ms**. Lower values feel more instant; higher values
  /// give nervous users more time to react.
  final Duration? autoCaptureConfirmationDelay;

  /// Maximum per-corner movement between consecutive frames that still
  /// counts as "stable", expressed as a fraction of the normalized
  /// `[0, 1]` preview coordinate space.
  ///
  /// `0.01` (1%) demands a tripod-steady hand; `0.05` (5%) fires on
  /// noticeably shaky hands but risks motion-blurred captures.
  ///
  /// Default **0.02** (2% of the frame).
  final double? autoCaptureCornerThreshold;

  /// Whether to perspective-warp the captured photo into a flat
  /// rectangle using the detected quad.
  ///
  /// When `false`, [ScanResult.croppedImagePath] is null and the caller
  /// gets only [ScanResult.rawImagePath]. Useful when your downstream
  /// pipeline wants the raw photo (e.g. you'll OCR with your own
  /// crop logic).
  ///
  /// Default `true`.
  final bool? enablePerspectiveWarp;

  /// JPEG compression quality `1`–`100` for both the raw and cropped
  /// images written to disk.
  ///
  /// `92` is visually indistinguishable from `100` in document
  /// dropoff tests and is `~3×` smaller — recommended for most apps.
  /// Use `100` only if you're going to re-process the bytes.
  final int? jpegQuality;

  /// Flash mode the camera should start in.
  ///
  /// - `FlashMode.off` — never fire.
  /// - `FlashMode.auto` — let the OS decide (default).
  /// - `FlashMode.on` — fire on every capture.
  /// - `FlashMode.torch` — continuous lamp for low-light scanning.
  ///
  /// The user can still cycle modes from the on-screen flash button.
  final FlashMode? initialFlashMode;

  /// Which camera to start with.
  ///
  /// - `CameraLens.back` — rear camera, the only sensible default for
  ///   documents.
  /// - `CameraLens.front` — useful for selfie-mode scanning of, e.g.,
  ///   a passport or whiteboard behind the user.
  final CameraLens? initialLens;

  /// Whether tapping the preview should set the focus point at that
  /// location (where supported by the OS). Default `true`.
  final bool? enableTapToFocus;

  /// Whether pinching the preview should drive the camera's zoom level
  /// (where supported by the OS). Default `true`.
  final bool? enablePinchToZoom;

  /// How often per second the native detector runs.
  ///
  /// Lower (`8`) saves CPU and battery; higher (`30`) makes the quad
  /// overlay feel more "alive" but can drop preview frames on older
  /// devices.
  ///
  /// Default **15 Hz** — Apple Vision's ML detector handles this
  /// comfortably on A12+; Android's Sobel detector is fine up to ~20 Hz.
  final int? detectionThrottleHz;

  /// Primary brand colour. Tints:
  /// - the detected-quad outline when status is `aligned` or
  ///   `confirming` (brighter when about to capture),
  /// - the shutter button's glow,
  /// - the "Use" button on the review screen.
  ///
  /// Defaults to the package's "aligned" green
  /// (`Color(0xFF34C759)` — Apple's system green).
  final Color? accentColor;

  /// Colour used when the document is detected but **not yet capturable**
  /// (`tooFar`, `tooClose`, or `tilted`). Defaults to amber
  /// (`Color(0xFFFFCC00)`).
  final Color? warningColor;

  /// Background colour of both the live preview and the review screen.
  /// Defaults to `Colors.black` — gives the camera preview the most
  /// contrast and matches the OS scanner look.
  final Color backgroundColor;

  /// Title shown in the review screen's AppBar after a capture.
  /// Defaults to `'Scan result'`. Override for localization.
  final String appBarTitle;

  /// Pill of text shown at the bottom of the live preview reminding
  /// the user to hold still. Set to `''` (with [showHint]: `true`) or
  /// pass [showHint]: `false` to hide.
  final String captureHintText;

  /// Label of the "retake" button on the review screen. Default
  /// `'Retake'` — override for localization.
  final String retakeLabel;

  /// Label of the "edit corners" button on the review screen. Default
  /// `'Edit corners'` — override for localization. Ignored when
  /// [enableEditCorners] is `false`.
  final String editCornersLabel;

  /// Label of the primary "accept" button on the review screen. Default
  /// `'Use'` — override for localization or to match your app's verb
  /// (`'Save'`, `'Send'`, `'Next'`).
  final String useLabel;

  /// Whether to render the bottom-of-screen hint pill (`captureHintText`)
  /// during the live preview. Default `true`.
  final bool showHint;

  /// Whether to render the top-left close (X) button. When `false`, the
  /// only way out of the scanner is to capture or use the system back
  /// gesture. Default `true`.
  final bool showCloseButton;

  /// Whether the review screen offers an "edit corners" button. Set to
  /// `false` for apps that never want the user to touch up the crop.
  /// Default `true`.
  final bool enableEditCorners;

  /// Full [ScannerConfig] for fields not surfaced as top-level
  /// parameters: quad smoothing window, lifecycle pause/resume, debug
  /// overlay, telemetry logging, and the explicit
  /// `enableAutoCaptureConfirmation` flag (turn the confirmation phase
  /// off entirely).
  ///
  /// Top-level parameters that are non-`null` override their matching
  /// field on this config. Pass a custom `ScannerConfig` here when you
  /// need to tune those advanced fields without re-supplying every
  /// top-level knob.
  final ScannerConfig config;

  /// Custom callback fired when the user accepts the captured scan.
  ///
  /// - When `null` (default), the screen pops itself and the awaited
  ///   `Future<ScanResult?>` from [scan] resolves with the result.
  /// - When non-`null`, the screen calls your callback but does **not**
  ///   auto-pop — useful if you want to navigate elsewhere yourself or
  ///   stay on the scanner for additional pages.
  final void Function(ScanResult result)? onCapture;

  /// Push the scanner as a full-screen modal route, wait for the user to
  /// confirm or cancel, and return the resulting [ScanResult] — or
  /// `null` if they cancel (back gesture, close button, or system pop).
  ///
  /// Every named argument mirrors the corresponding field on
  /// [DoclensScreen]. See those field docs for the full
  /// explanation of each parameter.
  ///
  /// Typical usage:
  ///
  /// ```dart
  /// final result = await DoclensScreen.scan(
  ///   context,
  ///   accentColor: Theme.of(context).colorScheme.primary,
  ///   useLabel: 'Save',
  /// );
  /// if (result == null) return; // user cancelled
  /// // result.croppedImagePath / rawImagePath / detectedQuad / ...
  /// ```
  static Future<ScanResult?> scan(
    BuildContext context, {
    bool? enableAutoCapture,
    Duration? autoCaptureStabilityDuration,
    Duration? autoCaptureConfirmationDelay,
    double? autoCaptureCornerThreshold,
    bool? enablePerspectiveWarp,
    int? jpegQuality,
    FlashMode? initialFlashMode,
    CameraLens? initialLens,
    bool? enableTapToFocus,
    bool? enablePinchToZoom,
    int? detectionThrottleHz,
    Color? accentColor,
    Color? warningColor,
    Color backgroundColor = Colors.black,
    String appBarTitle = 'Scan result',
    String captureHintText = 'Hold steady — auto capturing',
    String retakeLabel = 'Retake',
    String editCornersLabel = 'Edit corners',
    String useLabel = 'Use',
    bool showHint = true,
    bool showCloseButton = true,
    bool enableEditCorners = true,
    ScannerConfig config = const ScannerConfig(),
  }) {
    return Navigator.of(context).push<ScanResult>(
      MaterialPageRoute<ScanResult>(
        fullscreenDialog: true,
        builder: (_) => DoclensScreen(
          enableAutoCapture: enableAutoCapture,
          autoCaptureStabilityDuration: autoCaptureStabilityDuration,
          autoCaptureConfirmationDelay: autoCaptureConfirmationDelay,
          autoCaptureCornerThreshold: autoCaptureCornerThreshold,
          enablePerspectiveWarp: enablePerspectiveWarp,
          jpegQuality: jpegQuality,
          initialFlashMode: initialFlashMode,
          initialLens: initialLens,
          enableTapToFocus: enableTapToFocus,
          enablePinchToZoom: enablePinchToZoom,
          detectionThrottleHz: detectionThrottleHz,
          accentColor: accentColor,
          warningColor: warningColor,
          backgroundColor: backgroundColor,
          appBarTitle: appBarTitle,
          captureHintText: captureHintText,
          retakeLabel: retakeLabel,
          editCornersLabel: editCornersLabel,
          useLabel: useLabel,
          showHint: showHint,
          showCloseButton: showCloseButton,
          enableEditCorners: enableEditCorners,
          config: config,
        ),
      ),
    );
  }

  @override
  State<DoclensScreen> createState() => _DoclensScreenState();
}

class _DoclensScreenState extends State<DoclensScreen> {
  late final DoclensController _controller =
      DoclensController(config: _resolvedConfig());
  bool _initFailed = false;
  String? _initError;

  Color get _accent =>
      widget.accentColor ?? const Color(0xFFD4FF4D); // acid lime
  Color get _warning =>
      widget.warningColor ?? const Color(0xFFFFB454); // warm amber

  /// Merge the top-level overrides into [widget.config]. Any non-null
  /// override wins; everything else passes through unchanged.
  ScannerConfig _resolvedConfig() {
    final c = widget.config;
    return ScannerConfig(
      // detection
      enableLiveDetection: c.enableLiveDetection,
      enableAutoCapture: widget.enableAutoCapture ?? c.enableAutoCapture,
      autoCaptureStabilityDuration:
          widget.autoCaptureStabilityDuration ?? c.autoCaptureStabilityDuration,
      autoCaptureCornerThreshold:
          widget.autoCaptureCornerThreshold ?? c.autoCaptureCornerThreshold,
      enableAutoCaptureConfirmation: c.enableAutoCaptureConfirmation,
      autoCaptureConfirmationDelay:
          widget.autoCaptureConfirmationDelay ?? c.autoCaptureConfirmationDelay,
      detectionThrottleHz: widget.detectionThrottleHz ?? c.detectionThrottleHz,
      enableQuadSmoothing: c.enableQuadSmoothing,
      quadSmoothingWindow: c.quadSmoothingWindow,
      // capture
      enablePerspectiveWarp:
          widget.enablePerspectiveWarp ?? c.enablePerspectiveWarp,
      jpegQuality: widget.jpegQuality ?? c.jpegQuality,
      outputFormat: c.outputFormat,
      captureResolution: c.captureResolution,
      // camera
      initialFlashMode: widget.initialFlashMode ?? c.initialFlashMode,
      initialLens: widget.initialLens ?? c.initialLens,
      enableCameraSwitch: c.enableCameraSwitch,
      enableTapToFocus: widget.enableTapToFocus ?? c.enableTapToFocus,
      enablePinchToZoom: widget.enablePinchToZoom ?? c.enablePinchToZoom,
      // status
      enableLowLightDetection: c.enableLowLightDetection,
      enableStabilityStatus: c.enableStabilityStatus,
      // lifecycle
      pauseOnBackground: c.pauseOnBackground,
      resumeOnForeground: c.resumeOnForeground,
      // diagnostics
      enableDebugOverlay: c.enableDebugOverlay,
      enableTelemetryLogging: c.enableTelemetryLogging,
    );
  }

  @override
  void initState() {
    super.initState();
    _controller.initialize().catchError((Object e) {
      if (!mounted) return;
      setState(() {
        _initFailed = true;
        _initError = e.toString();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleCapture(ScanResult result) async {
    // Pause the live session while the user reviews — saves CPU + battery.
    await _controller.pause().catchError((_) {});
    if (!mounted) return;
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _ReviewScreen(
          result: result,
          controller: _controller,
          appBarTitle: widget.appBarTitle,
          accent: _accent,
          backgroundColor: widget.backgroundColor,
          retakeLabel: widget.retakeLabel,
          editCornersLabel: widget.editCornersLabel,
          useLabel: widget.useLabel,
          enableEditCorners: widget.enableEditCorners,
        ),
      ),
    );
    if (!mounted) return;
    if (accepted == true) {
      if (widget.onCapture != null) {
        widget.onCapture!(result);
      } else {
        Navigator.of(context).pop(result);
      }
    } else {
      await _controller.resume().catchError((_) {});
    }
  }

  String _statusLabel(DetectionStatus s) {
    switch (s) {
      case DetectionStatus.searching:
        return 'SEARCHING';
      case DetectionStatus.noPaper:
        return 'NO DOCUMENT';
      case DetectionStatus.tooFar:
        return 'MOVE CLOSER';
      case DetectionStatus.tooClose:
        return 'MOVE BACK';
      case DetectionStatus.tilted:
        return 'HOLD PARALLEL';
      case DetectionStatus.aligned:
        return 'ALIGNED · HOLD STILL';
      case DetectionStatus.confirming:
        return 'CAPTURING';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initFailed) {
      return _InstrumentErrorScreen(
        bg: widget.backgroundColor,
        message: _initError ?? 'Failed to start scanner',
        accent: _accent,
      );
    }
    return Scaffold(
      backgroundColor: widget.backgroundColor,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Live preview + overlay + shutter (provided by the package's
            // builder slots). The shutter floats inside this child too.
            DoclensView(
              controller: _controller,
              backgroundColor: widget.backgroundColor,
              overlayBuilder: (ctx, quad, status) => _ReticleOverlay(
                quad: quad,
                status: status,
                accent: _accent,
                warning: _warning,
              ),
              captureButtonBuilder: null, // we draw the shutter ourselves
              flashButtonBuilder: null, // ditto
              lowLightHintBuilder: null,
              onCapture: _handleCapture,
            ),

            // Vignette + film-grain feel without an image asset.
            IgnorePointer(child: _Vignette()),

            // Top instrument bar: close · title · flash + lens.
            // ListenableBuilder repaints when the controller calls
            // notifyListeners() — currently on flash change and on every
            // status transition. Without this the flash chip would render
            // once and then never update its icon when the user taps it.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => _TopInstrumentBar(
                  showClose: widget.showCloseButton,
                  title: widget.appBarTitle.toUpperCase(),
                  accent: _accent,
                  onClose: () => Navigator.of(context).maybePop(),
                  flashMode: _controller.flashMode,
                  onFlash: () => _controller.cycleFlashMode(),
                ),
              ),
            ),

            // Live status readout (the instrument cluster).
            Positioned(
              left: 0,
              right: 0,
              bottom: 188,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final s = _controller.status;
                      return _StatusReadout(
                        label: _statusLabel(s),
                        hint: widget.showHint ? widget.captureHintText : null,
                        accent: _accent,
                        warning: _warning,
                        status: s,
                      );
                    },
                  ),
                ),
              ),
            ),

            // Bottom shutter band.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomShutterBand(
                accent: _accent,
                onCapture: _manualCapture,
                isCapturing: _controller.isCapturing,
                status: _controller.status,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manualCapture() async {
    if (_controller.isCapturing) return;
    try {
      final result = await _controller.capture();
      await _handleCapture(result);
    } catch (_) {
      // Errors flow back through autoCaptureStream → onCapture; manual
      // path stays silent here to avoid double-fire.
    }
  }
}

// ---- review screen ----------------------------------------------------

class _ReviewScreen extends StatefulWidget {
  const _ReviewScreen({
    required this.result,
    required this.controller,
    required this.appBarTitle,
    required this.accent,
    required this.backgroundColor,
    required this.retakeLabel,
    required this.editCornersLabel,
    required this.useLabel,
    required this.enableEditCorners,
  });

  final ScanResult result;
  final DoclensController controller;
  final String appBarTitle;
  final Color accent;
  final Color backgroundColor;
  final String retakeLabel;
  final String editCornersLabel;
  final String useLabel;
  final bool enableEditCorners;

  @override
  State<_ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<_ReviewScreen> {
  late ScanResult _result = widget.result;

  Future<void> _editCorners() async {
    final newPath = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => EditCornersScreen(
          imagePath: _result.rawImagePath,
          initialQuad: _result.detectedQuad,
          imageSize: _result.rawImageSize,
          onSave: (q) async {
            final out =
                await widget.controller.warpImage(_result.rawImagePath, q);
            if (mounted) Navigator.of(context).pop(out);
            return out;
          },
        ),
      ),
    );
    if (newPath != null && mounted) {
      setState(() {
        _result = ScanResult(
          croppedImagePath: newPath,
          rawImagePath: _result.rawImagePath,
          detectedQuad: _result.detectedQuad,
          rawImageSize: _result.rawImageSize,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _result.croppedImagePath;
    return Scaffold(
      backgroundColor: widget.backgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ReviewHeader(
              title: widget.appBarTitle,
              accent: widget.accent,
              onBack: () => Navigator.of(context).pop(false),
            ),
            Expanded(
              child: path == null
                  ? _ReviewEmpty(
                      hasWarpError: _result.warpError != null,
                      editLabel: widget.editCornersLabel,
                      accent: widget.accent,
                    )
                  : _ReviewImage(path: path, accent: widget.accent),
            ),
            _ReviewActions(
              accent: widget.accent,
              retakeLabel: widget.retakeLabel,
              editCornersLabel: widget.editCornersLabel,
              useLabel: widget.useLabel,
              enableEditCorners: widget.enableEditCorners,
              onRetake: () => Navigator.of(context).pop(false),
              onEditCorners: _editCorners,
              onUse: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
//  Editorial / instrument-panel UI primitives
//  ---------------------------------------------------------------------
//  These are tightly coupled to the screen above and intentionally
//  kept private. They render a single coherent aesthetic:
//
//    - Hasselblad-style corner brackets and tick marks
//    - Calibrated mono readouts in uppercase
//    - Serif italic chrome (titles)
//    - Acid-lime accent
//    - No Material defaults
// =====================================================================

class _Vignette extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.1,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.55),
          ],
          stops: const [0.65, 1.0],
        ),
      ),
    );
  }
}

class _TopInstrumentBar extends StatelessWidget {
  const _TopInstrumentBar({
    required this.showClose,
    required this.title,
    required this.accent,
    required this.onClose,
    required this.flashMode,
    required this.onFlash,
  });

  final bool showClose;
  final String title;
  final Color accent;
  final VoidCallback onClose;
  final FlashMode flashMode;
  final VoidCallback onFlash;

  IconData _flashIcon() {
    switch (flashMode) {
      case FlashMode.off:
        return Icons.flash_off_outlined;
      case FlashMode.auto:
        return Icons.flash_auto_outlined;
      case FlashMode.on:
        return Icons.flash_on_outlined;
      case FlashMode.torch:
        return Icons.highlight_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, mediaPadding + 12, 20, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showClose)
            _InstrumentIconButton(
              icon: Icons.close,
              onTap: onClose,
              accent: accent,
            )
          else
            const SizedBox(width: 36),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NATIVE DOC SCANNER',
                  style: _mono(
                    size: 9,
                    color: accent,
                    letterSpacing: 0.22,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: _serif(
                    size: 19,
                    italic: true,
                    color: _kTextPrimary,
                  ),
                ),
              ],
            ),
          ),
          _InstrumentIconButton(
            icon: _flashIcon(),
            onTap: onFlash,
            accent: accent,
            label: flashMode.name.toUpperCase(),
          ),
        ],
      ),
    );
  }
}

class _InstrumentIconButton extends StatelessWidget {
  const _InstrumentIconButton({
    required this.icon,
    required this.onTap,
    required this.accent,
    this.label,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color accent;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 36,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 9 : 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorderSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _kTextPrimary, size: 17),
            if (label != null) ...[
              const SizedBox(width: 8),
              Text(
                label!,
                style: _mono(
                  size: 9.5,
                  color: _kTextSecondary,
                  weight: FontWeight.w600,
                  letterSpacing: 0.22,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusReadout extends StatelessWidget {
  const _StatusReadout({
    required this.label,
    required this.hint,
    required this.accent,
    required this.warning,
    required this.status,
  });

  final String label;
  final String? hint;
  final Color accent;
  final Color warning;
  final DetectionStatus status;

  Color _dotColor() {
    switch (status) {
      case DetectionStatus.confirming:
        return accent;
      case DetectionStatus.aligned:
        return accent;
      case DetectionStatus.tilted:
      case DetectionStatus.tooClose:
      case DetectionStatus.tooFar:
        return warning;
      case DetectionStatus.searching:
      case DetectionStatus.noPaper:
        return _kTextSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dot = _dotColor();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _kBorderSoft),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulseDot(
                  color: dot, pulse: status == DetectionStatus.confirming),
              const SizedBox(width: 10),
              Text(
                label,
                style: _mono(
                  size: 11,
                  color: _kTextPrimary,
                  weight: FontWeight.w600,
                  letterSpacing: 0.22,
                ),
              ),
            ],
          ),
          if (hint != null && hint!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              style: _serif(
                size: 12,
                italic: true,
                color: _kTextSecondary,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.pulse});
  final Color color;
  final bool pulse;
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = widget.pulse ? _c.value : 1.0;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.4 + 0.6 * t),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.45 * t),
                blurRadius: 8 * t,
                spreadRadius: 1 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BottomShutterBand extends StatelessWidget {
  const _BottomShutterBand({
    required this.accent,
    required this.onCapture,
    required this.isCapturing,
    required this.status,
  });

  final Color accent;
  final VoidCallback onCapture;
  final bool isCapturing;
  final DetectionStatus status;

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 22, 20, mediaPadding + 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: [
          Expanded(child: _CalibrationStrip(accent: accent)),
          const SizedBox(width: 24),
          _InstrumentShutter(
            accent: accent,
            isCapturing: isCapturing,
            armed: status == DetectionStatus.aligned ||
                status == DetectionStatus.confirming,
            onTap: onCapture,
          ),
          const SizedBox(width: 24),
          Expanded(child: _CalibrationStrip(accent: accent, reverse: true)),
        ],
      ),
    );
  }
}

class _CalibrationStrip extends StatelessWidget {
  const _CalibrationStrip({required this.accent, this.reverse = false});
  final Color accent;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: CustomPaint(
        painter: _CalibrationPainter(accent: accent, reverse: reverse),
      ),
    );
  }
}

class _CalibrationPainter extends CustomPainter {
  _CalibrationPainter({required this.accent, required this.reverse});
  final Color accent;
  final bool reverse;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = _kTextDim.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final tall = Paint()
      ..color = accent
      ..strokeWidth = 1.4;

    const ticks = 14;
    final spacing = size.width / (ticks - 1);
    final cy = size.height / 2;
    for (var i = 0; i < ticks; i++) {
      final x = reverse ? size.width - i * spacing : i * spacing;
      final isMajor = i % 4 == 0;
      final h = isMajor ? 12.0 : 6.0;
      canvas.drawLine(
        Offset(x, cy - h / 2),
        Offset(x, cy + h / 2),
        isMajor ? tall : base,
      );
    }
    // baseline
    canvas.drawLine(
      Offset(0, cy),
      Offset(size.width, cy),
      Paint()..color = _kTextDim.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(covariant _CalibrationPainter old) =>
      old.accent != accent || old.reverse != reverse;
}

class _InstrumentShutter extends StatefulWidget {
  const _InstrumentShutter({
    required this.accent,
    required this.isCapturing,
    required this.armed,
    required this.onTap,
  });
  final Color accent;
  final bool isCapturing;
  final bool armed;
  final VoidCallback onTap;

  @override
  State<_InstrumentShutter> createState() => _InstrumentShutterState();
}

class _InstrumentShutterState extends State<_InstrumentShutter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    lowerBound: 0.0,
    upperBound: 1.0,
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapCancel: () => _press.reverse(),
      onTapUp: (_) {
        _press.reverse();
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, _) {
          final scale = 1.0 - 0.06 * _press.value;
          final inner = widget.armed ? widget.accent : Colors.white;
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.armed
                      ? widget.accent
                      : _kTextPrimary.withValues(alpha: 0.85),
                  width: 2,
                ),
                boxShadow: widget.armed
                    ? [
                        BoxShadow(
                          color: widget.accent.withValues(alpha: 0.45),
                          blurRadius: 22,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isCapturing
                        ? inner.withValues(alpha: 0.55)
                        : inner,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---- review screen primitives ----------------------------------------

class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader({
    required this.title,
    required this.accent,
    required this.onBack,
  });
  final String title;
  final Color accent;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          _InstrumentIconButton(
            icon: Icons.arrow_back,
            onTap: onBack,
            accent: accent,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'REVIEW',
                  style: _mono(
                    size: 9,
                    color: accent,
                    letterSpacing: 0.24,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: _serif(size: 22, italic: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewImage extends StatelessWidget {
  const _ReviewImage({required this.path, required this.accent});
  final String path;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: LayoutBuilder(
        builder: (context, c) {
          return Stack(
            children: [
              // Subtle border-frame so the photo never feels naked on the
              // ink background.
              Container(
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorderSoft),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(File(path), fit: BoxFit.contain),
                ),
              ),
              // 4 corner brackets so the surface feels like a viewfinder
              // even on the review screen.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _CornerFramePainter(color: accent),
                  ),
                ),
              ),
              Positioned(
                top: 14,
                left: 18,
                child: Text(
                  'CROPPED',
                  style: _mono(
                    size: 9,
                    color: accent,
                    weight: FontWeight.w700,
                    letterSpacing: 0.22,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CornerFramePainter extends CustomPainter {
  _CornerFramePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const len = 18.0;
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.8
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
  bool shouldRepaint(covariant _CornerFramePainter old) => old.color != color;
}

class _ReviewEmpty extends StatelessWidget {
  const _ReviewEmpty({
    required this.hasWarpError,
    required this.editLabel,
    required this.accent,
  });
  final bool hasWarpError;
  final String editLabel;
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
            hasWarpError ? 'CROP UNAVAILABLE' : 'NO CROPPED RESULT',
            style: _mono(
              size: 10,
              color: accent,
              letterSpacing: 0.26,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            hasWarpError
                ? 'The detected corners could not be warped into a flat document. Tap "$editLabel" to nudge them by hand, or retake the photo.'
                : 'No cropped output was produced for this capture.',
            style: _serif(
              size: 17,
              italic: true,
              color: _kTextPrimary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewActions extends StatelessWidget {
  const _ReviewActions({
    required this.accent,
    required this.retakeLabel,
    required this.editCornersLabel,
    required this.useLabel,
    required this.enableEditCorners,
    required this.onRetake,
    required this.onEditCorners,
    required this.onUse,
  });

  final Color accent;
  final String retakeLabel;
  final String editCornersLabel;
  final String useLabel;
  final bool enableEditCorners;
  final VoidCallback onRetake;
  final VoidCallback onEditCorners;
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
          _GhostButton(label: retakeLabel, onTap: onRetake),
          if (enableEditCorners) ...[
            const SizedBox(width: 10),
            _GhostButton(label: editCornersLabel, onTap: onEditCorners),
          ],
          const Spacer(),
          _PrimaryButton(label: useLabel, accent: accent, onTap: onUse),
        ],
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _kSurfaceHi,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorderSoft),
        ),
        child: Center(
          child: Text(
            label.toUpperCase(),
            style: _mono(
              size: 11,
              color: _kTextPrimary,
              weight: FontWeight.w600,
              letterSpacing: 0.22,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.accent,
    required this.onTap,
  });
  final String label;
  final Color accent;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: 18,
              spreadRadius: 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: _mono(
                size: 11.5,
                color: _kBgInk,
                weight: FontWeight.w700,
                letterSpacing: 0.26,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, color: _kBgInk, size: 16),
          ],
        ),
      ),
    );
  }
}

// ---- error screen ----------------------------------------------------

class _InstrumentErrorScreen extends StatelessWidget {
  const _InstrumentErrorScreen({
    required this.bg,
    required this.message,
    required this.accent,
  });
  final Color bg;
  final String message;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _kErrorTint,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _kErrorTint.withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'SCANNER OFFLINE',
                    style: _mono(
                      size: 10,
                      color: _kErrorTint,
                      letterSpacing: 0.26,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Could not start the camera.',
                style: _serif(size: 28, italic: true, height: 1.1),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: _mono(size: 12, color: _kTextSecondary, height: 1.45),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Row(
                  children: [
                    Text(
                      'DISMISS',
                      style: _mono(
                        size: 11,
                        color: accent,
                        weight: FontWeight.w700,
                        letterSpacing: 0.24,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_forward, color: accent, size: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- the reticle overlay (the iconic part) ---------------------------

class _ReticleOverlay extends StatelessWidget {
  const _ReticleOverlay({
    required this.quad,
    required this.status,
    required this.accent,
    required this.warning,
  });

  final Quad? quad;
  final DetectionStatus status;
  final Color accent;
  final Color warning;

  Color _strokeColor() {
    switch (status) {
      case DetectionStatus.confirming:
        return accent;
      case DetectionStatus.aligned:
        return accent;
      case DetectionStatus.tilted:
      case DetectionStatus.tooClose:
      case DetectionStatus.tooFar:
        return warning;
      case DetectionStatus.searching:
      case DetectionStatus.noPaper:
        return _kTextSecondary.withValues(alpha: 0.6);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ReticlePainter(
        quad: quad,
        color: _strokeColor(),
        status: status,
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter({
    required this.quad,
    required this.color,
    required this.status,
  });

  final Quad? quad;
  final Color color;
  final DetectionStatus status;

  static const _bracketLen = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Permanent viewfinder reticle in the corners of the frame — the
    //    Hasselblad cue, present even when no quad is detected.
    _paintFrameReticle(canvas, size);

    // 2. Detected quad — drawn as 4 corner brackets at each corner plus
    //    a hairline connecting them, NOT a thick coloured outline.
    final q = quad;
    if (q == null) return;
    final scaled = q.scaleToSize(size);
    _paintQuadConnective(canvas, scaled);
    _paintQuadBrackets(canvas, scaled);
  }

  void _paintFrameReticle(Canvas canvas, Size size) {
    const margin = 18.0;
    const len = 14.0;
    final paint = Paint()
      ..color = _kTextSecondary.withValues(alpha: 0.55)
      ..strokeWidth = 1.0;

    void corner(Offset o, Offset dx, Offset dy) {
      canvas.drawLine(o, o + dx, paint);
      canvas.drawLine(o, o + dy, paint);
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

  void _paintQuadConnective(Canvas canvas, Quad q) {
    final path = Path()
      ..moveTo(q.topLeft.dx, q.topLeft.dy)
      ..lineTo(q.topRight.dx, q.topRight.dy)
      ..lineTo(q.bottomRight.dx, q.bottomRight.dy)
      ..lineTo(q.bottomLeft.dx, q.bottomLeft.dy)
      ..close();
    final fill = Paint()..color = color.withValues(alpha: 0.06);
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  void _paintQuadBrackets(Canvas canvas, Quad q) {
    final corners = [q.topLeft, q.topRight, q.bottomRight, q.bottomLeft];
    final neighbours = [
      [q.topRight, q.bottomLeft],
      [q.topLeft, q.bottomRight],
      [q.topRight, q.bottomLeft],
      [q.bottomRight, q.topLeft],
    ];
    final bracketPaint = Paint()
      ..color = color
      ..strokeWidth = status == DetectionStatus.confirming ? 2.6 : 2.0
      ..strokeCap = StrokeCap.square;

    for (var i = 0; i < 4; i++) {
      final c = corners[i];
      for (final n in neighbours[i]) {
        final dir = (n - c);
        final mag = dir.distance;
        if (mag < 1) continue;
        final unit = Offset(dir.dx / mag, dir.dy / mag);
        canvas.drawLine(c, c + unit * _bracketLen, bracketPaint);
      }
      // small filled dot at each corner — instrument feel
      canvas.drawCircle(c, 2.2, Paint()..color = color);
    }

    // Center crosshair when aligned/confirming, lets the user feel the lock.
    if (status == DetectionStatus.aligned ||
        status == DetectionStatus.confirming) {
      final center = q.centroid;
      final p = Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 1.0;
      const r = 7.0;
      canvas.drawLine(center.translate(-r, 0), center.translate(r, 0), p);
      canvas.drawLine(center.translate(0, -r), center.translate(0, r), p);
    }
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter old) =>
      old.quad != quad || old.color != color || old.status != status;
}
