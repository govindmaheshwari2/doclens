import Flutter
import CoreVideo

/// Flutter texture backed by the latest camera pixel buffer.
/// Thread-safe: `update` is called from the capture queue, `copyPixelBuffer`
/// from the Flutter engine thread.
final class CameraTexture: NSObject, FlutterTexture {
    private var current: CVPixelBuffer?
    private let lock = NSLock()
    var onFrame: (() -> Void)?

    func update(pixelBuffer: CVPixelBuffer) {
        lock.lock()
        current = pixelBuffer
        lock.unlock()
        onFrame?()
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer = current else { return nil }
        return Unmanaged.passRetained(buffer)
    }
}
