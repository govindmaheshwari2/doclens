import 'dart:io';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../quad.dart';
import 'doclens_view.dart';
import 'edit_corners_screen.dart';
import 'quad_overlay.dart';

// =====================================================================
//  Aesthetic tokens — refined editorial monochrome.
//  Pure black-and-white so the scanner drops into any host app without
//  fighting its brand palette. Adopters that want chroma can pass
//  `accentColor` / `warningColor` to the screen.
// =====================================================================

const _kBgInk = Color(0xFF000000);
const _kSurface = Color(0xFF0E0E0E);
const _kSurfaceHi = Color(0xFF181818);
const _kBorderHairline = Color(0x14FFFFFF);
const _kBorderSoft = Color(0x26FFFFFF);
const _kTextPrimary = Color(0xFFFFFFFF);
const _kTextSecondary = Color(0xFFAAAAAA);
const _kErrorTint = Color(0xFFE8E8E8);

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
    this.imageEnhancement,
    this.autoOrientation,
    this.initialFlashMode,
    this.initialLens,
    this.enableTapToFocus,
    this.enablePinchToZoom,
    this.detectionThrottleHz,
    // --- UI knobs ---
    this.accentColor,
    this.warningColor,
    this.overlayStyle,
    this.backgroundColor = Colors.black,
    this.appBarTitle = 'Preview',
    this.captureHintText = 'Hold steady to capture',
    this.retakeLabel = 'Retake',
    this.editCornersLabel = 'Edit corners',
    this.useLabel = 'Use',
    this.showHint = true,
    this.showCloseButton = true,
    this.enableEditCorners = true,
    // --- review-screen builders ---
    this.reviewBuilder,
    this.reviewHeaderBuilder,
    this.reviewImageBuilder,
    this.reviewEmptyBuilder,
    this.reviewActionsBuilder,
    this.errorBuilder,
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
  /// images written to disk. Defaults to **100** so OCR / downstream
  /// re-processing has the cleanest possible bytes. Drop to `~92` if
  /// disk size matters (visually indistinguishable from 100 and
  /// ~3× smaller).
  final int? jpegQuality;

  /// Post-warp processing applied to the cropped document image.
  ///
  /// - [ImageEnhancement.none] (default) — pure dewarp, unmodified pixels.
  /// - [ImageEnhancement.grayscale] — desaturated.
  /// - [ImageEnhancement.enhanced] — boosted contrast/saturation
  ///   ("magic colour").
  /// - [ImageEnhancement.blackAndWhite] — high-contrast near-bitonal
  ///   "document" look, best for OCR on faint text.
  ///
  /// Only the cropped output is affected; the raw image is left untouched.
  /// When `null` (default), inherits from [config] /
  /// [ScannerConfig.imageEnhancement].
  final ImageEnhancement? imageEnhancement;

  /// Automatic upright-orientation correction for the cropped document.
  ///
  /// - [AutoOrientation.none] (default) — keep the crop's in-frame orientation.
  /// - [AutoOrientation.auto] — detect the document's text direction
  ///   on-device and rotate the crop in 90° steps so it reads upright.
  ///
  /// Only the cropped output is affected; the raw image is left untouched.
  /// When `null` (default), inherits from [config] /
  /// [ScannerConfig.autoOrientation].
  final AutoOrientation? autoOrientation;

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
  /// Defaults to pure white (`Color(0xFFFFFFFF)`) so the scanner reads
  /// as a neutral, monochrome instrument that drops into any host app's
  /// palette. Pass a brand colour to tint accents.
  final Color? accentColor;

  /// Colour used when the document is detected but **not yet capturable**
  /// (`tooFar`, `tooClose`, or `tilted`). Defaults to a neutral mid-grey
  /// (`Color(0xFF8C8C8C)`) — readable against the dark preview without
  /// introducing a second hue.
  final Color? warningColor;

  /// Visual style of the detected-quad overlay rendered on top of the
  /// live preview.
  ///
  /// When `null` (default), the drop-in scanner uses its built-in
  /// editorial "reticle" overlay (corner brackets framing the whole
  /// viewfinder, plus highlighted document corners). Pass any value of
  /// [QuadOverlayStyle] to swap in one of the package-shipped looks:
  ///
  /// - `QuadOverlayStyle.outline` — just a stroked polygon
  /// - `QuadOverlayStyle.filled` — stroked polygon + tinted fill
  /// - `QuadOverlayStyle.corners` — corner brackets only
  /// - `QuadOverlayStyle.cornersFilled` — corner brackets + tinted fill
  /// - `QuadOverlayStyle.dots` — filled dots at corners
  /// - `QuadOverlayStyle.dotsLine` — corner dots + hairline polygon
  /// - `QuadOverlayStyle.glow` — blurred halo + stroked polygon
  ///
  /// Status colour follows [accentColor] (aligned/confirming) and
  /// [warningColor] (tilted/too close/too far).
  final QuadOverlayStyle? overlayStyle;

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

  /// Full-replacement builder for the post-capture review screen.
  ///
  /// When non-null, the default [DoclensReviewScreen] is **not** used.
  /// You receive a [DoclensReviewContext] containing the [ScanResult]
  /// plus three callbacks (`onRetake`, `onEditCorners`, `onAccept`) —
  /// invoke them from your custom UI to drive the scanner's state
  /// machine.
  ///
  /// For partial customisation (just the header, just the action row,
  /// etc.) prefer the per-section builders below.
  final DoclensReviewBuilder? reviewBuilder;

  /// Replaces only the **header** of the default review screen. Ignored
  /// when [reviewBuilder] is set.
  final DoclensReviewBuilder? reviewHeaderBuilder;

  /// Replaces only the **cropped-image preview** on the default review
  /// screen. Receives a [DoclensReviewContext] whose
  /// `result.croppedImagePath` is guaranteed non-null when this builder
  /// is invoked. Ignored when [reviewBuilder] is set.
  final DoclensReviewBuilder? reviewImageBuilder;

  /// Replaces only the **empty / warp-error placeholder** on the default
  /// review screen. Invoked when the perspective warp failed or no
  /// cropped output was produced. Ignored when [reviewBuilder] is set.
  final DoclensReviewBuilder? reviewEmptyBuilder;

  /// Replaces only the **bottom action row** (Retake / Edit corners /
  /// Use) on the default review screen. Ignored when [reviewBuilder] is
  /// set.
  final DoclensReviewBuilder? reviewActionsBuilder;

  /// Builder for the screen shown when the camera fails to initialise.
  /// Receives the error message. When `null`, the package ships a
  /// minimalist default. Useful for matching your app's chrome on
  /// permission-denied or hardware-unavailable states.
  final Widget Function(BuildContext context, String message)? errorBuilder;

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
    ImageEnhancement? imageEnhancement,
    AutoOrientation? autoOrientation,
    FlashMode? initialFlashMode,
    CameraLens? initialLens,
    bool? enableTapToFocus,
    bool? enablePinchToZoom,
    int? detectionThrottleHz,
    Color? accentColor,
    Color? warningColor,
    QuadOverlayStyle? overlayStyle,
    Color backgroundColor = Colors.black,
    String appBarTitle = 'Preview',
    String captureHintText = 'Hold steady to capture',
    String retakeLabel = 'Retake',
    String editCornersLabel = 'Edit corners',
    String useLabel = 'Use',
    bool showHint = true,
    bool showCloseButton = true,
    bool enableEditCorners = true,
    DoclensReviewBuilder? reviewBuilder,
    DoclensReviewBuilder? reviewHeaderBuilder,
    DoclensReviewBuilder? reviewImageBuilder,
    DoclensReviewBuilder? reviewEmptyBuilder,
    DoclensReviewBuilder? reviewActionsBuilder,
    Widget Function(BuildContext context, String message)? errorBuilder,
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
          imageEnhancement: imageEnhancement,
          autoOrientation: autoOrientation,
          initialFlashMode: initialFlashMode,
          initialLens: initialLens,
          enableTapToFocus: enableTapToFocus,
          enablePinchToZoom: enablePinchToZoom,
          detectionThrottleHz: detectionThrottleHz,
          accentColor: accentColor,
          warningColor: warningColor,
          overlayStyle: overlayStyle,
          backgroundColor: backgroundColor,
          appBarTitle: appBarTitle,
          captureHintText: captureHintText,
          retakeLabel: retakeLabel,
          editCornersLabel: editCornersLabel,
          useLabel: useLabel,
          showHint: showHint,
          showCloseButton: showCloseButton,
          enableEditCorners: enableEditCorners,
          reviewBuilder: reviewBuilder,
          reviewHeaderBuilder: reviewHeaderBuilder,
          reviewImageBuilder: reviewImageBuilder,
          reviewEmptyBuilder: reviewEmptyBuilder,
          reviewActionsBuilder: reviewActionsBuilder,
          errorBuilder: errorBuilder,
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

  // Default to pure monochrome so the scanner blends into any host UI.
  // Adopters that want a brand tint can still pass `accentColor` /
  // `warningColor` — every internal use is just a `Color`, no hard-coded
  // hues anywhere else.
  Color get _accent => widget.accentColor ?? const Color(0xFFFFFFFF);
  Color get _warning => widget.warningColor ?? const Color(0xFF8C8C8C);

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
      imageEnhancement: widget.imageEnhancement ?? c.imageEnhancement,
      autoOrientation: widget.autoOrientation ?? c.autoOrientation,
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
        builder: (_) {
          // Full-replacement escape hatch: when `reviewBuilder` is set,
          // hand the dev a ready-to-go `DoclensReviewContext` and let
          // them render whatever they want. They still call
          // `review.onAccept` / `onRetake` / `onEditCorners` to drive
          // the state machine.
          if (widget.reviewBuilder != null) {
            return _CustomReviewHost(
              result: result,
              controller: _controller,
              accent: _accent,
              backgroundColor: widget.backgroundColor,
              appBarTitle: widget.appBarTitle,
              retakeLabel: widget.retakeLabel,
              editCornersLabel: widget.editCornersLabel,
              useLabel: widget.useLabel,
              enableEditCorners: widget.enableEditCorners,
              builder: widget.reviewBuilder!,
            );
          }
          return DoclensReviewScreen(
            result: result,
            controller: _controller,
            appBarTitle: widget.appBarTitle,
            accent: _accent,
            backgroundColor: widget.backgroundColor,
            retakeLabel: widget.retakeLabel,
            editCornersLabel: widget.editCornersLabel,
            useLabel: widget.useLabel,
            enableEditCorners: widget.enableEditCorners,
            headerBuilder: widget.reviewHeaderBuilder,
            imageBuilder: widget.reviewImageBuilder,
            emptyBuilder: widget.reviewEmptyBuilder,
            actionsBuilder: widget.reviewActionsBuilder,
          );
        },
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
        return 'Looking for a document';
      case DetectionStatus.noPaper:
        return 'Point at a document';
      case DetectionStatus.tooFar:
        return 'Move closer';
      case DetectionStatus.tooClose:
        return 'Move back';
      case DetectionStatus.tilted:
        return 'Hold the camera flat';
      case DetectionStatus.aligned:
        return 'Hold still';
      case DetectionStatus.confirming:
        return 'Capturing';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initFailed) {
      final message = _initError ?? 'Failed to start scanner';
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, message);
      }
      return _InstrumentErrorScreen(
        bg: widget.backgroundColor,
        message: message,
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
              overlayBuilder: (ctx, quad, status) {
                // When the caller picks a `QuadOverlayStyle`, render that
                // package-shipped family member instead of the screen's
                // built-in reticle. Either way colours follow the
                // user-supplied accent / warning.
                if (widget.overlayStyle != null) {
                  return quadOverlayFor(
                    style: widget.overlayStyle!,
                    quad: quad,
                    status: status,
                    accent: _accent,
                    warning: _warning,
                  );
                }
                return _ReticleOverlay(
                  quad: quad,
                  status: status,
                  accent: _accent,
                  warning: _warning,
                );
              },
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

/// Context object passed to every [DoclensReviewScreen] builder slot.
///
/// Bundles the current scan result, the labels/accent configured on the
/// screen, and the three action callbacks (`onRetake`, `onEditCorners`,
/// `onAccept`) so custom builders can render any UI and still drive the
/// scanner's state machine correctly.
class DoclensReviewContext {
  const DoclensReviewContext({
    required this.result,
    required this.accent,
    required this.backgroundColor,
    required this.appBarTitle,
    required this.retakeLabel,
    required this.editCornersLabel,
    required this.useLabel,
    required this.enableEditCorners,
    required this.onRetake,
    required this.onEditCorners,
    required this.onAccept,
  });

  /// The current scan result. Custom [DoclensReviewScreen.imageBuilder]s
  /// should render `result.croppedImagePath ?? result.rawImagePath`.
  final ScanResult result;
  final Color accent;
  final Color backgroundColor;
  final String appBarTitle;
  final String retakeLabel;
  final String editCornersLabel;
  final String useLabel;
  final bool enableEditCorners;

  /// Dismiss the review screen and return the user to the live preview to
  /// take another shot. Wire this to your retake button.
  final VoidCallback onRetake;

  /// Push the bundled [EditCornersScreen] so the user can nudge the
  /// detected corners by hand, then re-warp the photo.
  final VoidCallback onEditCorners;

  /// Accept the current result. The awaited `Future<ScanResult?>` from
  /// [DoclensScreen.scan] resolves with [result].
  final VoidCallback onAccept;
}

/// Signature for builder slots on [DoclensReviewScreen].
typedef DoclensReviewBuilder = Widget Function(
  BuildContext context,
  DoclensReviewContext review,
);

/// Built-in review screen shown after a successful capture. Lets the user
/// retake, edit corners, or accept the scan.
///
/// Customisation tiers:
///
/// 1. **Strings / colours** — pass `appBarTitle`, `retakeLabel`,
///    `editCornersLabel`, `useLabel`, `accent`, `backgroundColor`.
/// 2. **Per-section builders** — replace any of `headerBuilder`,
///    `imageBuilder`, `emptyBuilder`, `actionsBuilder` with your own
///    widgets while keeping the other defaults.
/// 3. **Full replacement** — pass `DoclensScreen.reviewBuilder` to swap
///    this screen out entirely for your own widget.
///
/// Each builder receives a [DoclensReviewContext] that exposes the
/// current [ScanResult] plus the three action callbacks (`onRetake`,
/// `onEditCorners`, `onAccept`) — invoke them to drive the scanner's
/// state machine.
class DoclensReviewScreen extends StatefulWidget {
  const DoclensReviewScreen({
    super.key,
    required this.result,
    required this.controller,
    this.appBarTitle = 'Preview',
    this.accent = const Color(0xFFFFFFFF),
    this.backgroundColor = Colors.black,
    this.retakeLabel = 'Retake',
    this.editCornersLabel = 'Edit corners',
    this.useLabel = 'Use',
    this.enableEditCorners = true,
    this.headerBuilder,
    this.imageBuilder,
    this.emptyBuilder,
    this.actionsBuilder,
  });

  final ScanResult result;

  /// The same controller that captured the [result] — needed so
  /// "edit corners" can re-warp the raw image.
  final DoclensController controller;

  final String appBarTitle;
  final Color accent;
  final Color backgroundColor;
  final String retakeLabel;
  final String editCornersLabel;
  final String useLabel;
  final bool enableEditCorners;

  /// Replaces the top header (back button + title). The default renders
  /// a serif title with a hairline back chip.
  final DoclensReviewBuilder? headerBuilder;

  /// Replaces the cropped-image preview. Default renders
  /// `result.croppedImagePath` with `BoxFit.scaleDown` inside a framed
  /// surface, falling back to [emptyBuilder] when the path is `null`.
  final DoclensReviewBuilder? imageBuilder;

  /// Replaces the placeholder shown when the warp failed or produced no
  /// cropped output. Default renders a "Could not crop" message.
  final DoclensReviewBuilder? emptyBuilder;

  /// Replaces the bottom action row (Retake / Edit corners / Use).
  /// Default renders ghost buttons + a primary "Use" button — call
  /// `review.onRetake` / `review.onEditCorners` / `review.onAccept` on
  /// tap.
  final DoclensReviewBuilder? actionsBuilder;

  @override
  State<DoclensReviewScreen> createState() => _DoclensReviewScreenState();
}

class _DoclensReviewScreenState extends State<DoclensReviewScreen> {
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
    final review = DoclensReviewContext(
      result: _result,
      accent: widget.accent,
      backgroundColor: widget.backgroundColor,
      appBarTitle: widget.appBarTitle,
      retakeLabel: widget.retakeLabel,
      editCornersLabel: widget.editCornersLabel,
      useLabel: widget.useLabel,
      enableEditCorners: widget.enableEditCorners,
      onRetake: () => Navigator.of(context).pop(false),
      onEditCorners: _editCorners,
      onAccept: () => Navigator.of(context).pop(true),
    );

    final header = widget.headerBuilder?.call(context, review) ??
        _ReviewHeader(
          title: review.appBarTitle,
          accent: review.accent,
          onBack: review.onRetake,
        );
    final body = path == null
        ? (widget.emptyBuilder?.call(context, review) ??
            _ReviewEmpty(
              hasWarpError: review.result.warpError != null,
              editLabel: review.editCornersLabel,
              accent: review.accent,
            ))
        : (widget.imageBuilder?.call(context, review) ??
            _ReviewImage(path: path, accent: review.accent));
    final actions = widget.actionsBuilder?.call(context, review) ??
        _ReviewActions(
          accent: review.accent,
          retakeLabel: review.retakeLabel,
          editCornersLabel: review.editCornersLabel,
          useLabel: review.useLabel,
          enableEditCorners: review.enableEditCorners,
          onRetake: review.onRetake,
          onEditCorners: review.onEditCorners,
          onUse: review.onAccept,
        );

    return Scaffold(
      backgroundColor: widget.backgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            header,
            Expanded(child: body),
            actions,
          ],
        ),
      ),
    );
  }
}

