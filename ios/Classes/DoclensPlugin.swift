import Flutter
import UIKit

public class DoclensPlugin: NSObject, FlutterPlugin {
    private var session: ScannerSession?
    private let registrar: FlutterPluginRegistrar
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private let eventStream = QuadEventStream()
    private let nativeUIScanner = NativeUIScanner()

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        self.methodChannel = FlutterMethodChannel(
            name: "doclens/methods",
            binaryMessenger: registrar.messenger())
        self.eventChannel = FlutterEventChannel(
            name: "doclens/events",
            binaryMessenger: registrar.messenger())
        super.init()
        registrar.addMethodCallDelegate(self, channel: methodChannel)
        eventChannel.setStreamHandler(eventStream)
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = DoclensPlugin(registrar: registrar)
        registrar.publish(plugin)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            initialize(args: call.arguments as? [String: Any] ?? [:], result: result)
        case "dispose":
            session?.stop()
            session = nil
            eventStream.reset()
            result(nil)
        case "capture":
            guard let session = session else {
                result(FlutterError(code: "init_failed", message: "Not initialized", details: nil))
                return
            }
            session.capture { res in
                switch res {
                case .success(let payload): result(payload)
                case .failure(let err):
                    result(FlutterError(code: "capture_failed",
                                        message: err.localizedDescription,
                                        details: nil))
                }
            }
        case "warpImage":
            handleWarp(call: call, result: result)
        case "rotateImage":
            handleRotate(call: call, result: result)
        case "recognizeText":
            handleRecognizeText(call: call, result: result)
        case "setFlashMode":
            if let mode = (call.arguments as? [String: Any])?["mode"] as? String {
                session?.setFlashMode(mode)
            }
            result(nil)
        case "switchCamera":
            session?.switchCamera()
            result(nil)
        case "pause":
            session?.pause()
            result(nil)
        case "resume":
            session?.resume()
            result(nil)
        case "focusAt":
            let args = call.arguments as? [String: Any] ?? [:]
            let x = (args["x"] as? Double) ?? 0.5
            let y = (args["y"] as? Double) ?? 0.5
            session?.focus(at: CGPoint(x: x, y: y))
            result(nil)
        case "scanWithNativeUI":
            let args = call.arguments as? [String: Any] ?? [:]
            let quality = (args["jpegQuality"] as? Int) ?? 100
            nativeUIScanner.present(jpegQuality: quality, result: result)
        case "detectInImage":
            handleDetectInImage(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initialize(args: [String: Any], result: @escaping FlutterResult) {
        // Tear down any previous session so we never leak a running camera.
        session?.stop()
        session = nil
        let config = ScannerConfig.from(map: args)
        let textures = registrar.textures()
        let new = ScannerSession(config: config, textures: textures,
                                 eventSink: { [weak self] payload in
            self?.eventStream.send(payload)
        })
        new.start { startResult in
            switch startResult {
            case .success(let textureId):
                self.session = new
                result(NSNumber(value: textureId))
            case .failure(let err):
                let code: String
                if case .permissionDenied = err { code = "permission_denied" }
                else if case .unavailable = err { code = "unavailable" }
                else { code = "init_failed" }
                result(FlutterError(code: code,
                                    message: err.localizedDescription,
                                    details: nil))
            }
        }
    }

    private func handleWarp(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["rawImagePath"] as? String,
              let quadMap = args["quad"] as? [String: Any] else {
            result(FlutterError(code: "capture_failed",
                                message: "Invalid warp args", details: nil))
            return
        }
        let jpegQuality = (args["jpegQuality"] as? Int) ?? 100
        let enhancement = (args["enhancement"] as? String) ?? "none"
        let autoOrientation = (args["autoOrientation"] as? String) ?? "none"
        let quad = Quad.fromMap(quadMap)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let out = try ImageWarper.warpFile(
                    inputPath: path, quad: quad, jpegQuality: jpegQuality,
                    enhancement: enhancement, autoOrientation: autoOrientation)
                DispatchQueue.main.async { result(out) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "capture_failed",
                                        message: error.localizedDescription,
                                        details: nil))
                }
            }
        }
    }

    private func handleRecognizeText(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["imagePath"] as? String else {
            result(FlutterError(code: "capture_failed",
                                message: "Invalid recognizeText args", details: nil))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let out = try TextRecognizer.recognize(path: path)
                DispatchQueue.main.async { result(out) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "capture_failed",
                                        message: error.localizedDescription,
                                        details: nil))
                }
            }
        }
    }

    private func handleDetectInImage(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["imagePath"] as? String else {
            result(FlutterError(code: "capture_failed",
                                message: "Invalid detectInImage args", details: nil))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            // Bake EXIF orientation into the pixels so the detected quad and
            // reported size live in the same upright space the warp uses.
            guard let img = UIImage(contentsOfFile: path),
                  let cg = img.uprightCGImage() else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "capture_failed",
                                        message: "Cannot read image at \(path)",
                                        details: nil))
                }
                return
            }
            let size = CGSize(width: cg.width, height: cg.height)
            DocumentDetector.detect(cgImage: cg) { quad in
                let payload: [String: Any] = [
                    "quad": quad?.toMap() ?? NSNull(),
                    "imageSize": [Double(size.width), Double(size.height)],
                ]
                DispatchQueue.main.async { result(payload) }
            }
        }
    }

    private func handleRotate(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["imagePath"] as? String else {
            result(FlutterError(code: "capture_failed",
                                message: "Invalid rotate args", details: nil))
            return
        }
        let quarterTurns = (args["quarterTurns"] as? Int) ?? 0
        let jpegQuality = (args["jpegQuality"] as? Int) ?? 100
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let out = try ImageWarper.rotateFile(
                    inputPath: path, quarterTurns: quarterTurns, jpegQuality: jpegQuality)
                DispatchQueue.main.async { result(out) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "capture_failed",
                                        message: error.localizedDescription,
                                        details: nil))
                }
            }
        }
    }
}

final class QuadEventStream: NSObject, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }

    func send(_ payload: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.sink?(payload)
        }
    }

    func reset() {
        DispatchQueue.main.async { [weak self] in
            self?.sink = nil
        }
    }
}
