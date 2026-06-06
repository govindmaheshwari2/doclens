# Architecture

```
┌──────────────────────── Flutter (Dart) ────────────────────────┐
│                                                                │
│   DoclensScreen (drop-in route, owns its own controller)       │
│      ↓                                                         │
│   DoclensView (StatefulWidget)                                 │
│     ├─ Texture(textureId)            ← live preview            │
│     ├─ overlayBuilder(quad, status)  ← Quad overlay            │
│     ├─ captureButtonBuilder(onTap)                             │
│     ├─ flashButtonBuilder(mode, onCycle)                       │
│     └─ tap-to-focus gesture detector → controller.focusAt()    │
│                                                                │
│   DoclensController extends ChangeNotifier                     │
│     ├─ initialize() → textureId                                │
│     ├─ quadStream  (broadcast)                                 │
│     ├─ statusStream  (StatusClassifier)                        │
│     ├─ autoCaptureStream  (StabilityTracker + confirmation)    │
│     ├─ previewSizeStream                                       │
│     ├─ capture() → ScanResult                                  │
│     ├─ focusAt(Offset)                                         │
│     └─ warpImage(rawPath, quad) → croppedPath                  │
│                                                                │
│   ├─ MethodChannel  "doclens/methods"                          │
│   └─ EventChannel   "doclens/events"                           │
└────────────────────────────────────────────────────────────────┘
                                ↕
┌─────────── iOS (Swift) ─────────────┐  ┌──── Android (Kotlin) ──────┐
│                                     │  │                            │
│ AVCaptureSession                    │  │ CameraX                    │
│   ├─ AVCaptureVideoDataOutput       │  │   ├─ Preview               │
│   ├─ AVCapturePhotoOutput           │  │   ├─ ImageAnalysis         │
│   ↓                                 │  │   └─ ImageCapture          │
│ Sample buffer → CameraTexture       │  │                            │
│ (throttled) → VNDetect-             │  │ ImageProxy → YuvUtils      │
│   DocumentSegmentation (iOS 15+)    │  │  → QuadDetector (Sobel +   │
│   OR VNDetectRectangles (13/14)     │  │     connected component +  │
│  → normalized Quad                  │  │     convex hull → 4 pts)   │
│                                     │  │                            │
│ continuous AF + tap-to-focus:       │  │ continuous AF + tap-to-    │
│   AVCaptureDevice.focusMode         │  │ focus: CameraControl       │
│   .continuousAutoFocus +            │  │ .startFocusAndMetering     │
│   focusPointOfInterest              │  │ with SurfaceOrientedMeter- │
│                                     │  │ ingPointFactory            │
│                                     │  │                            │
│ capture: AVCapturePhotoOutput +     │  │ capture: ImageCapture +    │
│   CIPerspectiveCorrection           │  │   Matrix.setPolyToPoly     │
│                                     │  │                            │
│ native UI: VNDocumentCamera-        │  │ native UI: GmsDocument-    │
│   ViewController                    │  │   Scanner (Play services)  │
└─────────────────────────────────────┘  └────────────────────────────┘
```

## Same `Quad` contract on both platforms

Quads streamed over the EventChannel are in **normalized [0, 1]**
coordinates with **origin top-left**, points in
**TL → TR → BR → BL** order. The platform implementations are responsible
for whatever rotations / flips are needed to honour that contract
(e.g. Vision returns origin bottom-left in landscape sensor space, then
we flip Y to top-left; CameraX rotation is applied via
`rotateNormalizedQuad`).

## Why no OpenCV / ML Kit on the live-preview Android path

See [decisions.md](decisions.md).

## Threading

- **iOS**: detection runs on a dedicated `detectionQueue`; preview
  texture is updated on the sample queue. UI callbacks (`eventSink`,
  result handlers) are marshalled to the main queue.
- **Android**: detection runs on a single-thread analysis executor with
  `STRATEGY_KEEP_ONLY_LATEST`; capture uses a separate single-thread
  executor; method results are posted to the main thread.

## Lifecycle

`DoclensView` registers a `WidgetsBindingObserver`. On `paused`/
`inactive`/`hidden` it calls `controller.pause()`, which stops the
native session. On `resumed` it calls `resume()`. `dispose()` unbinds
use cases, unregisters the texture, and shuts down executors.

## Drop-in screen flow

`DoclensScreen` wraps `DoclensView` + a built-in review screen and owns
its own `DoclensController`. The flow:

1. Route push → `initialize()` → live preview.
2. Auto-capture (or manual shutter) → `controller.capture()`.
3. Pause session → push review screen with `Retake / Edit corners / Use`
   actions.
4. On `Use` → pop both routes, resolve the awaited `Future<ScanResult?>`
   with the result.
5. On `Retake` → pop review only, `controller.resume()` continues the
   live preview.
6. On cancel (close button, back gesture) → pop the route, resolve with
   `null`.
