# Decisions

## Texture vs PlatformView for preview

**Chose `Texture`.** Avoids the platform-view ↔ Flutter compositor cost
and the well-known stability/scroll issues with `AndroidView`.
`AVCaptureSession` and CameraX both produce pixel buffers that can be
forwarded to `FlutterTexture` / `SurfaceTexture` cleanly. Trade-off:
overlay paints run in Flutter, so the developer pays the compositor cost
for each frame, but that is the same cost they would have paid for any
other Flutter UI on top.

## Android detection: OpenCV vs ML Kit vs native Kotlin

**Chose a native Kotlin Sobel + connected-component + convex-hull detector
for v0.1.**

- **OpenCV**: ~60 MB AAR, drives up app size dramatically. Adds NDK build
  complexity. Quality would be best, but the size cost is unjustifiable
  at v0.1.
- **ML Kit Document Scanner SDK**: only exposes a full-screen UI flow,
  not a streaming corner-quad API — incompatible with our "100% Flutter
  UI" goal.
- **ML Kit Object Detection**: detects categories of objects, not
  document quads. Wrong fit.
- **Native Kotlin pipeline**: Sobel + adaptive threshold + boundary trace
  + convex-hull approximation. ~250 lines, zero dependencies, lean APK.
  Quality is adequate for bright paper on dark/contrasting backgrounds.
  For v0.2: gate an OpenCV variant behind an opt-in flag for users who
  need maximum robustness on cluttered backgrounds.

This decision is reversible — see `QuadDetector.detect()`; a future
variant could ship as a separate package extension.

## JPEG quality default: 92

Subjective sweet spot from comparing 80/90/92/95/100 on a set of
receipts. 92 is visually indistinguishable from 100 in the dropoff tests
while being ~3× smaller.

## Auto-capture defaults

- `cornerThreshold = 8.0 px` in screen space — looser than 4 (too
  jittery on real hands) but tighter than 16 (waits too long).
- `stabilityDuration = 1500 ms` — short enough not to feel sluggish,
  long enough to filter out brief hold-stills while reframing.

These are the values to revisit during real-device tuning.

## iOS Vision orientation

**Vision receives `.up`, not `.right`.** The video output's connection
is set to `videoOrientation = .portrait`, which per Apple's QA1744
*physically rotates* the delivered `CVPixelBuffer` (hardware accelerated,
not metadata-only — `AVCaptureVideoDataOutput` is the one capture output
that actually rewrites pixels). The buffer arriving in our delegate is
already upright portrait; passing `.right` to `VNImageRequestHandler`
would ask Vision to rotate it again, permuting the labels on
`VNRectangleObservation.topLeft` / `.topRight` / etc. relative to the
preview. That is the classic "flashes at wrong position, then disappears"
symptom seen during development.

Front camera with `isVideoMirrored = true` on the connection: pass
`.up` (not `.upMirrored`). Mirroring is also applied to the buffer at
the connection level — telling Vision `.upMirrored` would double-mirror.

References:
- [QA1744 — Setting the orientation of video with AV Foundation](https://developer.apple.com/library/archive/qa/qa1744/_index.html)
- [`AVCaptureConnection.videoOrientation`](https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videoorientation)
- [`VNImageRequestHandler`](https://developer.apple.com/documentation/vision/vnimagerequesthandler)
- [`VNRectangleObservation`](https://developer.apple.com/documentation/vision/vnrectangleobservation)
- machinethink.net — *How to display Vision bounding boxes*
- Apple Developer Forums — *VNDetectRectanglesRequest orientation*

## iOS capture: bake EXIF orientation into pixels before warp

**`UIImage.uprightCGImage()` re-renders through `UIGraphicsImageRenderer`.**

`AVCapturePhotoOutput`'s connection orientation behaves *opposite* to
`AVCaptureVideoDataOutput`'s: it writes EXIF metadata (tag 0x0112) into
the JPEG container but does **not** physically rotate the pixels. The
saved bytes are sensor-native landscape with an orientation tag — there
is no flag to make `fileDataRepresentation()` deliver physically rotated
output.

`UIImage(data:)` reads the EXIF tag into `imageOrientation`, but the
underlying `cgImage` is "the image data in its original orientation"
(per Apple's `UIImage` reference) — i.e. the landscape sensor pixels.

We can't feed those landscape pixels to `CIPerspectiveCorrection`
together with our portrait-normalized quad: the coordinate spaces don't
match, and the resulting crop is a slice of the raw frame that includes
non-quad pixels. The documented fix is to re-render the `UIImage`
through a `UIGraphicsImageRenderer`, which honors `imageOrientation`,
producing a `CGImage` whose pixel layout is the visually-correct upright
view. After that, portrait-normalized quad × portrait pixel dimensions
selects the right rectangle, and we also write that upright JPEG to disk
so consumers reading `rawImagePath` get what the user saw.

References:
- WWDC 2016 Session 511 — *Advances in iOS Photography*
- [QA1744 — Orientation across capture outputs](https://developer.apple.com/library/archive/qa/qa1744/_index.html)
- [`AVCapturePhotoOutput.fileDataRepresentation()`](https://developer.apple.com/documentation/avfoundation/avcapturephoto/2873914-filedatarepresentation)
- [`UIImage`](https://developer.apple.com/documentation/uikit/uiimage) (specifically `cgImage` and `imageOrientation`)
- [`UIGraphicsImageRenderer`](https://developer.apple.com/documentation/uikit/uigraphicsimagerenderer)
- Apple sample — *AVCam: Building a Camera App*
- Apple Developer Forums — *videoOrientation on AVCaptureVideoDataOutput vs AVCapturePhotoOutput*

## Auto-capture gate compares against fresh classification, not emitted status

**Use `_classifier.classify(quad)` directly in the auto-capture gate, not
`_status`.**

The controller emits `DetectionStatus.confirming` to the status stream
during the confirmation phase so the UI can pulse the overlay. That same
emitted value lives in `_status`. If we gate auto-capture on
`_status == DetectionStatus.aligned`, the very first frame inside the
confirmation window flips `_status` to `confirming`, the gate fails, and
`_cancelConfirmation()` fires immediately — auto-capture is permanently
stuck.

The fix is conceptually small but easy to regress: keep two distinct
values per frame. `classified` is the raw classifier output used for the
auto-capture gate; `_status` is the *UI-facing* enum that includes the
confirmation overlay state. They drift apart on purpose, and the gate
must use the raw one.

There are no docs to cite for this — it's a local invariant. The cost
of getting it wrong is high (silent auto-capture failure) and the symptom
("worked yesterday, broken today, no visible code change") is exactly
the kind of regression worth a named decision so future-us doesn't
collapse them back into a single field.
