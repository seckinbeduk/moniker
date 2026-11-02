import AppKit
import Foundation
import MonikerCore
import PDFKit
import Vision

/// Reads files with what's built into macOS: Vision for images, PDFKit for PDFs.
struct SystemContentReader: ContentReader {
    func read(_ url: URL, kind: FileKind) async throws -> FileContent {
        let name = url.lastPathComponent
        switch kind {
        case .image:
            async let text = Self.recognizeText(in: url)
            async let labels = Self.classify(url)
            return FileContent(kind: .image, originalName: name, text: await text, labels: await labels)

        case .pdf:
            guard let document = PDFDocument(url: url) else { throw MonikerError.unsupported(name) }
            var text = String((document.string ?? "").prefix(4_000))
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let page = document.page(at: 0) {
                // A scanned PDF has no text layer: read its first page like a picture.
                let image = page.thumbnail(of: CGSize(width: 1_600, height: 2_200), for: .mediaBox)
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    text = await Self.recognizeText(in: cgImage)
                }
            }
            let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
            return FileContent(kind: .pdf, originalName: name, text: text, pageCount: document.pageCount, embeddedTitle: title)

        case .text:
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 12_000) ?? Data()
            return FileContent(kind: .text, originalName: name, text: String(decoding: data, as: UTF8.self))
        }
    }

    static func recognizeText(in url: URL) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        let observations = (try? await request.perform(on: url)) ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func recognizeText(in image: CGImage) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        let observations = (try? await request.perform(on: image)) ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// What the picture shows, most confident first: "document", "food", "screenshot"…
    static func classify(_ url: URL) async -> [String] {
        let observations = (try? await ClassifyImageRequest().perform(on: url)) ?? []
        return observations
            .filter { $0.confidence > 0.3 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(5)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }
}
