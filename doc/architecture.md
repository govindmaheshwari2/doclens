# Architecture

```
┌──────────────────────── Flutter (Dart) ────────────────────────┐
│                                                                │
│   NativeDocScanner (StatefulWidget)                            │
│     ├─ Texture(textureId)            ← live preview            │
│     ├─ overlayBuilder(quad, status)  ← Quad overlay            │
│     ├─ captureButtonBuilder(onTap)                             │
│     └─ flashButtonBuilder(mode, onCycle)                       │
│                                                                │
│   DoclensController                                   │
│     ├─ initialize() → textureId                                │
│     ├─ quadStream  (broadcast)                                 │
│     ├─ statusStream (StatusClassifier)                         │
│     ├─ autoCaptureStream (StabilityTracker)                    │
│     ├─ capture() → ScanResult                                  │
│     └─ warpImage(rawPath, quad) → croppedPath                  │
│                                                                │
│   ├─ MethodChannel  "doclens/methods"       │
│   └─ EventChannel   "doclens/events"        │
└────────────────────────────────────────────────────────────────┘
                                ↕
┌─────────── iOS (Swift) ─────────────┐  ┌──── Android (Kotlin) ──────┐
│                                     │  │                            │
│ AVCaptureSession                    │  │ CameraX                    │
│   ├─ AVCaptureVideoDataOutput       │  │   ├─ Preview               │
│   ├─ AVCapturePhotoOutput           │  │   ├─ ImageAnalysis         │
│   ↓                                 │  │   └─ ImageCapture          │
│ Sample buffer → CameraTexture       │  │                            │
│ (throttled) → VNDetectRectangles    │  │ ImageProxy → YuvUtils      │
│  → normalized Quad                  │  │  → QuadDetector (Sobel +   │
│                                     │  │     connected component +  │
│ capture: CIPerspectiveCorrection    │  │     convex hull → 4 pts)   │
│                                     │  │                            │
│                                     │  │ capture: ImageCapture +    │
│                                     │  │   Matrix.setPolyToPoly     │
└─────────────────────────────────────┘  └────────────────────────────┘
```

## Same `Quad` contract on both platforms

Quads streamed over the EventChannel are in **normalized [0,1]** coordinates
with **origin top-left**, points in **TL → TR → BR → BL** order. The platform
implementations are responsible for whatever rotations / flips are needed to
honor that contract (e.g. Vision returns origin bottom-left and is flipped
internally; CameraX rotation is applied via `rotateNormalizedQuad`).

## Why no OpenCV / ML Kit on Android

See [decisions.md](decisions.md).

## Threading

- iOS: detection runs on a dedicated `detectionQueue`; preview texture is
  updated on the sample queue. UI callbacks (`eventSink`, result handlers)
  are marshaled to the main queue.
- Android: detection runs on a single-thread analysis executor with
  `STRATEGY_KEEP_ONLY_LATEST`; capture uses a separate single-thread
  executor; method results are posted to the main thread.

## Lifecycle

`DoclensView` registers a `WidgetsBindingObserver`. On `paused`/
`inactive`/`hidden` it calls `controller.pause()`, which stops the native
session. On `resumed` it calls `resume()`. `dispose()` unbinds use cases,
unregisters the texture, and shuts down executors.
