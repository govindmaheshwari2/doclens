# doclens

A document scanner for Flutter. Edge detection runs in native code (Apple Vision on iOS, a Kotlin pipeline on Android), but every pixel of UI is a Flutter widget you build and control.

The detected document outline — a 4-corner quad — is streamed to Dart on every frame. The camera preview is a Flutter `Texture`. So the overlay, the shutter button, the flash toggle, the labels: all yours. No native UI bleeds through unless you ask for it.

## Pick your level of control

There are three ways to use this package, from "one line and done" to "I'll draw everything myself."

### 1. Drop-in: one line

`DoclensScreen` is a finished scanner screen. It handles the live preview, auto-capture, and a review step with retake / edit-corners / accept. You get a cropped JPEG back.

```dart
final ScanResult? result = await DoclensScreen.scan(context);
if (result == null) return;            // user cancelled
final croppedJpegPath = result.croppedImagePath;
```

You can tune it without writing any builders:

```dart
final result = await DoclensScreen.scan(
  context,
  accentColor: Theme.of(context).colorScheme.primary,
  autoCaptureStabilityDuration: const Duration(milliseconds: 600),
  jpegQuality: 95,
  useLabel: 'Save',
);
```

Every parameter has dartdoc explaining its default and when you'd want to change it.

### 2. Custom UI: bring your own widgets

Want a scanner that matches your brand? Mount `DoclensView` yourself and supply builders for the overlay, shutter, and flash button. You own the result flow.

```dart
class _MyScannerState extends State<MyScanner> {
  final controller = DoclensController();

  @override void initState() { super.initState(); controller.initialize(); }
  @override void dispose()    { controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return DoclensView(
      controller: controller,
      overlayBuilder: DoclensView.defaultOverlayBuilder,
      captureButtonBuilder: DoclensView.defaultCaptureButton,
      flashButtonBuilder: DoclensView.defaultFlashButton,
      onCapture: (ScanResult result) {
        // result.croppedImagePath  — perspective-warped JPEG
        // result.rawImagePath      — full uncropped JPEG
        // result.detectedQuad      — Quad in raw image pixel coords
        // result.rawImageSize      — pixel size of the raw image
        // result.warpError         — non-null if the warp failed
      },
    );
  }
}
```

Each builder slot takes three things: `null` to draw nothing, a static default for a quick start, or your own widget.

#### Just want a different shape on the quad?

That's the most common ask, so the package ships a set of ready-made overlays as named constructors on `QuadOverlay`:

| Variant | Look |
|---|---|
| `QuadOverlay.outline` | A stroked polygon, nothing else |
| `QuadOverlay.filled` | Stroked polygon with a tinted fill (this is the default) |
| `QuadOverlay.corners` | Four corner brackets, no connecting lines |
| `QuadOverlay.cornersFilled` | Corner brackets plus a tinted fill |
| `QuadOverlay.dots` | A filled dot at each corner |
| `QuadOverlay.dotsLine` | Corner dots joined by a hairline |
| `QuadOverlay.glow` | A blurred halo behind a stroked polygon |

Drop one straight into an `overlayBuilder`:

```dart
DoclensView(
  controller: controller,
  overlayBuilder: (ctx, quad, status) => QuadOverlay.corners(
    quad: quad,
    status: status,
    accent: Colors.lime,
  ),
  ...,
);
```

Or name a style on `DoclensScreen.scan(...)` and skip the builder entirely:

```dart
final result = await DoclensScreen.scan(
  context,
  overlayStyle: QuadOverlayStyle.cornersFilled,
  accentColor: Colors.lime,
);
```

The overlay color tracks detection status on its own: a brighter accent while `confirming`, your accent when `aligned`, the warning color when the doc is `tilted` / `tooClose` / `tooFar`, and muted white while still `searching`.

### 3. OS-native: hand it to the system scanner

If you don't need custom branding on the camera, just call the OS scanner.

