## Unreleased

**Dark documents now detect on Android — `detectionPolarity`**

- The Android detector segmented every frame by keeping the *brighter* side
  of the frame's mean luma, so it only ever found documents lighter than
  their surroundings. A dark ID card, a saturated trading card, or a glossy
  photo on a light desk lost the component search to the background and left
  `DetectionStatus` at `searching` / `noPaper`. iOS was unaffected — Apple
  Vision is contrast-agnostic.
- New `ScannerConfig.detectionPolarity` (`DetectionPolarity.brighter`,
  `.darker`, `.auto`). `brighter` is the default and is exactly the previous
  behavior; `darker` mirrors the threshold for documents darker than their
  background; `auto` runs both polarities per frame and keeps whichever
  candidate looks more document-like — solid, clear of the frame edges, and
  large — for roughly twice the per-frame detection cost.
- New `ScannerConfig.detectionThresholdOffset` (default `20`, range `0`–`128`)
  exposes the luma bias that was hardcoded in the detector. Lower it when a
  document barely separates from its background, raise it to keep shadows and
  highlights out of the document's component.
- Both settings travel with `DoclensController.detectInImage(path)` too, so
  gallery imports segment the way the live preview does.
- Additive and default-preserving: existing apps behave exactly as before.
  Both are Android-only and are ignored on iOS.
- Note for anyone implementing `DoclensPlatform` themselves:
  `detectInImage` gained an optional `config` parameter, so an override with
  the old signature needs the new parameter added. Callers are unaffected.
- Fixed: `DoclensScreen` dropped `enableSharpnessGate`, `sharpnessFloor`, and
  `autoCaptureFocusTimeout` when merging its top-level overrides into a
  supplied `ScannerConfig`, so those three fell back to their defaults on that
  entry point.

## 0.0.8

**Web & desktop support — the package no longer hard-fails off mobile**

- The pure-compute half of the pipeline now has a **pure-Dart fallback** built
  on `dart:ui`, so the *import → edit-corners → warp* flow works on desktop
  (and as a safety net anywhere the native plugin is missing) instead of
  throwing an opaque `MissingPluginException`. `warpImage` does a true
  perspective (homography) dewarp, `rotateImage` rotates, `detectInImage`
  reports the image size with a `null` quad (seeding a manual crop), and
  `recognizeText` returns an empty result.
- **Graceful degradation** — camera/native-only methods (`initialize`,
  `capture`, flash/focus/zoom, `scanWithNativeUI`) now surface a clear
  `ScannerUnavailableException` off Android/iOS rather than a raw plugin error.
- **Capability flags** — `DoclensPlatform.supportsLiveScan` and
  `DoclensPlatform.supportsImportFlow` let you branch your UI without
  try/catch.
