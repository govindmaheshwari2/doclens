# doclens

A document scanner for Flutter with native edge detection and **100%
Flutter UI you fully control** — plus a one-line escape hatch to the
OS-native scanner UI when you don't need custom branding.

Detection runs natively. On iOS 15+ it uses Apple Vision's
[`VNDetectDocumentSegmentationRequest`](https://developer.apple.com/documentation/vision/vndetectdocumentsegmentationrequest)
with a [`VNDetectRectanglesRequest`](https://developer.apple.com/documentation/vision/vndetectrectanglesrequest)
fallback on iOS 13/14. On Android it uses CameraX with a native Kotlin
Sobel + connected-components + convex-hull pipeline. The detected
4-corner quad is streamed to Dart every frame. The preview is a Flutter
`Texture`. Every overlay, button, and label is a widget you build.

## Two ways to scan

### 1. Custom UI (the default value proposition)

You build the scanner screen in Flutter widgets; the package handles the
camera, detection, auto-capture timing, and perspective warp.

```dart
class MyScanner extends StatefulWidget {
  @override State<MyScanner> createState() => _MyScannerState();
}

class _MyScannerState extends State<MyScanner> {
  final controller = DoclensController();

  @override void initState() {
    super.initState();
    controller.initialize();
  }

  @override void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DoclensView(
      controller: controller,
      overlayBuilder: DoclensView.defaultOverlayBuilder,
      captureButtonBuilder: DoclensView.defaultCaptureButton,
      flashButtonBuilder: DoclensView.defaultFlashButton,
      onCapture: (ScanResult result) {
        // result.croppedImagePath  — perspective-warped JPEG path
        // result.rawImagePath      — full uncropped JPEG path
        // result.detectedQuad      — Quad in raw image pixel coords
        // result.rawImageSize      — pixel size of the raw image
        // result.warpError         — non-null if the warp itself failed
      },
    );
  }
}
```

### 2. Native OS scanner

When you want Apple's / Google's full-screen native scanner UI without
building your own, call:

```dart
final List<String>? paths =
    await DoclensPlatform.instance.scanWithNativeUI(
  pageLimit: 20,
  allowGalleryImport: true,
);
// `paths` is null if the user cancelled, otherwise the cropped page JPEGs.
```

On iOS this launches
[`VNDocumentCameraViewController`](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller).
On Android it launches
[`GmsDocumentScanner`](https://developers.google.com/ml-kit/vision/doc-scanner/android).
Both flows are full-screen, multi-page, and uniform on both platforms.

No `DoclensController` is required for this mode — call it from
anywhere.

## Auto-capture, the way VisionKit does it

Auto-capture is a three-stage state machine that mirrors the rhythm of
Apple's native scanner:

1. The classifier sees a document-shaped quad (`DetectionStatus.aligned`).
2. The quad stays still for `autoCaptureStabilityDuration` (800 ms
   default) — status flips to `DetectionStatus.confirming` and the
   default overlay paints brighter green.
3. If the quad keeps holding still for another
   `autoCaptureConfirmationDelay` (350 ms default), the shutter fires.

Move the camera during the confirmation window to abort. All thresholds
are knobs on `ScannerConfig`.

## Customization

Every overlay is a builder. Pass `null` to render nothing, the static
defaults for a quick start, or your own widget for full control:

```dart
DoclensView(
  controller: controller,
  config: const ScannerConfig(
    enableAutoCapture: true,
    autoCaptureStabilityDuration: Duration(milliseconds: 800),
    autoCaptureCornerThreshold: 0.02, // fraction of frame
    detectionThrottleHz: 15,
  ),
  overlayBuilder: (ctx, quad, status) => MyQuadOverlay(quad: quad),
  captureButtonBuilder: (ctx, onTap) => MyBrandShutter(onTap: onTap),
  flashButtonBuilder: (ctx, mode, onCycle) =>
      MyFlashChip(mode: mode, onCycle: onCycle),
)
```

The example app ships two shipping options end-to-end:

- The drop-in `DoclensScreen` (one-line call).
- `native_os_style.dart` — full-screen native scanner via `scanWithNativeUI`.

For maximum customisation, use the `DoclensView` widget directly
with your own builders — every overlay slot is optional and overridable.

## Edit corners after capture

```dart
EditCornersScreen(
  imagePath: scan.rawImagePath,
  initialQuad: scan.detectedQuad,
  imageSize: scan.rawImageSize,
  onSave: (finalQuad) => controller.warpImage(scan.rawImagePath, finalQuad),
);
```

Every handle, line, and button on `EditCornersScreen` is overridable via
builders.

## Platform setup

### iOS

Minimum **iOS 13.0**. Add to `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Used to scan documents</string>
```

Detection uses `VNDetectDocumentSegmentationRequest` on iOS 15+ and
gracefully falls back to a docs-tuned `VNDetectRectanglesRequest` on iOS
13/14. Capture uses `AVCapturePhotoOutput`; perspective warp uses
`CIPerspectiveCorrection`. Both pixel-orientation and EXIF orientation
are handled correctly — see [`doc/decisions.md`](doc/decisions.md).

The native UI flow uses `VNDocumentCameraViewController`.

### Android

Minimum **API 21**. `android.permission.CAMERA` is merged into the host
manifest automatically.

Detection uses CameraX + a pure-Kotlin Sobel detector (no OpenCV, no ML
Kit on the live-preview path — the package stays lean). Capture uses
`ImageCapture` + `android.graphics.Matrix.setPolyToPoly`.

The native UI flow uses ML Kit's `GmsDocumentScanner`, which is delivered
on demand by Google Play services — no on-device model bundling, no
`<meta-data>` requirement. Gracefully fails with
`ScannerUnavailableException` on devices without Play services
(Huawei, Amazon Fire).

## API surface

- **`DoclensController`** — owns a session. Streams:
  `quadStream`, `statusStream`, `autoCaptureStream`, `lowLightStream`,
  `previewSizeStream`. Methods: `initialize()`, `capture()`,
  `warpImage()`, `setFlashMode()`, `cycleFlashMode()`, `switchCamera()`,
  `pause()`, `resume()`, `dispose()`.
- **`DoclensView`** — Flutter widget rendering preview + your
  overlays. Builder slots: `overlayBuilder`, `captureButtonBuilder`,
  `flashButtonBuilder`, `lowLightHintBuilder`, `debugOverlayBuilder`.
- **`EditCornersScreen`** — drag-the-corners helper with re-warp on save.
- **`scanWithNativeUI()`** on `DoclensPlatform.instance` — full
  native-modal scan, returns `List<String>?`.
- **`ScannerConfig`** — every feature flag with a sensible default
  (auto-capture timing, smoothing window, detection throttle, JPEG
  quality, flash, lens, lifecycle, telemetry).
- **`Quad`** — 4-point TL/TR/BR/BL with `area`, `centroid`, `contains`,
  `interpolate`, `maxCornerDistance`, `scaleToSize`.
- **`ScanResult`** — `croppedImagePath`, `rawImagePath`, `detectedQuad`,
  `rawImageSize`, `warpError`.
- **`StabilityTracker`** + **`QuadSmoother`** — pure Dart helpers, exposed
  for tests or custom pipelines.
- **`DetectionStatus`** — `searching`, `tooFar`, `tooClose`, `tilted`,
  `aligned`, `confirming`, `noPaper`.
- **Exceptions** — `ScannerPermissionException`,
  `ScannerUnavailableException`, `ScannerInitializationException`,
  `ScannerCaptureException`.

## What this package deliberately does NOT do

- OCR — returns image paths only; pair with a text-recognition library.
- Multi-page PDF export — returns image paths; assemble a PDF yourself.
- B&W / grayscale / colour filters.
- Web or desktop targets.

## Documentation

- [Architecture](doc/architecture.md) — diagram of the Dart ↔ native
  pipeline and threading rules.
- [Decisions](doc/decisions.md) — every non-obvious design choice with
  citations to Apple / Google docs.
- [Tuning](doc/tuning.md) — auto-capture / status threshold methodology.

## License

MIT — see [LICENSE](LICENSE).
