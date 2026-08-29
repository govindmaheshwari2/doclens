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
- **Large-document scan** — `DoclensLargeDocScreen` captures a document too
  big for one frame as overlapping pieces (tap a `+` on any edge, line the
  next shot up against an overlap ghost, watch a miniview fill in), then
  stitches them into a single image.
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

**Large documents.** `DoclensLargeDocScreen` is the drop-in for a page too
big to fit in one frame — a long contract, a poster, a whiteboard. The user
captures one piece, taps a `+` on any edge of the composite, and lines the
next shot up against a translucent **overlap ghost** of the previous piece;
a **miniview** shows the whole document forming. On **Done** the pieces are
stitched into one image and the route returns its path:

```dart
final String? path = await DoclensLargeDocScreen.scan(context);
if (path == null) return;              // user cancelled
// `path` is the stitched composite image on disk.
```

Every piece of chrome is overridable, true to the package's "you own the
UI" stance — `plusButtonBuilder`, `miniviewBuilder`, `hintBuilder`,
`captureButtonBuilder`, plus `accentColor`, `overlapFraction`, and
`ghostOpacity`:

```dart
DoclensLargeDocScreen(
  accentColor: Theme.of(context).colorScheme.primary,
  overlapFraction: 0.3,                // how much of the last piece to ghost
  hintBuilder: (ctx, edge) => MyCoachHint(edge: edge),
  miniviewBuilder: (ctx, canvas) => MyPageMap(canvas: canvas),
)
```

The capture flow is built on injectable pieces you can also use directly for
a fully custom UI: `LargeDocCanvas` (the 2-D piece grid), `LargeDocSession`
(the capture → review → merge state machine), `LargeDocAligner` (overlap
correction; the default `ManualPlacementAligner` trusts the hand alignment),
and `LargeDocMerger` (`CanvasLargeDocMerger` pastes pieces at their grid
slots). Swap in your own aligner or merger via the constructor.

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

### Sharpness gate — no blurry captures

When `ScannerConfig.enableSharpnessGate` is `true` (the default),
auto-capture also waits for the frame to be in focus before firing, not
just geometrically aligned. Once the document aligns, the controller locks
focus on the quad's centroid and holds the shutter, and status reports
`DetectionStatus.focusing` so the default overlay shows a "focusing, hold
steady" hint.

Focus is judged on the native side from a per-frame variance-of-Laplacian
sharpness measured inside the quad, surfaced as `DetectionEvent.sharpness`.
A fixed threshold doesn't work, since sharpness numbers swing with scene
and distance, so a frame must clear `sharpnessFloor` (`8.0` default) and
then plateau near the top of a short rolling window. If focus hasn't
cleared by `autoCaptureFocusTimeout` (2500 ms default), capture fires
anyway so nobody gets stuck; the user can review and re-shoot. Set
`enableSharpnessGate: false` for the old geometry-only behaviour.

### Dark documents — detection polarity (Android)

The Android detector segments each frame by thresholding around the frame's
own mean brightness, and by default it keeps the **brighter** side: paper on
a desk. A document *darker* than what it's lying on — a dark ID card, a
saturated trading card, a glossy photo on a white desk — falls on the other
side of that split, so the surface wins the search and the status sticks at
`searching` / `noPaper`.

Two knobs on `ScannerConfig` steer it:

```dart
const ScannerConfig(
  // brighter (default) | darker | auto
  detectionPolarity: DetectionPolarity.darker,
  // luma bias past the frame mean, 0-128 (default 20)
  detectionThresholdOffset: 20,
);
```

`DetectionPolarity.auto` runs both polarities on every frame and keeps
whichever candidate looks more document-like — solid, away from the frame
edges, and large — which is the setting for a mixed pile where you don't
know what the next item looks like. It roughly doubles per-frame detection
cost; detection runs on a 256 px luma buffer, so that's still cheap, but
measure it on low-end devices before raising `detectionThrottleHz` too.

`detectionThresholdOffset` is how far past the frame mean a pixel has to be
to count as document. Lower it (`8`–`12`) when the document barely separates
from its background (an off-white receipt on a white desk); raise it
(`30`–`45`) to keep shadows and specular highlights out of the document's
component.

Both settings also travel with `controller.detectInImage(path)`, so gallery
imports segment the same way the live preview does.

**iOS ignores both.** Detection there goes through Apple Vision, which is
contrast-agnostic and finds dark documents natively — which is why the same
card scans fine on iOS today.

## Continuous autofocus + tap-to-focus

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

While a corner is dragged, a **magnifier loupe** shows the region under
the finger so the point being placed is never hidden. It is on by default
(`showMagnifier`) and tunable via `magnifierSize` and `magnifierScale`;
pass a `magnifierBuilder` to supply a custom loupe widget (return `null`
to fall back to the bundled one).

## Gallery import — run the pipeline on an existing photo

The whole **detect → edit → warp** flow also works without the camera, on a
photo the user already has. `detectInImage` runs the same native edge
detector the live preview uses on a still image on disk, so you can pick a
photo from the gallery and dewarp it like a fresh capture:

```dart
// Pick a photo however you like (e.g. the `image_picker` package).
final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
if (picked == null) return;

// 1. Detect — native edge detection on the still image.
final detection = await controller.detectInImage(picked.path);
if (detection == null) return; // couldn't read the image

// 2. Edit — seed EditCornersScreen with the detected corners (or a 10%
//    inset when nothing was found), 3. Warp on save.
final warpedPath = await Navigator.of(context).push<String>(
  MaterialPageRoute(
    builder: (_) => EditCornersScreen(
      imagePath: picked.path,
      initialQuad: detection.quadIn,   // pixel-space, ready to use
      imageSize: detection.imageSize,
      onSave: (quad) => controller.warpImage(picked.path, quad),
    ),
  ),
);
```