/// Internal host that drives the same state-machine the default review
/// screen does (mutate cropped path after edit-corners, pop with a
/// bool), but delegates the entire UI to a user-supplied builder.
class _CustomReviewHost extends StatefulWidget {
  const _CustomReviewHost({
    required this.result,
    required this.controller,
    required this.accent,
    required this.backgroundColor,
    required this.appBarTitle,
    required this.retakeLabel,
    required this.editCornersLabel,
    required this.useLabel,
    required this.enableEditCorners,
    required this.builder,
  });

  final ScanResult result;
  final DoclensController controller;
  final Color accent;
  final Color backgroundColor;
  final String appBarTitle;
  final String retakeLabel;
  final String editCornersLabel;
  final String useLabel;
  final bool enableEditCorners;
  final DoclensReviewBuilder builder;

  @override
  State<_CustomReviewHost> createState() => _CustomReviewHostState();
}

class _CustomReviewHostState extends State<_CustomReviewHost> {
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
    final review = DoclensReviewContext(
      result: _result,
      accent: widget.accent,
      backgroundColor: widget.backgroundColor,
      appBarTitle: widget.appBarTitle,
      retakeLabel: widget.retakeLabel,
      editCornersLabel: widget.editCornersLabel,
      useLabel: widget.useLabel,
      enableEditCorners: widget.enableEditCorners,
      onRetake: () => Navigator.of(context).pop(false),
      onEditCorners: _editCorners,
      onAccept: () => Navigator.of(context).pop(true),
    );
    return widget.builder(context, review);
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
    required this.accent,
    required this.onClose,
    required this.flashMode,
    required this.onFlash,
  });

  final bool showClose;
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
          const Expanded(child: SizedBox.shrink()),
          _InstrumentIconButton(
            icon: _flashIcon(),
            onTap: onFlash,
            accent: accent,
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
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorderSoft),
        ),
        child: Icon(icon, color: _kTextPrimary, size: 17),
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
                  size: 12,
                  color: _kTextPrimary,
                  weight: FontWeight.w500,
                  letterSpacing: 0.0,
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
            color: widget.color.withValues(alpha: 0.5 + 0.5 * t),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.25 * t),
                blurRadius: 6 * t,
                spreadRadius: 0.5 * t,
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
      child: Center(
        child: _InstrumentShutter(
          accent: accent,
          isCapturing: isCapturing,
          armed: status == DetectionStatus.aligned ||
              status == DetectionStatus.confirming,
          onTap: onCapture,
        ),
      ),
    );
  }
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
          // Shutter stays pure white in all states so it reads as the
          // familiar camera button against the preview, regardless of
          // what `accentColor` the host app passes. The "armed" cue is
          // a subtle white halo, not a colour swap — coloured shutters
          // (e.g. when an adopter sets a brand orange) clash with the
          // live preview underneath.
          const shutterFill = Colors.white;
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _kTextPrimary.withValues(
                    alpha: widget.armed ? 1.0 : 0.85,
                  ),
                  width: 2,
                ),
                boxShadow: widget.armed
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.35),
                          blurRadius: 18,
                          spreadRadius: 0.5,
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
                        ? shutterFill.withValues(alpha: 0.55)
                        : shutterFill,
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
            child: Text(
              title,
              style: _serif(size: 22, italic: true),
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
                  child: Center(
                    child: Image.file(
                      File(path),
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                    ),
                  ),
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
            hasWarpError ? 'Could not crop' : 'No preview',
            style: _mono(
              size: 12,
              color: accent,
              letterSpacing: 0.0,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            hasWarpError
                ? 'We couldn\'t straighten the photo. Tap "$editLabel" to adjust the corners, or retake the photo.'
                : 'No preview is available for this photo.',
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
            label,
            style: _mono(
              size: 13,
              color: _kTextPrimary,
              weight: FontWeight.w500,
              letterSpacing: 0.0,
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
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.arrow_forward, color: _kBgInk, size: 16),
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
                    decoration: const BoxDecoration(
                      color: _kErrorTint,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33FFFFFF),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Camera unavailable',
                    style: _mono(
                      size: 12,
                      color: _kErrorTint,
                      letterSpacing: 0.0,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'We couldn\'t open the camera.',
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
                      'Dismiss',
                      style: _mono(
                        size: 13,
                        color: accent,
                        weight: FontWeight.w600,
                        letterSpacing: 0.0,
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
