import CoreGraphics
import ImageIO
import Vision

/// Detects the dominant text direction of a (already dewarped) document crop
/// so the caller can rotate it upright.
///
/// Uses Apple Vision's `VNRecognizeTextRequest` (iOS 13+) — part of the OS,
/// no bundled model. The image is hypothesised at each of the four 90°
/// orientations; whichever the recogniser reads the most confident text from
/// is taken to be upright. Cheap because it runs once per capture on a
/// downscaled copy with the `.fast` recognition level.
enum TextOrientation {
    /// Number of clockwise 90° turns to apply to [cgImage] so its dominant
    /// text reads upright (`0...3`). Returns `0` when no confident text
    /// orientation can be found (blank/graphical page, or recognition failed),
    /// so callers leave the crop untouched.
    static func bestClockwiseTurns(for cgImage: CGImage) -> Int {
        guard let small = downscale(cgImage, maxDimension: 1000) else { return 0 }

        // Each hypothesis pairs a Vision orientation hint with the clockwise
        // turn count that bakes that same transform into the pixels:
        //   .up    → 0   (already upright)
        //   .right → 1   (raw pixels are 90° CCW from upright → rotate 90° CW)
        //   .down  → 2   (180°)
        //   .left  → 3   (raw pixels are 90° CW from upright → rotate 270° CW)
        let hypotheses: [(turns: Int, orientation: CGImagePropertyOrientation)] = [
            (0, .up), (1, .right), (2, .down), (3, .left),
        ]

        let scores = hypotheses.map { textScore(small, orientation: $0.orientation) }
        let asIsScore = scores[0]

        var best = (turns: 0, score: asIsScore)
        for i in 1..<scores.count where scores[i] > best.score {
            best = (hypotheses[i].turns, scores[i])
        }

        // Bias toward the current orientation. Upside-down (and sideways) Latin
        // text still "reads" as low-confidence garbage, so a flipped crop can
        // narrowly outscore the upright one. Only rotate when a hypothesis
        // beats the as-is (.up) score by a clear margin, and clears an absolute
        // floor — otherwise leave the crop untouched (the common false-180°
        // flip that left the image upside-down while OCR, which detects
        // orientation independently, read fine).
        guard best.turns != 0 else { return 0 }
        return (best.score >= 1.0 && best.score >= asIsScore * Self.minRotateMargin)
            ? best.turns : 0
    }

    /// A non-zero rotation must beat the as-is score by this factor to win.
    private static let minRotateMargin = 1.30

    /// Confidence-weighted count of recognised characters when [cgImage] is
    /// interpreted with [orientation]. Higher = more upright-looking text.
    private static func textScore(_ cgImage: CGImage,
                                  orientation: CGImagePropertyOrientation) -> Double {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage,
                                            orientation: orientation,
                                            options: [:])
        do {
            try handler.perform([request])
        } catch {
            return 0
        }
        guard let results = request.results else { return 0 }
        var score = 0.0
        for observation in results {
            guard let candidate = observation.topCandidates(1).first else { continue }
            score += Double(candidate.confidence) * Double(candidate.string.count)
        }
        return score
    }

    /// Downscale so the orientation pass is fast; coarse text shapes are all
    /// that's needed. Returns the original when already small enough.
    private static func downscale(_ cg: CGImage, maxDimension: Int) -> CGImage? {
        let w = cg.width
        let h = cg.height
        let maxDim = max(w, h)
        if maxDim <= maxDimension { return cg }
        let scale = Double(maxDimension) / Double(maxDim)
        let nw = max(1, Int(Double(w) * scale))
        let nh = max(1, Int(Double(h) * scale))
        guard let ctx = CGContext(
            data: nil, width: nw, height: nh,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }
}
