import Flutter
import UIKit
import VisionKit

/// Presents `VNDocumentCameraViewController` (VisionKit) and returns the
/// resulting page JPEGs as file paths.
///
/// References:
/// - https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller
/// - https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontrollerdelegate
/// - WWDC 2019 Session 224 "VisionKit and VNDocumentCameraViewController"
final class NativeUIScanner: NSObject {
    private var pending: FlutterResult?
    private var jpegQuality: Int = 100
    private weak var presenter: UIViewController?

    func present(jpegQuality: Int, result: @escaping FlutterResult) {
        // Guard against double-invocation while a scan is already in flight.
        if pending != nil {
            result(FlutterError(code: "capture_failed",
                                message: "Native scanner already presented",
                                details: nil))
            return
        }
        guard VNDocumentCameraViewController.isSupported else {
            result(FlutterError(code: "unavailable",
                                message: "VisionKit document scanner not supported on this device",
                                details: nil))
            return
        }
        guard let host = NativeUIScanner.topMostViewController() else {
            result(FlutterError(code: "unavailable",
                                message: "No host view controller to present from",
                                details: nil))
            return
        }
        self.pending = result
        self.jpegQuality = max(1, min(100, jpegQuality))
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        self.presenter = host
        host.present(scanner, animated: true)
    }

    // MARK: - Host VC lookup (iOS 13+ scene-aware, avoids deprecated keyWindow)

    private static func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
            ?? scenes.flatMap { $0.windows }.first
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - Result helpers

    private func reply(with paths: [String]?) {
        let cb = pending
        pending = nil
        // Reply to Flutter *first* so the user sees the result the instant
        // the modal animates out — then dismiss.
        cb?(paths)
        presenter?.dismiss(animated: true)
        presenter = nil
    }

    private func replyError(code: String, message: String) {
        let cb = pending
        pending = nil
        cb?(FlutterError(code: code, message: message, details: nil))
        presenter?.dismiss(animated: true)
        presenter = nil
    }

    /// Encode a `UIImage` to a JPEG file in `NSTemporaryDirectory()`.
    /// We use temp (not Documents) so the OS reclaims storage.
    private func saveJPEG(_ image: UIImage, index: Int) throws -> String {
        let q = CGFloat(jpegQuality) / 100.0
        guard let data = image.jpegData(compressionQuality: q) else {
            throw NSError(domain: "NativeUIScanner", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "JPEG encode failed"])
        }
        let dir = NSTemporaryDirectory()
        let name = "fnds_native_\(Int(Date().timeIntervalSince1970 * 1000))_\(index)_\(UUID().uuidString.prefix(6)).jpg"
        let path = (dir as NSString).appendingPathComponent(name)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        return path
    }
}

extension NativeUIScanner: VNDocumentCameraViewControllerDelegate {
    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                      didFinishWith scan: VNDocumentCameraScan) {
        // VisionKit hands us pages on the main thread; JPEG-encoding can be
        // chunky for high-res scans, so hop off then back on for the reply.
        let count = scan.pageCount
        var images = [UIImage]()
        images.reserveCapacity(count)
        for i in 0..<count {
            images.append(scan.imageOfPage(at: i))
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var paths: [String] = []
            do {
                for (i, img) in images.enumerated() {
                    paths.append(try self.saveJPEG(img, index: i))
                }
            } catch {
                DispatchQueue.main.async {
                    self.replyError(code: "capture_failed",
                                    message: "Failed writing scanned page: \(error.localizedDescription)")
                }
                return
            }
            DispatchQueue.main.async {
                self.reply(with: paths)
            }
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        reply(with: nil)
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                      didFailWithError error: Error) {
        replyError(code: "capture_failed", message: error.localizedDescription)
    }
}
