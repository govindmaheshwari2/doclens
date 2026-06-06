## 0.1.0

Initial release.

**Custom-UI scanner (the package's value proposition)**

- Live camera preview as a Flutter `Texture` (no platform views).
- Native edge detection on iOS — `VNDetectDocumentSegmentationRequest`
  (the Core ML detector used by VisionKit) on iOS 15+, with a docs-tuned
  `VNDetectRectanglesRequest` fallback on iOS 13/14.
- Native edge detection on Android — pure-Kotlin Sobel +
  connected-components + convex-hull approximation (no OpenCV, no ML
  Kit on the live-preview path).
- Streams normalized `Quad` to Dart at a configurable throttle rate
  (default 15 Hz).
- Two-stage auto-capture with confirmation phase
  (`DetectionStatus.confirming`) — mirrors VisionKit's "hold still" cue,
  configurable thresholds and durations.
- Full-resolution still capture with native perspective warp
  (`CIPerspectiveCorrection` on iOS, `Matrix.setPolyToPoly` on Android),
  EXIF orientation baked into pixel layout.
- Graceful fallback when warp fails — `ScanResult.warpError` is surfaced,
  raw image and quad still returned.
- `EditCornersScreen` with draggable handles, customizable builders, and
  re-warp callback.
- Median-of-N corner smoothing (`QuadSmoother`) to kill single-frame
  jitter.
- Flash / torch toggle, camera switching, pause/resume on app lifecycle.
- Low-light detection emitted on the status stream.
- Preview-size event so the overlay coordinate space always matches the
  rendered preview pixels.
- 100% builder-driven UI: every overlay and button is yours to style.
- `ScannerConfig` with feature flags for auto-capture timing, smoothing,
  detection throttle, JPEG quality, flash mode, lens, lifecycle, and
  telemetry — all with sensible defaults.
- Typed exceptions: `ScannerPermissionException`,
  `ScannerUnavailableException`, `ScannerInitializationException`,
  `ScannerCaptureException`.

**Native-UI scanner (one-line opt-in)**

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
- `docs/architecture.md`, `docs/decisions.md` (every non-obvious
  decision cited against Apple / Google docs), `docs/migration.md`,
  `docs/tuning.md`, `docs/verification/`.
