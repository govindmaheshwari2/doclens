import CoreImage
import UIKit
import ImageIO

enum ImageWarperError: Error, LocalizedError {
    case ioError(String)
    case warpFailed(String)

    var errorDescription: String? {
        switch self {
        case .ioError(let m): return m
        case .warpFailed(let m): return m
        }
    }
}

enum ImageWarper {
    private static let ciContext = CIContext()

    /// Apply a perspective correction to [cgImage] using corner points in
    /// the image's own pixel coordinates (origin top-left, y-down).
    /// CoreImage uses bottom-left origin, so we flip Y before calling.
    static func warp(cgImage: CGImage, quad: Quad, jpegQuality: Int,
                     enhancement: String = "none") throws -> String {
        let ci = CIImage(cgImage: cgImage)
        let w = ci.extent.width
        let h = ci.extent.height

        // Clamp quad into the image bounds — Vision/normalization can
        // push corners slightly outside [0,w]×[0,h] which makes
        // CIPerspectiveCorrection emit an infinite extent.
        func clamp(_ p: CGPoint) -> CGPoint {
            return CGPoint(
                x: min(max(p.x, 0), w),
                y: min(max(p.y, 0), h)
            )
        }
        let tl = clamp(quad.topLeft)
        let tr = clamp(quad.topRight)
        let br = clamp(quad.bottomRight)
        let bl = clamp(quad.bottomLeft)

        // Reject degenerate (collinear / coincident) quads — they would
        // produce an empty output and a misleading "render failed" error.
        if !isQuadValid(tl: tl, tr: tr, br: br, bl: bl, imageSize: CGSize(width: w, height: h)) {
            throw ImageWarperError.warpFailed("Degenerate quad — corners are too close or collinear")
        }

        func flip(_ p: CGPoint) -> CGPoint {
            return CGPoint(x: p.x, y: h - p.y)
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            throw ImageWarperError.warpFailed("CIPerspectiveCorrection unavailable")
        }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: flip(tl)), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: flip(tr)), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: flip(br)), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: flip(bl)), forKey: "inputBottomLeft")

        guard let out = filter.outputImage else {
            throw ImageWarperError.warpFailed("No output image")
        }
        // `extent` can be infinite when the warp can't form a finite output
        // (degenerate corners that survived clamping). Guard explicitly —
        // CGImage rendering against `.infinite` silently fails.
        let extent = out.extent
        if extent.isInfinite || extent.isEmpty ||
           extent.width < 1 || extent.height < 1 {
            throw ImageWarperError.warpFailed(
                "CIPerspectiveCorrection produced an invalid extent (\(extent))")
        }
        // Optional post-warp enhancement. CIColorControls preserves the
        // extent, so we keep rendering from the geometry extent computed
        // above.
        let enhanced = applyEnhancement(out, mode: enhancement)
        guard let cg = ciContext.createCGImage(enhanced, from: extent) else {
            throw ImageWarperError.warpFailed("CGImage render failed (extent=\(extent))")
        }
        let img = UIImage(cgImage: cg)
        let q = max(1, min(100, jpegQuality))
        guard let data = img.jpegData(compressionQuality: CGFloat(q) / 100.0) else {
            throw ImageWarperError.warpFailed("JPEG encode failed")
        }
        return try TempFiles.write(jpegData: data, quality: q)
    }

    /// Apply an optional colour enhancement to the perspective-corrected
    /// image. Values mirror the Android ColorMatrix settings so both
    /// platforms produce a comparable look. `none` returns the image as-is.
    private static func applyEnhancement(_ image: CIImage, mode: String) -> CIImage {
        switch mode {
        case "grayscale":
            return colorControls(image, saturation: 0, brightness: 0, contrast: 1.0)
        case "enhanced":
            return colorControls(image, saturation: 1.1, brightness: 0.02, contrast: 1.2)
        case "blackAndWhite":
            return colorControls(image, saturation: 0, brightness: 0, contrast: 2.2)
        default:
            return image
        }
    }

    private static func colorControls(_ image: CIImage,
                                      saturation: CGFloat,
                                      brightness: CGFloat,
                                      contrast: CGFloat) -> CIImage {
        guard let f = CIFilter(name: "CIColorControls") else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(saturation, forKey: kCIInputSaturationKey)
        f.setValue(brightness, forKey: kCIInputBrightnessKey)
        f.setValue(contrast, forKey: kCIInputContrastKey)
        return f.outputImage ?? image
    }

    /// Sanity-check the quad before handing it to CoreImage.
    /// - Each edge must be at least 1% of the corresponding image dimension.
    /// - The signed area must be > 0.5% of the image area (i.e. it's a real
    ///   quadrilateral with the corners in the expected winding order).
    private static func isQuadValid(tl: CGPoint, tr: CGPoint,
                                    br: CGPoint, bl: CGPoint,
                                    imageSize: CGSize) -> Bool {
        let minEdge = max(min(imageSize.width, imageSize.height) * 0.01, 4)
        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = a.x - b.x, dy = a.y - b.y
            return (dx * dx + dy * dy).squareRoot()
        }
        let top = dist(tl, tr)
        let right = dist(tr, br)
        let bottom = dist(br, bl)
        let left = dist(bl, tl)
        if top < minEdge || right < minEdge ||
           bottom < minEdge || left < minEdge {
            return false
        }
        let points = [tl, tr, br, bl]
        var area: CGFloat = 0
        for i in 0..<4 {
            let a = points[i]
            let b = points[(i + 1) % 4]
            area += a.x * b.y - b.x * a.y
        }
        area = abs(area) / 2
        let imageArea = imageSize.width * imageSize.height
        return area >= imageArea * 0.005
    }

    /// Read an image from disk, warp it, write a new file. Used by warpImage().
    static func warpFile(inputPath: String, quad: Quad, jpegQuality: Int,
                         enhancement: String = "none") throws -> String {
        guard let img = UIImage(contentsOfFile: inputPath),
              let cg = img.uprightCGImage() else {
            throw ImageWarperError.ioError("Cannot read image at \(inputPath)")
        }
        return try warp(cgImage: cg, quad: quad, jpegQuality: jpegQuality,
                        enhancement: enhancement)
    }
}

extension UIImage {
    /// Returns a `CGImage` whose pixel layout matches the *visible*
    /// orientation of this `UIImage` — i.e. the EXIF orientation is baked
    /// into the pixels. Use this whenever you want to do pixel math (warp,
    /// crop, draw an overlay) without worrying about the orientation tag.
    func uprightCGImage() -> CGImage? {
        // Fast path: already upright.
        if imageOrientation == .up, let cg = cgImage {
            return cg
        }
        // Re-render through a graphics context that applies orientation.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }
}

enum TempFiles {
    static func write(jpegData: Data, quality _: Int) throws -> String {
        let dir = NSTemporaryDirectory()
        let name = "fnds_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(6)).jpg"
        let path = (dir as NSString).appendingPathComponent(name)
        try jpegData.write(to: URL(fileURLWithPath: path))
        return path
    }
}
