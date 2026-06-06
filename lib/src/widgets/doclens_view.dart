import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../quad.dart';
import 'quad_overlay.dart';

typedef QuadOverlayBuilder = Widget Function(
    BuildContext context, Quad? quad, DetectionStatus status);

typedef CaptureButtonBuilder = Widget Function(
    BuildContext context, VoidCallback onTap);

typedef FlashButtonBuilder = Widget Function(
    BuildContext context, FlashMode mode, VoidCallback onCycle);

typedef LowLightHintBuilder = Widget Function(BuildContext context);

typedef DebugOverlayBuilder = Widget Function(
    BuildContext context, Quad? quad, DetectionStatus status, double? fps);

/// The scanner surface. Renders the live camera preview as a `Texture` and
/// composes the developer-supplied builders on top.
///
/// All overlays are opt-in: pass `null` to render nothing for that slot.
/// Use the static `default*` helpers to drop in reasonable defaults.
class DoclensView extends StatefulWidget {
  const DoclensView({
    super.key,
    required this.controller,
    this.overlayBuilder,
    this.captureButtonBuilder,
    this.flashButtonBuilder,
    this.lowLightHintBuilder,
    this.debugOverlayBuilder,
    this.onCapture,
    this.onError,
    this.backgroundColor = Colors.black,
  });

  final DoclensController controller;
  final QuadOverlayBuilder? overlayBuilder;
  final CaptureButtonBuilder? captureButtonBuilder;
  final FlashButtonBuilder? flashButtonBuilder;
  final LowLightHintBuilder? lowLightHintBuilder;
  final DebugOverlayBuilder? debugOverlayBuilder;

  /// Fires for both manual taps on the capture button and auto-capture
  /// events. The two are not currently distinguished — listen on
  /// `controller.autoCaptureStream` if you need to discriminate.
  final void Function(ScanResult)? onCapture;
  final void Function(Object error, StackTrace stack)? onError;
  final Color backgroundColor;

  /// Reasonable default overlay: tinted, stroked polygon whose colour
  /// follows the [DetectionStatus] (acid-lime accent on aligned /
  /// confirming, amber on tilted / too-close / too-far, muted white
  /// while searching).
  ///
  /// Internally this is just `QuadOverlay.filled` with the package's
  /// default palette. Swap to any other [QuadOverlay] constructor — or
  /// the [quadOverlayFor] helper with a [QuadOverlayStyle] enum value —
  /// for a different look.
  static Widget defaultOverlayBuilder(
      BuildContext context, Quad? quad, DetectionStatus status) {
    return QuadOverlay.filled(quad: quad, status: status);
  }

  static Widget defaultCaptureButton(
      BuildContext context, VoidCallback onTap) {
    return _DefaultCaptureButton(onTap: onTap);
  }

  static Widget defaultFlashButton(
      BuildContext context, FlashMode mode, VoidCallback onCycle) {
    return _DefaultFlashButton(mode: mode, onCycle: onCycle);
  }

  static Widget defaultLowLightHint(BuildContext context) =>
      const _DefaultLowLightHint();

  @override
  State<DoclensView> createState() => _DoclensViewState();
}

