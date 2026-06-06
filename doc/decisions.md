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

## JPEG quality default: 100

Chose **100** because the most common downstream consumer of a scan is
an OCR / extraction pipeline, and those benefit from the cleanest bytes
we can give them. The size cost (a 3 MB JPEG vs ~1 MB at quality 92) is
acceptable for documents that the user typically uploads once and
forgets.

Apps that scan to gallery / camera-roll style storage can drop the
default to `~92` — visually indistinguishable from 100 in dropoff tests
and ~3× smaller. The package's own `EditCornersScreen.warpImage` honours
the same setting.

## Auto-capture defaults

- `cornerThreshold = 0.02` — fraction of the normalised `[0, 1]`
  preview coordinate space, i.e. "no corner moved more than 2 % of the
  frame between consecutive emitted frames." Tighter values demand a
  tripod-steady hand; looser values fire on noticeably shaky hands but
  risk motion-blurred captures.
- `stabilityDuration = 800 ms` — handheld scanning is never perfectly
  still. 800 ms at 2 % jitter is a realistic, snappy target.
- `confirmationDelay = 350 ms` — the "hold still, about to shoot"
  cue. Long enough that the user can abort by moving the camera, short
  enough that the perceived shutter rhythm matches VisionKit's native
  scanner.

Total time from "looks like a document" to shutter is roughly
`stabilityDuration + confirmationDelay` ≈ 1.15 s.

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

## Tap-to-focus coordinate transforms

**iOS** — `AVCaptureDevice.focusPointOfInterest` is in the sensor's
**landscape** orientation, origin top-left when the device is held
landscape-left. Independent of the connection's `videoOrientation`. So
a Flutter tap at portrait-normalised `(x, y)` maps to:

- Back camera: `(sensorX, sensorY) = (y, 1 - x)`
- Front camera: `(sensorX, sensorY) = (y, x)` (already mirrored on the
  connection, do not double-mirror here)

After the one-shot focus completes we drop back to
`.continuousAutoFocus` after 3 s — matches Apple's HIG and CameraX's
default auto-cancel duration.

**Android** — CameraX exposes `SurfaceOrientedMeteringPointFactory` for
preview surfaces whose dimensions we control. We use the
`SurfaceRequest.resolution` returned for the Preview use case as the
factory's surface size; the user's tap, in `(textureWidth,
textureHeight)` space, is fed directly to `factory.createPoint(x, y)`.
This is the documented factory for `Texture`-based previews — using
`DisplayOrientedMeteringPointFactory` would be wrong because we don't
have a `PreviewView`.

References:
- [`AVCaptureDevice.focusPointOfInterest`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/1385853-focuspointofinterest)
- [`SurfaceOrientedMeteringPointFactory`](https://developer.android.com/reference/androidx/camera/core/SurfaceOrientedMeteringPointFactory)
- [`CameraControl.startFocusAndMetering`](https://developer.android.com/reference/androidx/camera/core/CameraControl#startFocusAndMetering(androidx.camera.core.FocusMeteringAction))
