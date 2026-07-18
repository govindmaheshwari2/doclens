import CoreGraphics
import Vision

/// Runs the same document-quad detection used by the live preview on a single
/// still image (e.g. one imported from the gallery), returning a normalized
/// `[0,1]` top-left-origin quad — or `nil` when nothing document-like is found.
///
/// Mirrors the detection and document-presence gating in
/// `ScannerSession.handleRectangles`, but drives `VNImageRequestHandler` from a
/// `CGImage` on disk instead of a live `CVPixelBuffer`.
enum DocumentDetector {
    /// Detect on [cgImage] (assumed already EXIF-upright). The completion is
    /// invoked with a normalized quad, or `nil` if detection fails or no
    /// confident document quad is found.
    static func detect(cgImage: CGImage, completion: @escaping (Quad?) -> Void) {
        let handler = VNImageRequestHandler(cgImage: cgImage,
                                            orientation: .up, options: [:])
        func finish(_ req: VNRequest) {
            completion(bestQuad(from: req.results as? [VNRectangleObservation] ?? []))
        }
        // Prefer Apple's document-specific ML detector (iOS 15+); fall back to
        // a docs-tuned rectangles request on older OSes — same as the live path.
        if #available(iOS 15.0, *) {
            let request = VNDetectDocumentSegmentationRequest { req, _ in finish(req) }
            do { try handler.perform([request]) } catch { completion(nil) }
        } else {
            let request = VNDetectRectanglesRequest { req, _ in finish(req) }
            request.minimumAspectRatio = 0.4
            request.maximumAspectRatio = 1.0
            request.minimumSize = 0.15
            request.minimumConfidence = 0.4
            request.maximumObservations = 5
            request.quadratureTolerance = 45
            do { try handler.perform([request]) } catch { completion(nil) }
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

    /// Apply the same document-presence gate as the live preview, then pick
    /// the largest qualifying quad and flip Y to a top-left origin.
    private static func bestQuad(from results: [VNRectangleObservation]) -> Quad? {
        let filtered = results.filter { obs in
            let area = quadArea(obs)
            return obs.confidence >= 0.5 && area >= 0.10 && area <= 0.95
        }
        guard let obs = filtered.max(by: { quadArea($0) < quadArea($1) }) else {
            return nil
        }
        // Vision returns normalized [0,1] with origin bottom-left; flip Y to
        // top-left so the contract matches Android and the live stream.
        return Quad(
            topLeft: CGPoint(x: obs.topLeft.x, y: 1.0 - obs.topLeft.y),
            topRight: CGPoint(x: obs.topRight.x, y: 1.0 - obs.topRight.y),
            bottomRight: CGPoint(x: obs.bottomRight.x, y: 1.0 - obs.bottomRight.y),
            bottomLeft: CGPoint(x: obs.bottomLeft.x, y: 1.0 - obs.bottomLeft.y)
        )
    }
}
