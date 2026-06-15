## 0.0.5

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
