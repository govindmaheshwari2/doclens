# doclens

A document scanner for Flutter with native edge detection and **100%
Flutter UI you fully control**.

Detection runs natively. On iOS 15+ it uses Apple Vision's
[`VNDetectDocumentSegmentationRequest`](https://developer.apple.com/documentation/vision/vndetectdocumentsegmentationrequest)
with a [`VNDetectRectanglesRequest`](https://developer.apple.com/documentation/vision/vndetectrectanglesrequest)
fallback on iOS 13/14. On Android it uses CameraX with a native Kotlin
Sobel + connected-components + convex-hull pipeline. The detected
4-corner quad is streamed to Dart every frame. The preview is a Flutter
`Texture`. Every overlay, button, and label is a widget you build.

## Three ways to scan

### 1. Drop-in — one line of code

`DoclensScreen` is a polished, opinionated scanner screen owned by the
package. It runs the live preview, auto-captures, and presents a built-in
review screen with retake / edit-corners / accept.

```dart
final ScanResult? result = await DoclensScreen.scan(context);
if (result == null) return;            // user cancelled
final croppedJpegPath = result.croppedImagePath;
```

Customise without dropping down to builders:

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

**Multi-page / batch.** `DoclensMultiScreen` is the batch sibling of
`DoclensScreen` — keep the camera open and collect a stack of pages in one
session. Use it as a one-line route:

```dart
final List<ScanResult>? pages = await DoclensMultiScreen.scan(context);
if (pages == null) return;             // user cancelled
for (final page in pages) {
  print(page.croppedImagePath);
}
```

…or mount it directly as a widget and handle the result yourself via
`onComplete` (the batch analogue of `DoclensScreen.onCapture`). Unlike the
single-page widget, `DoclensMultiScreen` is self-contained — no
`DoclensController` to wire up:

```dart
DoclensMultiScreen(
  maxPages: 20,                    // null = unlimited
  imageEnhancement: ImageEnhancement.enhanced,
  autoOrientation: AutoOrientation.auto,
  onPagesChanged: (pages) {
    // fires on every add / remove / reorder — update a counter, etc.
  },
  onComplete: (pages) {
    // pages: List<ScanResult>, in order, when the user taps "Done"
    for (final page in pages) {
      // page.croppedImagePath  — perspective-warped JPEG
      // page.detectedQuad      — Quad in raw image pixel coords
      // page.warpError         — non-null if the warp failed
    }
    Navigator.of(context).pop();   // with onComplete set, you drive navigation
  },
)
```

The live preview grows a thumbnail rail and a **Done** button; the review
screen's accept button reads **Add**. Tap the rail to open a page manager
that **reorders** (drag) and **deletes** pages, and closing with
uncommitted pages prompts a discard confirmation. Pass `maxPages` to cap
the batch; every other `DoclensScreen` knob (enhancement, auto-orientation,
overlay style, review builders, …) carries over.

### 2. Custom UI — full control with `DoclensView`

When you want a fully branded scanner, mount the `DoclensView` widget
yourself, supply your own builders for the overlay / shutter / flash
button, and own the result flow.

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

Pass `null` to any builder slot to render nothing, the static defaults
for a quick start, or your own widget for full control.

### Quad overlay family

For the most common need — "I just want a different shape on the
detected quad" — the package ships a family of pre-built overlays as
named constructors on `QuadOverlay`:

| Variant | Look |
|---|---|
| `QuadOverlay.outline` | Just a stroked polygon |
| `QuadOverlay.filled` | Stroked polygon + tinted fill (the package default) |
| `QuadOverlay.corners` | Four corner brackets, no connecting lines |
| `QuadOverlay.cornersFilled` | Corner brackets + tinted fill polygon |
| `QuadOverlay.dots` | Four filled dots at the corners |
| `QuadOverlay.dotsLine` | Corner dots + hairline polygon between them |
| `QuadOverlay.glow` | Blurred halo + stroked polygon |

Use one directly in a `DoclensView`'s `overlayBuilder`:

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

Or pick a style on `DoclensScreen.scan(...)` without writing a builder:

```dart
final result = await DoclensScreen.scan(
  context,
  overlayStyle: QuadOverlayStyle.cornersFilled,
  accentColor: Colors.lime,
);
```

Status colour follows `accent` / `warning` automatically: brighter
accent on `confirming`, accent on `aligned`, warning on
`tilted`/`tooClose`/`tooFar`, muted white while `searching`.

### 3. OS-native — `scanWithNativeUI`

Hand off to the OS scanner when you don't need custom branding on the
camera surface.

```dart
final List<String>? paths =
    await DoclensPlatform.instance.scanWithNativeUI(
  pageLimit: 20,
  allowGalleryImport: true,
);
```

On iOS this launches
[`VNDocumentCameraViewController`](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller).
On Android it launches
[`GmsDocumentScanner`](https://developers.google.com/ml-kit/vision/doc-scanner/android).
Both flows are full-screen, multi-page, and uniform on both platforms.
No `DoclensController` is required for this mode.

## Auto-capture with confirmation

Auto-capture is a three-stage state machine that mirrors the rhythm of
Apple's native scanner:

1. The classifier sees a document-shaped quad (`DetectionStatus.aligned`).
2. The quad stays still for `autoCaptureStabilityDuration` (800 ms
   default) — status flips to `DetectionStatus.confirming` and the
   default overlay paints brighter green.
3. If the quad keeps holding still for another
   `autoCaptureConfirmationDelay` (350 ms default), the shutter fires.

Move the camera during the confirmation window to abort. All thresholds
are knobs on `ScannerConfig` and surface as top-level parameters on
`DoclensScreen.scan(...)`.

## Continuous autofocus + tap-to-focus

The native session enables **continuous autofocus** by default on both
platforms (`AVCaptureDevice.focusMode = .continuousAutoFocus` on iOS;
CameraX's default `CONTROL_AF_MODE_CONTINUOUS_PICTURE` on Android), and
opts iOS into the near-distance hint that fits A4-at-arm's-length.

When `ScannerConfig.enableTapToFocus` is `true` (the default), tapping
the preview triggers a one-shot focus + auto-exposure at that point. The
camera reverts to continuous AF after ~3 seconds. The widget renders a
brief focus reticle at the tap location.

You can also drive focus programmatically:

```dart
await controller.focusAt(const Offset(0.5, 0.5));  // centre of frame
```

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

| Mode             | Effect                                                                  | Good for                         |
| ---------------- | ----------------------------------------------------------------------- | -------------------------------- |
| `none` (default) | Pure dewarp, unmodified pixels                                          | Archival, your own preprocessing |
| `grayscale`      | Plain desaturate (no shadow handling)                                   | Neutral look, smaller files      |
| `enhanced`       | **Shadow removal** + background whitening, colour kept ("magic colour") | Photos in uneven light           |
| `blackAndWhite`  | **Shadow removal** + adaptive/Otsu threshold, near-bitonal              | Plain text, OCR on faint print   |

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

## Auto-orientation & rotate

A capture only knows a document's *in-frame* orientation — shoot a page
sideways or upside-down and the dewarped crop comes out the same way. Set
`autoOrientation` to detect the page's text direction on-device and rotate the
crop in 90° steps so it reads upright:

```dart
final result = await DoclensScreen.scan(
  context,
  autoOrientation: AutoOrientation.auto,
);
```

| Mode | Effect |
| --- | --- |
| `none` (default) | Keep the crop's in-frame orientation |
| `auto` | Detect the dominant text direction and rotate the crop upright |

Detection reuses the OS text APIs already on each platform — Apple Vision's
`VNRecognizeTextRequest` on iOS and Play-services ML Kit text recognition on
Android — so **no model is bundled** (the Android model is delivered on demand
by Google Play services, exactly like `scanWithNativeUI`). The crop is read at
each of the four 90° rotations and turned to whichever reads as the most
confident text; a blank or purely graphical page (no confident text) is left
untouched. Like enhancement, it runs on the cropped output only — the raw image
is never rotated — and travels on `ScannerConfig`, so it applies to captures
and to re-warps via `EditCornersScreen`.

For a **manual** rotate control (e.g. a button in your review UI), call the
controller directly — `quarterTurns` is clockwise and normalized modulo 4, so
`-1` and `3` both turn one step the respective way:

```dart
final rotatedPath = await controller.rotateImage(scan.croppedImagePath!, 1);
```

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
`CIPerspectiveCorrection`. Both pixel orientation and EXIF orientation
are handled correctly — see [`doc/decisions.md`](doc/decisions.md).

The native UI flow uses `VNDocumentCameraViewController`.

### Android

Minimum **API 21**. `android.permission.CAMERA` is merged into the host
manifest automatically.

Detection uses CameraX with a pure-Kotlin Sobel-based pipeline on the
live-preview path (no OpenCV, no on-device ML model bundling). Capture
uses `ImageCapture` + `android.graphics.Matrix.setPolyToPoly`.

The native UI flow uses ML Kit's `GmsDocumentScanner`, which is delivered
on demand by Google Play services. Gracefully fails with
`ScannerUnavailableException` on devices without Play services.

## API surface

- **`DoclensScreen`** — drop-in single-page scanner. `DoclensScreen.scan(ctx)`
  pushes a full-screen route, awaits a `ScanResult?`, and pops itself
  when the user accepts or cancels; or mount the widget directly and use
  `onCapture`.
- **`DoclensMultiScreen`** — drop-in multi-page / batch scanner.
  `DoclensMultiScreen.scan(ctx)` awaits a `List<ScanResult>?`; or mount the
  widget directly and use `onComplete`. Thumbnail rail, reorder/delete
  manager, `maxPages` cap.
- **`DoclensController`** — owns a session. Streams: `quadStream`,
  `statusStream`, `autoCaptureStream`, `lowLightStream`,
  `previewSizeStream`. Methods: `initialize()`, `capture()`,
  `warpImage()`, `rotateImage()`, `focusAt()`, `setFlashMode()`,
  `cycleFlashMode()`, `switchCamera()`, `pause()`, `resume()`, `dispose()`.
- **`DoclensView`** — Flutter widget rendering preview + your overlays.
  Builder slots: `overlayBuilder`, `captureButtonBuilder`,
  `flashButtonBuilder`, `lowLightHintBuilder`, `debugOverlayBuilder`.
  Handles tap-to-focus when `ScannerConfig.enableTapToFocus` is true.
- **`EditCornersScreen`** — drag-the-corners helper with re-warp on
  save.
- **`QuadOverlay`** + **`QuadOverlayStyle`** — family of pre-built
  overlay widgets (`outline`, `filled`, `corners`, `cornersFilled`,
  `dots`, `dotsLine`, `glow`) with status-driven colour. Pass the enum
  via `DoclensScreen.overlayStyle` or use a constructor directly inside
  an `overlayBuilder`.
- **`recognizeText()`** — on-device OCR over an image path. On
  `DoclensController` or directly on `DoclensPlatform.instance`; needs no
  camera session. Returns an **`OcrResult`** (`text`, `blocks`, `lines`,
  `imageSize`) with per-block / per-line bounding boxes and confidence.
- **`scanWithNativeUI()`** on `DoclensPlatform.instance` — full
  native-modal scan, returns `List<String>?`.
- **`ScannerConfig`** — every feature flag with a sensible default
  (auto-capture timing, smoothing window, detection throttle, JPEG
  quality, image enhancement, auto-orientation, flash, lens, lifecycle,
  telemetry, tap-to-focus, pinch-to-zoom).
- **`Quad`** — 4-point TL/TR/BR/BL with `area`, `centroid`, `contains`,
  `interpolate`, `maxCornerDistance`, `scaleToSize`.
- **`ScanResult`** — `croppedImagePath`, `rawImagePath`, `detectedQuad`,
  `rawImageSize`, `warpError`.
- **`StabilityTracker`** + **`QuadSmoother`** — pure Dart helpers,
  exposed for tests or custom pipelines.
- **`DetectionStatus`** — `searching`, `tooFar`, `tooClose`, `tilted`,
  `aligned`, `confirming`, `noPaper`.
- **Exceptions** — `ScannerPermissionException`,
  `ScannerUnavailableException`, `ScannerInitializationException`,
  `ScannerCaptureException`.

## On-device OCR (text recognition)

Pull the text *out* of a scan. `recognizeText` runs full text recognition on
any image on disk — typically a capture's `croppedImagePath` — and returns the
transcript plus per-block / per-line bounding boxes and confidence:

```dart
final result = await DoclensScreen.scan(
  context,
  imageEnhancement: ImageEnhancement.blackAndWhite, // cleanest for OCR
);
if (result?.croppedImagePath == null) return;

final ocr = await DoclensPlatform.instance.recognizeText(
  imagePath: result!.croppedImagePath!,
);
print(ocr.text);                                   // the full transcript
for (final line in ocr.lines) {
  print('${line.text}  @ ${line.boundingBox}  (${line.confidence})');
}
```

It needs no camera session (no `initialize()`), so the call lives on the
platform instance and works on any JPEG/PNG on disk. If you already manage a
`DoclensController`, the same method is on it too:

```dart
final ocr = await controller.recognizeText(somePath);
```

`OcrResult` exposes `text` (blocks joined by newlines), `blocks` (each an
`OcrBlock` with `lines`, a pixel-space `boundingBox`, and on Android a
`recognizedLanguage`), and a flattened `lines` getter (`OcrLine` — `text`,
`boundingBox`, `confidence`). All bounding boxes are in the recognised image's
pixel coordinates (origin top-left); use `OcrResult.imageSize` to map them onto
a scaled preview. A blank or purely graphical page yields an empty result
(`OcrResult.isEmpty`) rather than an error.

Like auto-orientation, recognition reuses the OS text APIs already on each
platform — Apple Vision's `VNRecognizeTextRequest` (run at the `.accurate`
level) on iOS and Play-services ML Kit text recognition on Android — so **no
model is bundled** (the Android model is delivered on demand by Google Play
services, exactly like the OS-native scanner).

## What this package deliberately does NOT do

- Multi-page PDF export — returns image paths; assemble a PDF yourself.
- Web or desktop targets.

## Documentation

- [Architecture](doc/architecture.md) — diagram of the Dart ↔ native
  pipeline and threading rules.
- [Decisions](doc/decisions.md) — every non-obvious design choice with
  citations to Apple / Google docs.

## License

MIT — see [LICENSE](LICENSE).
