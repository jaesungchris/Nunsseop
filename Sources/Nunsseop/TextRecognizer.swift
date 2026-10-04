import Foundation
import Vision

/// Reads the text in an image with Vision, line by line in reading order.
enum TextRecognizer {
    private static let preferredLanguages = ["ko-KR", "ja-JP", "zh-Hans", "en-US"]

    static func recognize(imageAt url: URL) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = Set((try? request.supportedRecognitionLanguages()) ?? [])
        request.recognitionLanguages = preferredLanguages.filter(supported.contains)
        // Without detection, the first language's model garbles the others (Japanese read as Korean).
        request.automaticallyDetectsLanguage = true
        guard (try? VNImageRequestHandler(url: url).perform([request])) != nil else { return "" }
        let pieces = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { (box: observation.boundingBox, text: $0.string) }
        }
        // Vision's boxes have their origin at the bottom left. Boxes whose centers sit
        // within half a line of each other are one line, read left to right.
        var lines: [[(box: CGRect, text: String)]] = []
        for piece in pieces.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let first = lines.last?.first,
               abs(first.box.midY - piece.box.midY) < min(first.box.height, piece.box.height) / 2 {
                lines[lines.count - 1].append(piece)
            } else {
                lines.append([piece])
            }
        }
        return lines.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}
