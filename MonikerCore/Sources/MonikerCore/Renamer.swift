import Foundation

/// A proposed new name, before anything on disk changes.
public struct Suggestion: Sendable, Identifiable, Equatable {
    public var id: URL { url }
    public var url: URL
    public var newName: String
    public var tags: [String]

    public init(url: URL, newName: String, tags: [String] = []) {
        self.url = url
        self.newName = newName
        self.tags = tags
    }
}

/// A rename that happened, kept so it can be undone.
public struct RenameRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var original: URL
    public var renamed: URL
    public var date: Date

    public init(id: UUID = UUID(), original: URL, renamed: URL, date: Date = Date()) {
        self.id = id
        self.original = original
        self.renamed = renamed
        self.date = date
    }
}

/// Reads a file, asks the model for a name, and renames it.
public struct Renamer: Sendable {
    let reader: any ContentReader
    let model: any NamingModel

    public init(reader: any ContentReader, model: any NamingModel) {
        self.reader = reader
        self.model = model
    }

    /// Works out a new name. Nothing on disk changes.
    public func suggest(for url: URL, datePrefix: Bool) async throws -> Suggestion {
        let name = url.lastPathComponent
        guard let kind = FileKind(pathExtension: url.pathExtension) else { throw MonikerError.unsupported(name) }
        let content = try await reader.read(url, kind: kind)
        let idea = try await model.suggest(instructions: Prompts.instructions, prompt: Prompts.prompt(for: content))

        let title = FileNamer.sanitize(idea.title, pathExtension: url.pathExtension)
        guard !title.isEmpty, !GenericName.isGeneric(title) else { throw MonikerError.noName(name) }
        let date = datePrefix ? Self.creationDate(of: url) : nil
        let newName = FileNamer.filename(title: title, date: date, pathExtension: url.pathExtension)
        let tags = idea.tags.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Suggestion(url: url, newName: newName, tags: Array(tags.prefix(3)))
    }

    /// Renames the file, picking "name 2" if the name is taken. Optionally adds Finder tags.
    public static func apply(_ suggestion: Suggestion, addTags: Bool = false,
                             fileManager: FileManager = .default) throws -> RenameRecord {
        let source = suggestion.url
        guard fileManager.fileExists(atPath: source.path) else { throw MonikerError.missing(source.lastPathComponent) }
        let directory = source.deletingLastPathComponent()
        let target = FileNamer.availableURL(for: suggestion.newName, in: directory) {
            $0.path != source.path && fileManager.fileExists(atPath: $0.path)
        }
        if target.path != source.path {
            try fileManager.moveItem(at: source, to: target)
        }
        if addTags, !suggestion.tags.isEmpty {
            setTags(suggestion.tags, on: target)
        }
        return RenameRecord(original: source, renamed: target)
    }

    /// Puts the file back under its old name (or "old name 2" if something took it meanwhile).
    @discardableResult
    public static func undo(_ record: RenameRecord, fileManager: FileManager = .default) throws -> URL {
        guard fileManager.fileExists(atPath: record.renamed.path) else {
            throw MonikerError.missing(record.renamed.lastPathComponent)
        }
        let target = FileNamer.availableURL(for: record.original.lastPathComponent,
                                            in: record.original.deletingLastPathComponent()) {
            fileManager.fileExists(atPath: $0.path)
        }
        try fileManager.moveItem(at: record.renamed, to: target)
        return target
    }

    static func creationDate(of url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }

    static func setTags(_ tags: [String], on url: URL) {
        #if os(macOS)
        var url = url
        var values = URLResourceValues()
        let existing = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
        values.tagNames = Array(Set(existing + tags)).sorted()
        try? url.setResourceValues(values)
        #endif
    }
}

/// The last renames, saved as JSON so Undo survives a restart.
public struct Journal: Sendable {
    public let file: URL
    public let limit: Int

    public init(file: URL, limit: Int = 50) {
        self.file = file
        self.limit = limit
    }

    public func load() -> [RenameRecord] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RenameRecord].self, from: data)) ?? []
    }

    public func save(_ records: [RenameRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Array(records.prefix(limit))) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