class _DoclensViewState extends State<DoclensView>
    with WidgetsBindingObserver {
  StreamSubscription<Quad?>? _quadSub;
  StreamSubscription<DetectionStatus>? _statusSub;
  StreamSubscription<ScanResult>? _autoCaptureSub;
  StreamSubscription<bool>? _lowLightSub;
  StreamSubscription<Size>? _previewSizeSub;

  Quad? _quad;
  DetectionStatus _status = DetectionStatus.searching;
  bool _lowLight = false;
  Size? _previewSize;

  // Tap-to-focus visual indicator state. `_focusIndicator` is the tap
  // location in the preview rect; `_focusToken` is bumped on every tap
  // so the `_FocusRing` widget gets a fresh key and replays its
  // animation from scratch.
  Offset? _focusIndicator;
  int _focusToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wireUp(widget.controller);
  }

  @override
  void didUpdateWidget(covariant DoclensView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _teardown();
      _wireUp(widget.controller);
    }
  }

  void _wireUp(DoclensController c) {
    _previewSize = c.previewSize;
    _quadSub = c.quadStream.listen((q) => setState(() => _quad = q));
    _statusSub = c.statusStream.listen((s) => setState(() => _status = s));
    _autoCaptureSub = c.autoCaptureStream.listen((r) {
      widget.onCapture?.call(r);
    });
    _lowLightSub =
        c.lowLightStream.listen((l) => setState(() => _lowLight = l));
    _previewSizeSub = c.previewSizeStream
        .listen((s) => setState(() => _previewSize = s));
  }

  void _teardown() {
    _quadSub?.cancel();
    _statusSub?.cancel();
    _autoCaptureSub?.cancel();
    _lowLightSub?.cancel();
    _previewSizeSub?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = widget.controller;
    if (!c.isInitialized) return;
    final cfg = c.config;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (cfg.pauseOnBackground) {
          c.pause().catchError((Object e, StackTrace s) {
            widget.onError?.call(e, s);
          });
        }
        break;
      case AppLifecycleState.resumed:
        if (cfg.resumeOnForeground) {
          c.resume().catchError((Object e, StackTrace s) {
            widget.onError?.call(e, s);
          });
        }
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _teardown();
    super.dispose();
  }

  Future<void> _handleCapture() async {
    try {
      final result = await widget.controller.capture();
      widget.onCapture?.call(result);
    } catch (e, s) {
      widget.onError?.call(e, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final textureId = c.textureId;
    final preview = _previewSize;

    // The Texture + quad overlay must share the same coordinate rect so
    // that normalized [0,1] corners land on the right pixels. We compose
    // them inside a SizedBox sized to the *buffer's* dimensions, then
    // BoxFit.cover-scale the whole thing to fill the parent.
    Widget previewLayer;
    if (textureId == null) {
      previewLayer = const Center(child: CircularProgressIndicator());
    } else if (preview != null && preview.width > 0 && preview.height > 0) {
      previewLayer = ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: preview.width,
            height: preview.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Texture(textureId: textureId),
                if (widget.overlayBuilder != null)
                  IgnorePointer(
                    child: widget.overlayBuilder!(context, _quad, _status),
                  ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Buffer size not known yet — show the texture stretched as a
      // fallback. The quad overlay is suppressed for this brief window
      // to avoid drawing in the wrong place.
      previewLayer = Texture(textureId: textureId);
    }

    return ColoredBox(
      color: widget.backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    if (!widget.controller.config.enableTapToFocus) return;
                    if (w <= 0 || h <= 0) return;
                    final dx =
                        (details.localPosition.dx / w).clamp(0.0, 1.0);
                    final dy =
                        (details.localPosition.dy / h).clamp(0.0, 1.0);
                    widget.controller
                        .focusAt(Offset(dx, dy))
                        .catchError((Object e, StackTrace s) {
                      widget.onError?.call(e, s);
                    });
                    setState(() {
                      _focusIndicator = details.localPosition;
                      _focusToken++;
                    });
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      previewLayer,
                      if (_focusIndicator != null)
                        _FocusRing(
                          key: ValueKey<int>(_focusToken),
                          position: _focusIndicator!,
                          color: Colors.white,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (widget.lowLightHintBuilder != null && _lowLight)
            Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: Center(child: widget.lowLightHintBuilder!(context)),
            ),
          if (widget.flashButtonBuilder != null)
            Positioned(
              top: 24,
              right: 16,
              child: widget.flashButtonBuilder!(
                  context, c.flashMode, c.cycleFlashMode),
            ),
          if (widget.captureButtonBuilder != null)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: widget.captureButtonBuilder!(context, _handleCapture),
              ),
            ),
          if (widget.debugOverlayBuilder != null)
            Positioned(
              top: 80,
              left: 16,
              child: widget.debugOverlayBuilder!(context, _quad, _status, null),
            ),
        ],
      ),
    );
  }
}

// ---- default UI bits ---------------------------------------------------

class _DefaultCaptureButton extends StatelessWidget {
  const _DefaultCaptureButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: DecoratedBox(
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white)),
        ),
      ),
    );
  }
}

class _DefaultFlashButton extends StatelessWidget {
  const _DefaultFlashButton({required this.mode, required this.onCycle});
  final FlashMode mode;
  final VoidCallback onCycle;

  IconData _icon() {
    switch (mode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.on:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCycle,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
            color: Colors.black54, shape: BoxShape.circle),
        child: Icon(_icon(), color: Colors.white),
      ),
    );
  }
}

class _DefaultLowLightHint extends StatelessWidget {
  const _DefaultLowLightHint();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.black54, borderRadius: BorderRadius.circular(16)),
      child: const Text('Low light — try moving closer to a lamp',
          style: TextStyle(color: Colors.white)),
    );
  }
}

/// Brief "tap-to-focus" indicator. Scales + fades over ~700 ms and then
/// stays at low opacity for a moment so the user sees where their tap
/// landed even after the animation settles.
class _FocusRing extends StatefulWidget {
  const _FocusRing({
    super.key,
    required this.position,
    required this.color,
  });
  final Offset position;
  final Color color;

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

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
        // Scale: 1.6 → 1.0. Opacity: 0.0 → 0.95 over first 25%,
        // then fades back to 0.35 by the end.
        final t = _c.value;
        final scale = 1.6 - 0.6 * t;
        final opacity = t < 0.25
            ? (t / 0.25) * 0.95
            : (0.95 - ((t - 0.25) / 0.75) * 0.6);
        const size = 76.0;
        return Positioned(
          left: widget.position.dx - size / 2,
          top: widget.position.dy - size / 2,
          child: IgnorePointer(
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.rectangle,
                    border: Border.all(color: widget.color, width: 1.5),
                  ),
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
