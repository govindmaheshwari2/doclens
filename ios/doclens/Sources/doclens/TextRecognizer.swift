import CoreGraphics
import UIKit
import Vision

/// On-device OCR over a document image, returning the full recognised text
/// plus per-line bounding boxes and confidence.
///
/// Uses Apple Vision's `VNRecognizeTextRequest` (iOS 13+) — part of the OS, no
/// bundled model. Run with the `.accurate` recognition level and language
/// correction on for the best transcription (this is a one-shot call on a
/// captured still, not the live path, so accuracy is worth the cost).
///
/// Vision has no notion of a paragraph "block", so each recognised line is
/// emitted as its own block containing a single line — keeping the cross-
/// platform [OcrResult] shape uniform with Android's ML Kit (blocks → lines).
enum TextRecognizer {
    /// Recognise text in the image at [path]. The returned map matches the
    /// Dart `OcrResult.fromMap` contract:
    /// `{ text, imageSize:[w,h], blocks:[ { text, boundingBox:[l,t,w,h],
    ///    recognizedLanguage, lines:[ { text, boundingBox, confidence } ] } ] }`.
    static func recognize(path: String) throws -> [String: Any] {
        guard let img = UIImage(contentsOfFile: path),
              let cg = img.uprightCGImage() else {
            throw ImageWarperError.ioError("Cannot read image at \(path)")
        }

        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([request])

        var blocks: [[String: Any]] = []
        var fullLines: [String] = []

        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let string = candidate.string
            if string.isEmpty { continue }

            // Vision boxes are normalised with a bottom-left origin and y-up.
            // Convert to top-left-origin pixel coordinates so the boxes match
            // the image the caller is displaying.
            let bb = observation.boundingBox
            let box: [Double] = [
                Double(bb.minX * width),
                Double((1 - bb.maxY) * height),
                Double(bb.width * width),
                Double(bb.height * height),
            ]

            let line: [String: Any] = [
                "text": string,
                "boundingBox": box,
                "confidence": Double(candidate.confidence),
            ]
            blocks.append([
                "text": string,
                "boundingBox": box,
                "lines": [line],
            ])
            fullLines.append(string)
        }

        return [
            "text": fullLines.joined(separator: "\n"),
            "imageSize": [Double(width), Double(height)],
            "blocks": blocks,
        ]
    }
}