```dart
final List<String>? paths =
    await DoclensPlatform.instance.scanWithNativeUI(
  pageLimit: 20,
  allowGalleryImport: true,
);
```

iOS opens [`VNDocumentCameraViewController`](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller); Android opens ML Kit's [`GmsDocumentScanner`](https://developers.google.com/ml-kit/vision/doc-scanner/android). Both are full-screen and multi-page. You don't need a `DoclensController` for this one.

## How auto-capture works

Auto-capture is a three-step state machine, modeled on the feel of Apple's native scanner:

1. The detector finds a document-shaped quad → `DetectionStatus.aligned`.
2. The quad holds still for `autoCaptureStabilityDuration` (800 ms by default) → status flips to `confirming` and the default overlay turns a brighter green.
3. It stays still for another `autoCaptureConfirmationDelay` (350 ms) → the shutter fires.

Move the camera during that window and the capture aborts. Every threshold lives on `ScannerConfig` and is also a parameter on `DoclensScreen.scan(...)`.

## Focus

The native session runs continuous autofocus by default on both platforms (`.continuousAutoFocus` on iOS, `CONTROL_AF_MODE_CONTINUOUS_PICTURE` on Android), and on iOS it adds the near-distance hint that suits holding an A4 page at arm's length.

Tap-to-focus is on by default (`ScannerConfig.enableTapToFocus`). Tap the preview and you get a one-shot focus plus auto-exposure at that point, a focus reticle painted where you tapped, and a return to continuous AF after about 3 seconds.

You can also focus from code:

```dart
await controller.focusAt(const Offset(0.5, 0.5));  // centre of frame
```

## Editing corners after capture

If the detected quad isn't quite right, let the user drag the corners and re-warp.

```dart
EditCornersScreen(
  imagePath: scan.rawImagePath,
  initialQuad: scan.detectedQuad,
  imageSize: scan.rawImageSize,
  onSave: (finalQuad) => controller.warpImage(scan.rawImagePath, finalQuad),
);
```

Every handle, line, and button here is overridable through builders too.

## Image enhancement & shadow removal

By default the cropped output is a pure dewarp — the original pixels,
straightened, with nothing else touched. Set `imageEnhancement` to apply a
post-warp filter to the **cropped** image (the raw image is never modified):

```dart
final result = await DoclensScreen.scan(
  context,
  imageEnhancement: ImageEnhancement.blackAndWhite, // best for OCR
);
```

| Mode | Effect | Good for |
| --- | --- | --- |
| `none` (default) | Pure dewarp, unmodified pixels | Archival, your own preprocessing |
| `grayscale` | Plain desaturate (no shadow handling) | Neutral look, smaller files |
| `enhanced` | **Shadow removal** + background whitening, colour kept ("magic colour") | Photos in uneven light |
| `blackAndWhite` | **Shadow removal** + adaptive/Otsu threshold, near-bitonal | Plain text, OCR on faint print |

`enhanced` and `blackAndWhite` genuinely remove uneven lighting and soft
shadows — not just global contrast. The technique is the classic
illumination-division ("flatten") used by document scanners: estimate the
lighting and divide it out. It runs entirely on-device with **no bundled
model and no extra dependency**:

- **iOS** uses Apple's built-in `CIDocumentEnhancer` (iOS 16+), falling back
  to `CIHighlightShadowAdjust` (local shadow lift) on older OSes;
  `blackAndWhite` desaturates then binarises with `CIColorThresholdOtsu`.
- **Android** estimates the background from a heavily downscaled copy and
  divides it out per pixel (adaptive-mean thresholding for `blackAndWhite`).

