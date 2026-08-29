import CoreVideo

enum LumaEstimator {
    /// Average luminance of the buffer's center region, used as a coarse
    /// "is it dark?" signal. Returns true when the avg is below ~50 on 0..255.
    static func isLowLight(pixelBuffer: CVPixelBuffer) -> Bool {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        // We only configured BGRA, so handle that path.
        if format != kCVPixelFormatType_32BGRA { return false }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return false }
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        let sampleW = w / 4
        let sampleH = h / 4
        let startX = (w - sampleW) / 2
        let startY = (h - sampleH) / 2

        var sum: UInt64 = 0
        var count: UInt64 = 0
        // Step to reduce work.
        let step = max(1, sampleW / 32)
        var y = startY
        while y < startY + sampleH {
            var x = startX
            let row = ptr + y * stride
            while x < startX + sampleW {
                let pix = row + x * 4
                let b = UInt32(pix[0])
                let g = UInt32(pix[1])
                let r = UInt32(pix[2])
                let luma = (r * 299 + g * 587 + b * 114) / 1000
                sum &+= UInt64(luma)
                count &+= 1
                x += step
            }
            y += step
        }
        if count == 0 { return false }
        let avg = sum / count
        return avg < 50
    }
}
