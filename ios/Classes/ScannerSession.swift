import AVFoundation
import CoreImage
import CoreMedia
import Flutter
import UIKit
import Vision

final class ScannerSession: NSObject {
    private let config: ScannerConfig
    private let textures: FlutterTextureRegistry
    private let eventSink: ([String: Any]) -> Void

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sampleQueue = DispatchQueue(label: "fnds.sample.queue")
    private let detectionQueue = DispatchQueue(label: "fnds.detect.queue")

    private var currentInput: AVCaptureDeviceInput?
    private var currentDevice: AVCaptureDevice?

    private var texture: CameraTexture?
    private var textureId: Int64 = -1

    private var lastDetectionTime = CFAbsoluteTimeGetCurrent()
    private var detectionIntervalSec: CFTimeInterval { 1.0 / Double(max(1, config.detectionThrottleHz)) }

    private var flashMode: AVCaptureDevice.FlashMode = .auto
    private var torchOn: Bool = false

    private var pendingCapture: ((Result<[String: Any], ScannerError>) -> Void)?
    private let stateLock = NSLock()
    private var _lastQuadNormalized: Quad?
    private var lastQuadNormalized: Quad? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _lastQuadNormalized }
        set { stateLock.lock(); _lastQuadNormalized = newValue; stateLock.unlock() }
    }
    private var stopped: Bool = false
    private var lastBufferWidth: Int = 0
    private var lastBufferHeight: Int = 0
    private var emittedPreviewSize: Bool = false

    init(config: ScannerConfig,
         textures: FlutterTextureRegistry,
         eventSink: @escaping ([String: Any]) -> Void) {
        self.config = config
        self.textures = textures
        self.eventSink = eventSink
        super.init()
        switch config.initialFlashMode {
        case "off": flashMode = .off
        case "on": flashMode = .on
        case "torch": flashMode = .off; torchOn = true
        default: flashMode = .auto
        }
    }

    // MARK: - Lifecycle

    func start(completion: @escaping (Result<Int64, ScannerError>) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            doStart(completion: completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.doStart(completion: completion) }
                    else { completion(.failure(.permissionDenied)) }
                }
            }
        default:
            completion(.failure(.permissionDenied))
        }
    }

    private func doStart(completion: @escaping (Result<Int64, ScannerError>) -> Void) {
        sampleQueue.async {
            do {
                try self.configureSession()
                self.captureSession.startRunning()
                DispatchQueue.main.async {
                    let texture = CameraTexture()
                    self.texture = texture
                    self.textureId = self.textures.register(texture)
                    texture.onFrame = { [weak self] in
                        guard let self = self else { return }
                        self.textures.textureFrameAvailable(self.textureId)
                    }
                    self.applyTorchIfNeeded()
                    completion(.success(self.textureId))
                }
            } catch let err as ScannerError {
                DispatchQueue.main.async { completion(.failure(err)) }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.initFailed(error.localizedDescription)))
                }
            }
        }
    }

    private func configureSession() throws {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = config.sessionPreset

        let position: AVCaptureDevice.Position =
            config.initialLens == "front" ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: position) else {
            captureSession.commitConfiguration()
            throw ScannerError.unavailable("No camera for position \(position.rawValue)")
        }
        let input = try AVCaptureDeviceInput(device: device)
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            currentInput = input
            currentDevice = device
        } else {
            captureSession.commitConfiguration()
            throw ScannerError.initFailed("Cannot add video input")
        }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            captureSession.commitConfiguration()
            throw ScannerError.initFailed("Cannot add video output")
        }
        if let conn = videoOutput.connection(with: .video) {
            if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
            if conn.isVideoMirroringSupported { conn.isVideoMirrored = position == .front }
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        if let conn = photoOutput.connection(with: .video),
           conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }

        captureSession.commitConfiguration()
        applyContinuousAutoFocus(on: device)
    }

    /// Enable continuous autofocus + auto-exposure as the default mode.
    /// Documents at arm's length live in the AF range; range-restricting
    /// to `.near` is a hint per Apple's `AVCaptureDevice` docs (the
    /// algorithm is free to ignore it on unsupported devices).
    private func applyContinuousAutoFocus(on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.responds(to: #selector(setter: AVCaptureDevice.isSmoothAutoFocusEnabled)),
               device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if #available(iOS 11.0, *),
               device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            device.unlockForConfiguration()
        } catch {
            // Best-effort — focus tweaks are not fatal.
        }
    }

    func stop() {
        stopped = true
        texture?.onFrame = nil
        sampleQueue.sync {
            if self.captureSession.isRunning { self.captureSession.stopRunning() }
        }
        // Now safe to unregister: no more sample buffers will arrive.
        if textureId >= 0 {
            textures.unregisterTexture(textureId)
            textureId = -1
        }
        texture = nil
    }

    func pause() {
        sampleQueue.async {
            if self.captureSession.isRunning { self.captureSession.stopRunning() }
        }
    }

    func resume() {
        sampleQueue.async {
            if !self.captureSession.isRunning { self.captureSession.startRunning() }
        }
    }

    // MARK: - Controls

    func setFlashMode(_ mode: String) {
        switch mode {
        case "off": flashMode = .off; torchOn = false
        case "on": flashMode = .on; torchOn = false
        case "auto": flashMode = .auto; torchOn = false
        case "torch": flashMode = .off; torchOn = true
        default: break
        }
        applyTorchIfNeeded()
    }

    private func applyTorchIfNeeded() {
        guard let device = currentDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = torchOn ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Best effort.
        }
    }

    /// Tap-to-focus. `normalized` is in portrait-widget [0,1] space
    /// (origin top-left). We re-project into the sensor's landscape
    /// `focusPointOfInterest` space per Apple's `AVCaptureDevice` docs:
    /// (0,0) = top-left of the sensor when the device is held in
    /// landscape-left.
    func focus(at normalized: CGPoint) {
        guard let device = currentDevice else { return }
        let x = max(0, min(1, normalized.x))
        let y = max(0, min(1, normalized.y))
        // Portrait → landscape sensor transform. Back camera: rotate
        // 90° CW (sensorX = y, sensorY = 1 - x). Front camera is also
        // mirrored on the connection, so its sensor x is not flipped.
        let isFront = device.position == .front
        let sensorPoint: CGPoint
        if isFront {
            sensorPoint = CGPoint(x: y, y: x)
        } else {
            sensorPoint = CGPoint(x: y, y: 1.0 - x)
        }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported,
               device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = sensorPoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported,
               device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = sensorPoint
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            return
        }
        // Auto-cancel: drop back to continuous AF after a short window
        // so the preview keeps tracking when the user moves the camera.
        // 3 s matches CameraX's recommended default for documents.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                // Best-effort.
            }
        }
    }

    func switchCamera() {
        sampleQueue.async {
            self.captureSession.beginConfiguration()
            if let input = self.currentInput { self.captureSession.removeInput(input) }
            let newPos: AVCaptureDevice.Position =
                self.currentDevice?.position == .back ? .front : .back
            if let dev = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                 for: .video,
                                                 position: newPos),
               let input = try? AVCaptureDeviceInput(device: dev) {
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                    self.currentDevice = dev
                    self.currentInput = input
                }
            }
            if let conn = self.videoOutput.connection(with: .video) {
                if conn.isVideoOrientationSupported {
                    conn.videoOrientation = .portrait
                }
                if conn.isVideoMirroringSupported {
                    conn.isVideoMirrored = self.currentDevice?.position == .front
                }
            }
            self.captureSession.commitConfiguration()
            if let dev = self.currentDevice {
                self.applyContinuousAutoFocus(on: dev)
            }
            self.applyTorchIfNeeded()
        }
    }

    // MARK: - Capture

    func capture(completion: @escaping (Result<[String: Any], ScannerError>) -> Void) {
        stateLock.lock()
        if pendingCapture != nil {
            stateLock.unlock()
            completion(.failure(.captureFailed("Capture already in progress")))
            return
        }
        pendingCapture = completion
        stateLock.unlock()
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(flashMode) {
            settings.flashMode = flashMode
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - Sample buffer delegate (live detection)

extension ScannerSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if stopped { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let bw = CVPixelBufferGetWidth(pixelBuffer)
        let bh = CVPixelBufferGetHeight(pixelBuffer)
        if bw != lastBufferWidth || bh != lastBufferHeight {
            lastBufferWidth = bw
            lastBufferHeight = bh
            emittedPreviewSize = false
        }

        texture?.update(pixelBuffer: pixelBuffer)

        if !emittedPreviewSize {
            emittedPreviewSize = true
            eventSink([
                "previewSize": [Double(bw), Double(bh)],
            ])
        }

        guard config.enableLiveDetection else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastDetectionTime < detectionIntervalSec { return }
        lastDetectionTime = now

        let lowLight = config.enableLowLightDetection
            ? LumaEstimator.isLowLight(pixelBuffer: pixelBuffer) : false

        // Orientation: see docs/decisions.md ("iOS Vision orientation").
        // Buffer is delivered already upright via the connection.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up, options: [:])
        detectionQueue.async { [weak self] in
            guard let self = self else { return }
            // Prefer Apple's document-specific ML detector when available —
            // it's what VisionKit uses internally (iOS 15+, Neural-Engine
            // accelerated). Fall back to a tuned rectangles request on
            // older OS versions.
            if #available(iOS 15.0, *) {
                let request = VNDetectDocumentSegmentationRequest { req, _ in
                    self.handleRectangles(
                        req.results as? [VNRectangleObservation] ?? [],
                        lowLight: lowLight)
                }
                try? handler.perform([request])
            } else {
                let request = VNDetectRectanglesRequest { req, _ in
                    self.handleRectangles(
                        req.results as? [VNRectangleObservation] ?? [],
                        lowLight: lowLight)
                }
                // Docs-tuned defaults for documents, see
                // developer.apple.com/documentation/vision/vndetectrectanglesrequest
                request.minimumAspectRatio = 0.4
                request.maximumAspectRatio = 1.0
                request.minimumSize = 0.15
                request.minimumConfidence = 0.4
                request.maximumObservations = 5
                request.quadratureTolerance = 45
                try? handler.perform([request])
            }
        }
    }

    private static func quadArea(_ obs: VNRectangleObservation) -> CGFloat {
        let p = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
        var sum: CGFloat = 0
        for i in 0..<4 {
            let a = p[i]
            let b = p[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    private func handleRectangles(_ results: [VNRectangleObservation], lowLight: Bool) {
        let payload: [String: Any]
        // Document-presence gate: reject observations that are unlikely to
        // be a real document. We require (a) reasonable Vision confidence
        // and (b) the quad covers a meaningful fraction of the frame. The
        // ML detector alone returns "best guess" rectangles even when the
        // frame is empty — without this filter, auto-capture fires on
        // ambient surfaces like desks and walls.
        let filtered = results.filter { obs in
            let area = ScannerSession.quadArea(obs)
            return obs.confidence >= 0.5 && area >= 0.10 && area <= 0.95
        }
        // Apple sorts by confidence; for documents the largest detected
        // quad is almost always the user's intended target.
        let best = filtered.max { lhs, rhs in
            ScannerSession.quadArea(lhs) < ScannerSession.quadArea(rhs)
        }
        if let obs = best {
            // Vision returns normalized [0,1] with origin bottom-left.
            // We flip Y to top-left so the contract matches Android.
            let q = Quad(
                topLeft: CGPoint(x: obs.topLeft.x, y: 1.0 - obs.topLeft.y),
                topRight: CGPoint(x: obs.topRight.x, y: 1.0 - obs.topRight.y),
                bottomRight: CGPoint(x: obs.bottomRight.x, y: 1.0 - obs.bottomRight.y),
                bottomLeft: CGPoint(x: obs.bottomLeft.x, y: 1.0 - obs.bottomLeft.y)
            )
            lastQuadNormalized = q
            payload = ["quad": q.toMap(), "lowLight": lowLight]
        } else {
            lastQuadNormalized = nil
            payload = ["quad": NSNull(), "lowLight": lowLight]
        }
        eventSink(payload)
    }
}

// MARK: - Photo capture delegate

extension ScannerSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        stateLock.lock()
        let completion = pendingCapture
        pendingCapture = nil
        stateLock.unlock()
        guard let completion = completion else { return }

        if let error = error {
            completion(.failure(.captureFailed(error.localizedDescription)))
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let uiImage = UIImage(data: data) else {
            completion(.failure(.captureFailed("No image data")))
            return
        }

        // `UIImage(data:).cgImage` returns the *raw sensor* pixels (landscape)
        // even when EXIF says the image is portrait. We re-render the
        // UIImage through a graphics context that bakes the orientation,
        // so the resulting CGImage has the same orientation as the live
        // preview — i.e. the same frame our normalized quad was measured in.
        guard let uprightCG = uiImage.uprightCGImage() else {
            completion(.failure(.captureFailed("Unable to bake orientation")))
            return
        }
        let rawSize = CGSize(width: uprightCG.width, height: uprightCG.height)

        // Save the upright JPEG to disk so consumers reading from
        // `rawImagePath` see what the user saw (and so the quad coords we
        // report are valid in that file's pixel space).
        let rawPath: String
        do {
            let uprightUIImage = UIImage(cgImage: uprightCG)
            let q = max(1, min(100, config.jpegQuality))
            guard let uprightData = uprightUIImage.jpegData(
                    compressionQuality: CGFloat(q) / 100.0) else {
                throw ImageWarperError.warpFailed("Re-encode failed")
            }
            rawPath = try TempFiles.write(jpegData: uprightData, quality: q)
        } catch {
            completion(.failure(.captureFailed("Failed writing raw: \(error)")))
            return
        }
        let cgImage = uprightCG

        // If quad in normalized space, convert to raw image pixels.
        let normQuad = lastQuadNormalized
        let imageQuad: Quad?
        if let n = normQuad {
            imageQuad = Quad(
                topLeft: CGPoint(x: n.topLeft.x * rawSize.width, y: n.topLeft.y * rawSize.height),
                topRight: CGPoint(x: n.topRight.x * rawSize.width, y: n.topRight.y * rawSize.height),
                bottomRight: CGPoint(x: n.bottomRight.x * rawSize.width, y: n.bottomRight.y * rawSize.height),
                bottomLeft: CGPoint(x: n.bottomLeft.x * rawSize.width, y: n.bottomLeft.y * rawSize.height)
            )
        } else {
            imageQuad = nil
        }

        var croppedPath: String? = nil
        var warpError: String? = nil
        if config.enablePerspectiveWarp, let q = imageQuad {
            do {
                croppedPath = try ImageWarper.warp(
                    cgImage: cgImage,
                    quad: q,
                    jpegQuality: config.jpegQuality)
            } catch {
                // Don't fail the whole capture — surface the warp error
                // so callers can decide to retake, but still give them the
                // raw photo and quad to work with (e.g. for EditCorners).
                warpError = "\(error)"
                croppedPath = nil
            }
        }

        var payload: [String: Any] = [
            "croppedImagePath": croppedPath ?? NSNull(),
            "rawImagePath": rawPath,
            "quad": (imageQuad ?? Quad(
                topLeft: .zero,
                topRight: CGPoint(x: rawSize.width, y: 0),
                bottomRight: CGPoint(x: rawSize.width, y: rawSize.height),
                bottomLeft: CGPoint(x: 0, y: rawSize.height)
            )).toMap(),
            "rawImageSize": [Double(rawSize.width), Double(rawSize.height)],
        ]
        if let warpError = warpError {
            payload["warpError"] = warpError
        }
        completion(.success(payload))
    }
}