Enhancement applies to both the capture's cropped output and any re-warp
done through `EditCornersScreen` (it travels on the controller's config).
It's a knob on `ScannerConfig` too, so it works from every entry point.

> For the absolute best shadow/glare removal, the OS-native scanners
> (`scanWithNativeUI`) apply Apple's / Google's own document cleanup — at the
> cost of using their full-screen UI instead of this package's custom flow.

## Platform setup

### iOS

Minimum iOS 13.0. Add this to `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Used to scan documents</string>
```

On iOS 15+ detection uses `VNDetectDocumentSegmentationRequest`, and falls back to a docs-tuned `VNDetectRectanglesRequest` on iOS 13/14. Capture goes through `AVCapturePhotoOutput`, and the perspective warp uses `CIPerspectiveCorrection`. Both pixel and EXIF orientation are handled — the details are in [`doc/decisions.md`](doc/decisions.md). The native flow uses `VNDocumentCameraViewController`.

### Android

Minimum API 21. `android.permission.CAMERA` merges into your manifest automatically.

Detection uses CameraX with a pure-Kotlin Sobel pipeline on the preview path — no OpenCV, no bundled ML model. Capture uses `ImageCapture` plus `android.graphics.Matrix.setPolyToPoly`.

The native flow uses ML Kit's `GmsDocumentScanner`, delivered on demand by Google Play services. On a device without Play services it throws `ScannerUnavailableException` rather than crashing.

## API reference

- **`DoclensScreen`** — the drop-in route. `DoclensScreen.scan(ctx)` pushes a full-screen route, waits for a `ScanResult?`, and pops itself on accept or cancel.
- **`DoclensController`** — owns a camera session. Streams: `quadStream`, `statusStream`, `autoCaptureStream`, `lowLightStream`, `previewSizeStream`. Methods: `initialize()`, `capture()`, `warpImage()`, `focusAt()`, `setFlashMode()`, `cycleFlashMode()`, `switchCamera()`, `pause()`, `resume()`, `dispose()`.
- **`DoclensView`** — the widget that renders the preview plus your overlays. Builder slots: `overlayBuilder`, `captureButtonBuilder`, `flashButtonBuilder`, `lowLightHintBuilder`, `debugOverlayBuilder`. Handles tap-to-focus when enabled.
- **`EditCornersScreen`** — the drag-the-corners helper, re-warps on save.
- **`QuadOverlay`** + **`QuadOverlayStyle`** — the pre-built overlays (`outline`, `filled`, `corners`, `cornersFilled`, `dots`, `dotsLine`, `glow`) with status-driven color. Pass the enum through `DoclensScreen.overlayStyle`, or use a constructor directly in an `overlayBuilder`.
- **`scanWithNativeUI()`** on `DoclensPlatform.instance` — the full native-modal scan, returns `List<String>?`.
- **`ScannerConfig`** — every feature flag with a sane default: auto-capture timing, smoothing window, detection throttle, JPEG quality, flash, lens, lifecycle, telemetry, tap-to-focus, pinch-to-zoom.
- **`Quad`** — a 4-point TL/TR/BR/BL shape with `area`, `centroid`, `contains`, `interpolate`, `maxCornerDistance`, `scaleToSize`.
- **`ScanResult`** — `croppedImagePath`, `rawImagePath`, `detectedQuad`, `rawImageSize`, `warpError`.
- **`StabilityTracker`** + **`QuadSmoother`** — pure-Dart helpers, exposed so you can use them in tests or your own pipeline.
- **`DetectionStatus`** — `searching`, `tooFar`, `tooClose`, `tilted`, `aligned`, `confirming`, `noPaper`.
- **Exceptions** — `ScannerPermissionException`, `ScannerUnavailableException`, `ScannerInitializationException`, `ScannerCaptureException`.

## What this package leaves to you

- OCR — you get image paths back; pair it with a text-recognition library.
- PDF export — also image paths; assemble the PDF yourself.
- B&W / grayscale / color filters.
- Web and desktop. iOS and Android only.

## More docs

- [Architecture](doc/architecture.md) — the Dart ↔ native pipeline and the threading rules.
- [Decisions](doc/decisions.md) — every non-obvious design choice, with links to the Apple and Google docs behind it.

## License

MIT — see [LICENSE](LICENSE).