- **New building blocks** exported for web (where the path-based API can't run):
  `PerspectiveWarp.warpBytes(bytes, quad)` and `ImageEnhance.apply(image,
  enhancement)` operate purely on bytes / `ui.Image`.
- Fallback output is **PNG** (lossless — `jpegQuality` ignored) and
  `autoOrientation` is a no-op off-device (needs on-device OCR). See the new
  **Platform support** section in the README for the full capability matrix.

## 0.0.7

**Large-document scan — capture a document too big for one frame**

- New `DoclensLargeDocScreen` lets the user build one document out of several
  overlapping captures: shoot a fragment, tap a `+` on any edge of the
  growing composite, and line the next shot up against a translucent
  **overlap ghost** of the previous piece. A **miniview** shows the whole
  document taking shape; *Done* stitches the pieces into a single image.
  Supports long pages (a row/column), L-shapes, and 2×2 blocks.
- True to the package's "you own the UI" stance, every piece of chrome is
  overridable — `plusButtonBuilder`, `miniviewBuilder`, `hintBuilder`,
  `captureButtonBuilder`, plus `accentColor`, `overlapFraction`, and
  `ghostOpacity`. The capture pipeline, state machine, grid model,
  alignment, and stitching are all injectable.
- Underlying pieces are exported for custom UIs: `LargeDocCanvas` (2-D grid
  placement), `LargeDocSession` (the capture→review→merge state machine),
  `LargeDocAligner` (overlap-band correction; default `ManualPlacementAligner`
  trusts the hand alignment), and `LargeDocMerger` (`CanvasLargeDocMerger` pastes
  pieces at their grid slots — seam feathering is a future step).

**Gallery import — detect → edit → warp on an existing photo**

- New `DoclensController.detectInImage(path)` (and the underlying
  `DoclensPlatform.detectInImage`) runs the native edge detector — the same
  one that powers the live preview — on a still image already on disk, such
  as one the user imported from the gallery. It returns an `ImageDetection`
  with the detected quad in normalized `[0,1]` coords (or `null` when nothing
  document-like is found) plus the image's EXIF-upright pixel size.
- This makes the package's whole pipeline available without the camera: feed
  `ImageDetection.imageSize` and `ImageDetection.quadIn` to
  `EditCornersScreen`, then `warpImage` with the user-adjusted corners.
  `ImageDetection.quadIn` falls back to a 10%-inset rectangle so there are
  always draggable corners to start from. It's a pure file operation — no
  `initialize()` / camera session required.
- The example app gains a "Gallery import" entry demonstrating the full
  detect → edit → warp flow on a picked photo.

## 0.0.6

**Sharpness-gated auto-capture**

- Auto-capture now waits for the frame to be in focus before firing, not
  just geometrically aligned, so it no longer shoots a well-framed but
  blurry page. When a document aligns, the controller locks focus on the
  quad's centroid and holds the shutter until sharpness clears threshold.
  The new `DetectionStatus.focusing` reports this state so the UI can show
  a "focusing, hold steady" hint, and the drop-in scanner already does.
- Focus is judged from a per-frame variance-of-Laplacian sharpness value
  via the new `SharpnessTracker`. A fixed threshold doesn't work here,
  since the numbers swing with scene and distance, so a frame must clear
  an absolute floor and then plateau near the top of a short rolling
  window. The native side (iOS and Android `SharpnessEstimator`) measures
  the in-quad sharpness per frame and reports it on the new
  `DetectionEvent.sharpness` field; `null` means "no signal" and never
  blocks capture.
- Configurable via `ScannerConfig`: `enableSharpnessGate` (default `true`;
  set `false` for the old geometry-only behavior), `autoCaptureFocusTimeout`
  (default 2500 ms, after which capture fires anyway so nobody gets stuck),
  and `sharpnessFloor` (default `8.0`). Losing alignment resets the focus
  episode so the next alignment re-focuses.

**Edit-corners magnifier loupe**

- `EditCornersScreen` now shows a magnifying loupe while a corner is
  dragged, so the finger no longer hides the point being placed. Configurable
  via `showMagnifier` (default `true`), `magnifierSize`, and
  `magnifierScale`, with an optional `magnifierBuilder` to supply a custom
  loupe widget (return `null` to fall back to the bundled one).

- New `ScanResult.copyWith` for persisting an updated `croppedImagePath`
  (e.g. after a manual rotate or re-warp) back into a result you're holding.

**On-device OCR — new `recognizeText` API**

- New **`recognizeText`** runs full on-device text recognition over any image
  on disk (typically a capture's `croppedImagePath`) and returns the transcript
  plus structured geometry. Available on `DoclensController.recognizeText(path)`
  and directly on `DoclensPlatform.instance.recognizeText(imagePath: …)` — it is
  a pure file operation, so it needs no camera session or `initialize()` call.
- New result types: **`OcrResult`** (`text`, `blocks`, flattened `lines`,
  `imageSize`), **`OcrBlock`** (`text`, pixel-space `boundingBox`, `lines`,
  and on Android a `recognizedLanguage`), and **`OcrLine`** (`text`,
  `boundingBox`, `confidence`). All bounding boxes are in the recognised image's
  pixel coordinates (origin top-left). A blank/graphical page (or an
  unavailable recogniser) yields an empty `OcrResult` rather than an error.
- Reuses the OS text APIs already present on each platform — Apple Vision's
  `VNRecognizeTextRequest` (run at the `.accurate` level) on iOS and
  Play-services ML Kit text recognition on Android — so **no model is bundled**
  and **no new dependency is added**; the Android model is delivered on demand
  by Google Play services. OCR was previously listed as a non-goal; it is now
  supported.

## 0.0.5

**Multi-page / batch scanning — new `DoclensMultiScreen`**

- New drop-in **`DoclensMultiScreen`**, the batch sibling of
  `DoclensScreen`, with the same two usage styles:
  - `DoclensMultiScreen.scan(context)` pushes a route and returns
    `Future<List<ScanResult>?>` (or `null` if cancelled);
  - mount the widget directly and receive the pages via `onComplete`
    (the batch analogue of `DoclensScreen.onCapture`).
- The user captures any number of pages without leaving the camera and
  taps "Done" to finish. Each page still flows through the same review
  screen (retake / edit corners / accept).
- The live preview grows a thumbnail rail of captured pages, a page-count
  chip, and a "Done" button; the review screen's accept button reads "Add".
- Tapping the rail opens a full-screen page manager to **reorder** (drag)
  and **delete** pages. Closing a session with uncommitted pages — via the
  close button or system back — prompts a discard confirmation.
- Optional `maxPages` cap, plus configurable labels (`addPageLabel`,
  `doneLabel`), discard-dialog strings, and an `onPagesChanged` callback.
- Every behaviour/UI knob from `DoclensScreen` (enhancement,
  auto-orientation, flash, overlay style, …) carries over. (Multi-page
  mode is also available on `DoclensScreen` itself via the `multiPage`
  flag, which `DoclensMultiScreen` wraps.)
- The post-capture review now returns the *edited* `ScanResult` when the
  user adjusts corners before accepting (previously the pre-edit result
  was returned). `DoclensReviewScreen` pops a `ScanResult?` instead of a
  `bool`.
- Scratch images are now cleaned up instead of accumulating in the temp
  directory: a retaken/cancelled capture, a crop superseded by edit-corners,
  a page deleted from a batch, and a discarded multi-page session all delete
  their backing files. Files for pages you keep (returned from the scanner)
  are never touched — the caller owns them.

**Auto-orientation (upright) for the cropped output, plus a manual rotate API**

- New `ScannerConfig.autoOrientation` (and matching `DoclensScreen` parameter):
  `none` (default, unchanged behaviour) or `auto`, which detects the captured
  page's dominant text direction on-device and rotates the crop in 90° steps so
  it reads upright. A blank or purely graphical page (no confident text) is left
  untouched.
  - iOS: Apple Vision's `VNRecognizeTextRequest` (no bundled model).
  - Android: Play-services ML Kit Latin text recognition, delivered on demand —
    exactly like `scanWithNativeUI`'s document scanner; no model bundled in the
    host APK.
- Applies to both the capture's cropped output and re-warps via
  `EditCornersScreen` (it travels on `ScannerConfig` and the `warpImage`
  channel call). The raw image is never rotated.
- New `DoclensController.rotateImage(path, quarterTurns)` (and `rotateImage`
  channel method) for a manual rotate control — `quarterTurns` is clockwise and
  normalized modulo 4. Writes a new file; the source is left untouched.

**Image enhancement & shadow removal on the cropped output**

- New `ScannerConfig.imageEnhancement` (and matching `DoclensScreen`
  parameter) applies a post-warp filter to the cropped document:
  `none` (default, unchanged behaviour), `grayscale` (plain desaturate),
  `enhanced` (shadow-corrected colour "magic colour"), or `blackAndWhite`
  (shadow-corrected near-bitonal — best for OCR on faint text).
- `enhanced` and `blackAndWhite` genuinely remove uneven lighting and soft
  shadows via on-device illumination-division ("flatten"), not just global
  contrast. No model is bundled and no extra dependency is added.
  - iOS: Apple's `CIDocumentEnhancer` (iOS 16+) with a `CIHighlightShadowAdjust`
    fallback on older OSes; `blackAndWhite` desaturates then binarises with
    `CIColorThresholdOtsu`.
  - Android: background estimated from a heavily downscaled copy and divided
    out per pixel; `blackAndWhite` uses adaptive-mean thresholding.
- Applies to both the capture's cropped output and re-warps performed via
  `EditCornersScreen` (it travels on the controller's config and the
  `warpImage` channel call). The raw image is never modified.

**Android: crop lands in the wrong position after editing corners**

- On Android, large captures are decoded downscaled (`decodeDownscaled`,
  max 3000 px), so `rawImageSize` and the reported quad are in that
  downscaled pixel space. When no EXIF rotation was needed, capture
  returned the *original full-resolution* file as `rawImagePath` while
  those coordinates described the downscaled image. A later re-warp via
  `EditCornersScreen` decoded that file at full resolution and applied the
  half-scale quad, cropping the wrong region (typically the top-left
  quadrant). Capture now always persists the upright bitmap it measured,
  so `rawImagePath`'s pixel dimensions match `rawImageSize` and the quad.

## 0.0.4

**Resume grace window prevents immediate re-capture**

- `DoclensController.resume()` now resets stability tracking and suppresses
  auto-capture for 1 200 ms (`resumeAutoCaptureGrace`) after a resume. Without
  this, a document still aligned in frame from before the pause would re-trip
  auto-capture within a frame or two of resuming, giving the user no chance to
  reposition after a retake.
- Any in-progress confirmation phase is also cancelled on resume so the
  two-stage capture timer starts fresh.

## 0.0.3

**Android preview no longer stretches**

- The live preview now reports its size in the rotated (displayed)
  orientation instead of the sensor-natural landscape buffer size, so a
  portrait preview fills a portrait screen without `BoxFit.cover`
  stretching it. Driven off CameraX's `setTransformationInfoListener`,
  with identical sizes deduped and 0x0 events dropped so a stale or
  repeat emission can't corrupt the layout.

**Overlay shows from the first frame**

- `DoclensView` now paints the quad overlay during the brief window
  between the first camera frame and the first `previewSize` event.
  Previously the overlay was missing for that window; the corners are
  normalized `[0,1]` so they align to the texture rect immediately.

**Primary button**

- The default primary button in `DoclensScreen` is now icon-only
  (forward arrow), dropping the inline label + icon row for a cleaner
  control.

## 0.0.2

**EditCornersScreen**

- AppBar styled with white foreground, no elevation, and weighted title text.
- Bottom buttons are now full-width (`Expanded`) with 12 px gap between them.
- `onSave` return value (warped image path) is passed back via `Navigator.pop`.
- New parameters: `resetLabel`, `saveLabel`, `savingLabel` — customise button
  text without supplying a full `buttonBuilder`.
- New parameters: `buttonStyle` (`ButtonStyle?`) and `buttonTextStyle`
  (`TextStyle?`) — style the default buttons without a custom builder.

## 0.0.1

Initial release.

**Drop-in scanner**

- `DoclensScreen.scan(context)` — one-line, full-screen scanner route
  with live preview, auto-capture, and a built-in review screen
  (retake / edit corners / accept). Returns `Future<ScanResult?>`.
- Every visible string and behaviour knob (auto-capture timing, JPEG
  quality, flash mode, lens, accent colours, labels, edit-corners
  toggle) exposed as a top-level parameter with rich dartdoc.

**Custom UI**

- `DoclensView` Flutter widget rendering a `Texture`-backed live
  camera preview plus your overlay / shutter / flash button builders.
  Every slot accepts `null` to render nothing, a static default for
  quick start, or a custom widget.
- `DoclensController extends ChangeNotifier` owning the session.
  Streams: `quadStream`, `statusStream`, `autoCaptureStream`,
  `lowLightStream`, `previewSizeStream`. Methods: `initialize`,
  `capture`, `warpImage`, `focusAt`, `setFlashMode`, `cycleFlashMode`,
  `switchCamera`, `pause`, `resume`, `dispose`.
- `QuadOverlay` family of pre-built overlay widgets with named
  constructors: `outline`, `filled`, `corners`, `cornersFilled`,
  `dots`, `dotsLine`, `glow`. Status-driven colour follows
  `accent` / `warning`. The drop-in `DoclensScreen` exposes an
  `overlayStyle: QuadOverlayStyle` parameter so consumers can switch
  the look without writing a builder.

**Native detection pipeline**

- iOS — `VNDetectDocumentSegmentationRequest` (the Core ML detector
  used by VisionKit) on iOS 15+, with a docs-tuned
  `VNDetectRectanglesRequest` fallback on iOS 13/14.
- Android — pure-Kotlin Sobel + connected-components + convex-hull
  approximation on CameraX (no OpenCV, no on-device ML model bundling
  on the live-preview path).
- Streams normalised `Quad` to Dart at a configurable throttle rate
  (default 15 Hz).
- Two-stage auto-capture with `DetectionStatus.confirming` phase,
  configurable thresholds and durations.

**Focus**

- Continuous autofocus enabled by default on both platforms (iOS
  `.continuousAutoFocus` + near-distance hint; Android CameraX
  `CONTROL_AF_MODE_CONTINUOUS_PICTURE`).
- Tap-to-focus on the preview triggers a one-shot focus + auto-exposure
  at the tap point, with a focus-reticle animation. Reverts to
  continuous AF after ~3 seconds. Programmatic access via
  `controller.focusAt(Offset)`.

**Capture + warp**

- Full-resolution still capture with native perspective warp
  (`CIPerspectiveCorrection` on iOS, `Matrix.setPolyToPoly` on Android),
  EXIF orientation baked into pixel layout.
- Graceful fallback when warp fails — `ScanResult.warpError` is
  surfaced, raw image and quad still returned.
- `EditCornersScreen` with draggable handles, customisable builders,
  and re-warp callback.

**Quality of life**

- Median-of-N corner smoothing (`QuadSmoother`) to kill single-frame
  jitter.
- Flash / torch toggle, camera switching, pause/resume on app
  lifecycle.
- Low-light detection emitted on the status stream.
- Preview-size event so the overlay coordinate space always matches the
  rendered preview pixels.
- `ScannerConfig` with feature flags for auto-capture timing, smoothing,
  detection throttle, JPEG quality, flash mode, lens, lifecycle,
  telemetry, tap-to-focus, pinch-to-zoom — all with sensible defaults.
- Typed exceptions: `ScannerPermissionException`,
  `ScannerUnavailableException`, `ScannerInitializationException`,
  `ScannerCaptureException`.

**OS-native scanner (one-line opt-in)**

- `scanWithNativeUI()` launches the OS-native scanner UI:
  `VNDocumentCameraViewController` on iOS,
  `GmsDocumentScanner` (Google Play services) on Android.
- Returns the cropped page image paths or `null` on user cancel,
  consistently on both platforms.
- Pre-launch Google Play services check on Android with
  `ScannerUnavailableException` on devices without GMS.

**Tests + docs**

- Pure-Dart unit tests for `Quad`, `StabilityTracker`,
  `StatusClassifier`, and `QuadSmoother`.
- `doc/architecture.md` with the Dart ↔ native pipeline diagram.
- `doc/decisions.md` — every non-obvious design choice cited against
  Apple / Google docs.
