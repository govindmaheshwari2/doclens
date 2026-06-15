# doclens

A document scanner for Flutter. Edge detection runs in native code (Apple Vision on iOS, a Kotlin pipeline on Android), but every pixel of UI is a Flutter widget you build and control.

The detected document outline — a 4-corner quad — is streamed to Dart on every frame. The camera preview is a Flutter `Texture`. So the overlay, the shutter button, the flash toggle, the labels: all yours. No native UI bleeds through unless you ask for it.

## Features

- **Native edge detection** — Apple Vision on iOS, a pure-Kotlin CameraX
  pipeline on Android. The 4-corner quad is streamed to Dart every frame.
- **Three ways to scan** — a one-line drop-in screen, a fully branded
  custom UI on the package widget, or a hand-off to the OS-native scanner.
- **Multi-page / batch scanning** — `DoclensMultiScreen` keeps the camera
  open, collects a stack of pages with a thumbnail rail, and returns them
  in order; reorder and delete from a built-in page manager.
- **Auto-capture with confirmation** — fires once the document is framed
  and held still, with a brief "hold still" window you can abort.
- **Continuous autofocus + tap-to-focus**, programmatic focus, flash/torch
  modes, and camera switch.
- **Perspective-correct crop** — the detected quad is dewarped to a clean,
  flat document image.
- **Image enhancement & shadow removal** — grayscale, shadow-corrected
  colour ("magic colour"), and near-bitonal black-and-white for OCR. Runs
  on-device with no bundled model and no extra dependency.
- **Auto-orientation & rotate** — straighten the crop upright from its
  detected text direction, plus a manual `rotateImage` API.
- **Edit corners after capture** — drag-the-corners helper with re-warp on
  save; every handle and button is overridable.

## Three ways to scan

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

| Variant                     | Look                                                     |
| --------------------------- | -------------------------------------------------------- |
| `QuadOverlay.outline`       | A stroked polygon, nothing else                          |
| `QuadOverlay.filled`        | Stroked polygon with a tinted fill (this is the default) |
| `QuadOverlay.corners`       | Four corner brackets, no connecting lines                |
| `QuadOverlay.cornersFilled` | Corner brackets plus a tinted fill                       |
| `QuadOverlay.dots`          | A filled dot at each corner                              |
| `QuadOverlay.dotsLine`      | Corner dots joined by a hairline                         |
| `QuadOverlay.glow`          | A blurred halo behind a stroked polygon                  |

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

A capture only knows a document's _in-frame_ orientation — shoot a page
sideways or upside-down and the dewarped crop comes out the same way. Set
`autoOrientation` to detect the page's text direction on-device and rotate the
crop in 90° steps so it reads upright:

```dart
final result = await DoclensScreen.scan(
  context,
  autoOrientation: AutoOrientation.auto,
);
```

| Mode             | Effect                                                         |
| ---------------- | -------------------------------------------------------------- |
| `none` (default) | Keep the crop's in-frame orientation                           |
| `auto`           | Detect the dominant text direction and rotate the crop upright |

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

## What this package leaves to you

- OCR — returns image paths only; pair with a text-recognition library.
  (`AutoOrientation.auto` reads text to find "upright" but never returns it.)
- Multi-page PDF export — returns image paths; assemble a PDF yourself.
- Web or desktop targets.

## More docs

- [Architecture](doc/architecture.md) — the Dart ↔ native pipeline and the threading rules.
- [Decisions](doc/decisions.md) — every non-obvious design choice, with links to the Apple and Google docs behind it.

## License

MIT — see [LICENSE](LICENSE).
