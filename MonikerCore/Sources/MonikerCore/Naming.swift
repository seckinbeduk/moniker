import Foundation

/// What Moniker could read from a file.
public struct FileContent: Sendable, Equatable {
    public var kind: FileKind
    public var originalName: String
    /// Recognized or extracted text.
    public var text: String
    /// What an image shows, e.g. "document", "receipt", "screenshot", "food".
    public var labels: [String]
    public var pageCount: Int?
    /// A title stored inside the file, like a PDF's metadata title.
    public var embeddedTitle: String?

    public init(kind: FileKind, originalName: String, text: String = "", labels: [String] = [],
                pageCount: Int? = nil, embeddedTitle: String? = nil) {
        self.kind = kind
        self.originalName = originalName
        self.text = text
        self.labels = labels
        self.pageCount = pageCount
        self.embeddedTitle = embeddedTitle
    }
}

/// The model's idea for a name.
public struct NameIdea: Sendable, Equatable {
    public var title: String
    public var tags: [String]

    public init(title: String, tags: [String] = []) {
        self.title = title
        self.tags = tags
    }
}

/// Reads a file's content. The app uses Vision and PDFKit; tests use a fake.
public protocol ContentReader: Sendable {
    func read(_ url: URL, kind: FileKind) async throws -> FileContent
}

/// Turns content into a name. The app uses Apple Intelligence; tests use a fake.
public protocol NamingModel: Sendable {
    func suggest(instructions: String, prompt: String) async throws -> NameIdea
}

public enum MonikerError: Error, LocalizedError, Equatable {
    case unsupported(String)
    case noName(String)
    case missing(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let name): "Moniker can't read \(name)."
        case .noName(let name): "Couldn't come up with a name for \(name)."
        case .missing(let name): "\(name) is gone."
        }
    }
}

// MARK: - Prompts

public enum Prompts {
    public static let instructions = """
    You name files so people can find them later. Given what a file contains, write a short, specific title: \
    2 to 6 words, Title Case, no date, no file extension, no quotes.
    Say what it is and whose or about what: "Turkcell Invoice October", "Swift Build Error Log", \
    "Flight Booking Istanbul Berlin", "Wireframe Settings Screen".
    Write the title in the main language of the text in the file.
    tags: up to three lowercase single-word topics.
    """

    /// Text past this point rarely changes the name, and every character costs time on-device.
    public static let textLimit = 2_500

    public static func prompt(for content: FileContent) -> String {
        var lines: [String] = []
        switch content.kind {
        case .image:
            let screenshot = content.labels.contains("screenshot") || GenericName.isScreenshotName(content.originalName)
            lines.append("File: an image" + (screenshot ? " (screenshot)" : ""))
        case .pdf:
            lines.append("File: a PDF" + (content.pageCount.map { " with \($0) page\($0 == 1 ? "" : "s")" } ?? ""))
        case .text:
            lines.append("File: a text file (.\((content.originalName as NSString).pathExtension))")
        }
        if let title = content.embeddedTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
           !GenericName.isGeneric(title) {
            lines.append("Title stored in the file: \(title)")
        }
        if !content.labels.isEmpty {
            lines.append("It looks like: " + content.labels.joined(separator: ", "))
        }
        let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            lines.append("No readable text.")
        } else {
            lines.append("Text in the file:\n" + String(text.prefix(textLimit)))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - File names

public enum FileNamer {
    static let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)

    /// A title that's safe as a file name on macOS, at most `maxLength` characters.
    public static func sanitize(_ title: String, pathExtension: String = "", maxLength: Int = 60) -> String {
        var text = String(String.UnicodeScalarView(title.unicodeScalars.map { forbidden.contains($0) ? " " : $0 }))
        text = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        // The model sometimes adds the extension itself: "Invoice October.pdf".
        if !pathExtension.isEmpty, text.lowercased().hasSuffix("." + pathExtension.lowercased()) {
            text = String(text.dropLast(pathExtension.count + 1))
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .-_'‘’“”`"))
        guard text.count > maxLength else { return text }

        var words: [Substring] = []
        var length = 0
        for word in text.split(separator: " ") {
            if length + word.count + (words.isEmpty ? 0 : 1) > maxLength { break }
            length += word.count + (words.isEmpty ? 0 : 1)
            words.append(word)
        }
        return words.isEmpty ? String(text.prefix(maxLength)) : words.joined(separator: " ")
    }

    /// `2026-11-02` in the user's time zone.
    public static func datePrefix(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `2026-11-02 Turkcell Invoice October.pdf`
    public static func filename(title: String, date: Date?, pathExtension: String, timeZone: TimeZone = .current) -> String {
        let base = date.map { datePrefix($0, timeZone: timeZone) + " " + title } ?? title
        return pathExtension.isEmpty ? base : base + "." + pathExtension
    }

    /// `name.pdf`, or `name 2.pdf` if that's taken, and so on.
    public static func availableURL(for filename: String, in directory: URL, exists: (URL) -> Bool) -> URL {
        let candidate = directory.appendingPathComponent(filename)
        guard exists(candidate) else { return candidate }
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        for number in 2... {
            let name = "\(base) \(number)" + (ext.isEmpty ? "" : ".\(ext)")
            let url = directory.appendingPathComponent(name)
            if !exists(url) { return url }
        }
        return candidate
    }
}
