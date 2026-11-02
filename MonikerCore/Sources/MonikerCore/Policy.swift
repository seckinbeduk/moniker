import Foundation

/// The kinds of file Moniker can read.
public enum FileKind: String, Sendable, Equatable {
    case image, pdf, text

    public init?(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp":
            self = .image
        case "pdf":
            self = .pdf
        case "txt", "md", "markdown", "csv", "json", "log", "xml", "yaml", "yml", "html", "htm":
            self = .text
        default:
            return nil
        }
    }
}

/// Names that say nothing about the file: what cameras, screenshots and downloads produce.
public enum GenericName {
    /// Lowercased prefixes that are generic whatever follows them.
    static let generatedPrefixes = [
        "screenshot", "screen shot", "ekran resmi", "ekran görüntüsü", "bildschirmfoto", "capture d’écran",
        "capture d'écran", "captura de pantalla", "schermata", "スクリーンショット", "截屏",
        "whatsapp image", "signal-", "telegram", "cleanshot", "snagit",
    ]

    /// Lowercased words that are generic when followed only by numbers, dates or a copy count.
    static let genericWords = [
        "img", "dsc", "dscn", "dcim", "pxl", "mvimg", "photo", "image", "picture", "pic", "scan", "scanned",
        "document", "doc", "file", "download", "downloaded", "untitled", "adsız", "adsiz", "unbenannt",
        "sans titre", "attachment", "unnamed", "export", "output", "new", "temp", "tmp", "page", "receipt",
    ]

    /// "img_4821", "document (3)", "untitled 2", "scan 2026-11-02"
    nonisolated(unsafe) static let wordWithNumbers = try? Regex(
        "(" + genericWords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            + ")([ _.\\-]?[0-9]+)*( ?\\([0-9]+\\))?"
    )
    /// "20261102_143012", "2026-11-02 14.30.12"
    nonisolated(unsafe) static let numbersOnly = try? Regex("[0-9 _.\\-]{6,}")
    /// "3f2a9c1e-77b0-…", "a94f0c3d5e6b7a8c9d0e"
    nonisolated(unsafe) static let uuidStart = try? Regex("[0-9a-f]{8}-[0-9a-f]{4}-")
    nonisolated(unsafe) static let longHex = try? Regex("[0-9a-f]{16,}")

    static let screenshotPrefixes = Array(generatedPrefixes.prefix(11)) + ["cleanshot", "snagit"]

    /// "Screenshot …", "Ekran Resmi …", "CleanShot …"
    public static func isScreenshotName(_ filename: String) -> Bool {
        let lower = filename.lowercased()
        return screenshotPrefixes.contains { lower.hasPrefix($0) }
    }

    /// True for "Screenshot 2026-11-02 at 16.52.04.png", "IMG_4821.HEIC", "document (3).pdf"…
    public static func isGeneric(_ filename: String) -> Bool {
        let base = (filename as NSString).deletingPathExtension.lowercased()
            .trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return true }
        if generatedPrefixes.contains(where: { base.hasPrefix($0) }) { return true }
        if let regex = wordWithNumbers, base.wholeMatch(of: regex) != nil { return true }
        if let regex = numbersOnly, base.wholeMatch(of: regex) != nil { return true }
        if let regex = uuidStart, base.prefixMatch(of: regex) != nil { return true }
        if let regex = longHex, base.wholeMatch(of: regex) != nil { return true }
        return false
    }
}

/// Decides which files Moniker looks at.
public enum RenamePolicy {
    /// Extensions of downloads that haven't finished yet.
    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "tmp", "opdownload"]

    /// A file Moniker should rename on its own: visible, finished, readable, and badly named.
    public static func shouldConsider(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard !name.hasPrefix("."), !partialExtensions.contains(url.pathExtension.lowercased()) else { return false }
        guard FileKind(pathExtension: url.pathExtension) != nil else { return false }
        return GenericName.isGeneric(name)
    }
}
