import CoreVideo

enum SharpnessEstimator {
    /// Variance-of-Laplacian over a BGRA buffer, optionally restricted to a
    /// normalized rect (portrait [0,1] space, origin top-left). Higher value
    /// = sharper. Returns 0 for unsupported formats / empty regions.
    static func sharpness(pixelBuffer: CVPixelBuffer, region: CGRect?) -> Double {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if format != kCVPixelFormatType_32BGRA { return 0 }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        guard w > 2, h > 2,
              let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // Clamp region to the inner area (Laplacian needs ±1 neighbors).
        let r = region ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let x0 = max(1, Int(r.minX * Double(w)))
        let y0 = max(1, Int(r.minY * Double(h)))
        let x1 = min(w - 2, Int(r.maxX * Double(w)))
        let y1 = min(h - 2, Int(r.maxY * Double(h)))
        if x1 <= x0 || y1 <= y0 { return 0 }

        // Subsample so cost stays bounded regardless of resolution.
        let stepX = max(1, (x1 - x0) / 96)
        let stepY = max(1, (y1 - y0) / 96)

        func luma(_ x: Int, _ y: Int) -> Double {
            let pix = ptr + y * stride + x * 4
            let b = Double(pix[0]); let g = Double(pix[1]); let red = Double(pix[2])
            return (red * 299 + g * 587 + b * 114) / 1000
        }

        var sum = 0.0
        var sumSq = 0.0
        var n = 0.0
        var y = y0
        while y <= y1 {
            var x = x0
            while x <= x1 {
                let lap = luma(x - 1, y) + luma(x + 1, y)
                        + luma(x, y - 1) + luma(x, y + 1)
                        - 4 * luma(x, y)
                sum += lap
                sumSq += lap * lap
                n += 1
                x += stepX
            }
            y += stepY
        }
        if n < 1 { return 0 }
        let mean = sum / n
        return max(0, sumSq / n - mean * mean)
    }
}
