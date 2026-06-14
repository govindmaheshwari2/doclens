import Foundation
import AVFoundation

struct ScannerConfig {
    let enableLiveDetection: Bool
    let detectionThrottleHz: Int
    let enablePerspectiveWarp: Bool
    let jpegQuality: Int
    let imageEnhancement: String
    let outputFormat: String
    let captureResolution: String
    let initialFlashMode: String
    let initialLens: String
    let enableTapToFocus: Bool
    let enablePinchToZoom: Bool
    let enableLowLightDetection: Bool

    static func from(map: [String: Any]) -> ScannerConfig {
        return ScannerConfig(
            enableLiveDetection: map["enableLiveDetection"] as? Bool ?? true,
            detectionThrottleHz: map["detectionThrottleHz"] as? Int ?? 12,
            enablePerspectiveWarp: map["enablePerspectiveWarp"] as? Bool ?? true,
            jpegQuality: map["jpegQuality"] as? Int ?? 100,
            imageEnhancement: map["imageEnhancement"] as? String ?? "none",
            outputFormat: map["outputFormat"] as? String ?? "jpeg",
            captureResolution: map["captureResolution"] as? String ?? "high",
            initialFlashMode: map["initialFlashMode"] as? String ?? "auto",
            initialLens: map["initialLens"] as? String ?? "back",
            enableTapToFocus: map["enableTapToFocus"] as? Bool ?? true,
            enablePinchToZoom: map["enablePinchToZoom"] as? Bool ?? true,
            enableLowLightDetection: map["enableLowLightDetection"] as? Bool ?? true
        )
    }

    var sessionPreset: AVCaptureSession.Preset {
        switch captureResolution {
        case "max": return .photo
        case "high": return .high
        default: return .high
        }
    }
}

struct Quad {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    func toMap() -> [String: Any] {
        return [
            "topLeft": [Double(topLeft.x), Double(topLeft.y)],
            "topRight": [Double(topRight.x), Double(topRight.y)],
            "bottomRight": [Double(bottomRight.x), Double(bottomRight.y)],
            "bottomLeft": [Double(bottomLeft.x), Double(bottomLeft.y)],
        ]
    }

    static func fromMap(_ map: [String: Any]) -> Quad {
        func pt(_ key: String) -> CGPoint {
            if let arr = map[key] as? [Double], arr.count == 2 {
                return CGPoint(x: arr[0], y: arr[1])
            }
            if let arr = map[key] as? [NSNumber], arr.count == 2 {
                return CGPoint(x: arr[0].doubleValue, y: arr[1].doubleValue)
            }
            return .zero
        }
        return Quad(topLeft: pt("topLeft"),
                    topRight: pt("topRight"),
                    bottomRight: pt("bottomRight"),
                    bottomLeft: pt("bottomLeft"))
    }
}

enum ScannerError: Error, LocalizedError {
    case permissionDenied
    case unavailable(String)
    case initFailed(String)
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera permission denied"
        case .unavailable(let m): return m
        case .initFailed(let m): return m
        case .captureFailed(let m): return m
        }
    }
}