`detectInImage` returns an `ImageDetection` with the quad in normalized
`[0,1]` coords (or `null` when nothing document-like is found) plus the
image's EXIF-upright pixel size; `quadIn` gives you the same quad already
scaled into pixel coordinates. Like `warpImage` / `rotateImage` /
`recognizeText`, it's a pure file operation — no `initialize()` or camera
session required. The example app's **Gallery import** entry shows the full
flow end to end.

## Platform support — mobile, desktop & web

The **live scanner** (camera preview + streaming edge detection) is native and
runs on **Android and iOS**. Everywhere else the package no longer hard-fails:
the pure-compute half of the pipeline has a **pure-Dart fallback** built on
`dart:ui`, so the *import → edit-corners → warp* flow keeps working off mobile.

| Capability | Android / iOS | Desktop (macOS/Windows/Linux) | Web |
| --- | --- | --- | --- |
| Live camera + edge detection | ✅ native | ❌ (throws `ScannerUnavailableException`) | ❌ |
| `detectInImage` (import) | ✅ native detector | ✅ Dart (null quad → manual crop) | ⚠️ bytes only |
| `warpImage` (perspective dewarp) | ✅ native | ✅ Dart homography | ⚠️ bytes only |
| `rotateImage` | ✅ native | ✅ Dart | ⚠️ bytes only |
| `EditCornersScreen` | ✅ | ✅ | ⚠️ needs a filesystem |
| Image enhancement | ✅ native | ✅ Dart (grayscale / contrast / Otsu) | ✅ on bytes |
| OCR (`recognizeText`) | ✅ native | ❌ empty result | ❌ empty result |

Gate your UI on the capability flags instead of catching exceptions:

```dart
if (DoclensPlatform.supportsLiveScan) {
  // Show the live-camera entry point (Android / iOS).
  final result = await DoclensScreen.scan(context);
} else if (DoclensPlatform.supportsImportFlow) {
  // Desktop: run the same detect → edit → warp flow on a picked file.
  final detection = await controller.detectInImage(path);
  // … EditCornersScreen → controller.warpImage(path, quad)
}
```

**Notes on the fallback.** It writes **PNG** (lossless), so `jpegQuality` is
ignored; `autoOrientation` is a no-op (upright detection needs on-device OCR);
and `detectInImage` returns a `null` quad (no Dart edge detector) so `quadIn`
seeds a 10% inset the user drags into place — a **manual crop**. The homography
warp, output-size derivation, and enhancement passes are otherwise faithful to
the native behaviour.

**Web.** The public API is path-based, which needs a filesystem web doesn't
have, so the path methods throw a clear `ScannerUnavailableException` there.
The underlying engine is web-safe, though: decode your imported image to bytes
and call the exported `PerspectiveWarp.warpBytes(bytes, quad)` /
`ImageEnhance.apply(image, enhancement)` building blocks directly.

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

Detection uses CameraX with a pure-Kotlin Sobel pipeline on the preview path — no OpenCV, no bundled ML model. Because segmentation is a luma threshold around the frame mean, which side of that mean the document sits on is a setting: see [Dark documents — detection polarity](#dark-documents--detection-polarity-android). Capture uses `ImageCapture` plus `android.graphics.Matrix.setPolyToPoly`.

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
- **`DoclensLargeDocScreen`** — drop-in scanner for a document too big for
  one frame. `DoclensLargeDocScreen.scan(ctx)` awaits the stitched image
  path (`String?`). Captures overlapping pieces via a `+`-per-edge UI with
  an overlap ghost and a miniview. Overridable chrome (`plusButtonBuilder`,
  `miniviewBuilder`, `hintBuilder`, `captureButtonBuilder`) and injectable
  `LargeDocAligner` / `LargeDocMerger`; the underlying `LargeDocCanvas` and
  `LargeDocSession` are exported for fully custom UIs.
- **`DoclensController`** — owns a session. Streams: `quadStream`,
  `statusStream`, `autoCaptureStream`, `lowLightStream`,
  `previewSizeStream`. Methods: `initialize()`, `capture()`,
  `warpImage()`, `rotateImage()`, `detectInImage()`, `focusAt()`,
  `setFlashMode()`, `cycleFlashMode()`, `switchCamera()`, `pause()`,
  `resume()`, `dispose()`.
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
- **`detectInImage()`** — run native edge detection on a still image (e.g.
  a gallery import). On `DoclensController` or directly on
  `DoclensPlatform.instance`; needs no camera session. Returns an
  **`ImageDetection`** (`quad`, `imageSize`, `quadIn`) to feed
  `EditCornersScreen` + `warpImage` — the full detect → edit → warp pipeline
  off a picked photo.
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

> Script coverage follows the recogniser: Android uses ML Kit's default
> **Latin-script** model; iOS Vision recognises its full language set. For
> non-Latin scripts on Android, run a dedicated ML Kit script model on the
> cropped path yourself.

## What this package deliberately does NOT do

- Multi-page PDF export — returns image paths; assemble a PDF yourself.
- Web or desktop targets.

## More docs

- [Architecture](doc/architecture.md) — the Dart ↔ native pipeline and the threading rules.
- [Decisions](doc/decisions.md) — every non-obvious design choice, with links to the Apple and Google docs behind it.

## License

MIT — see [LICENSE](LICENSE).
