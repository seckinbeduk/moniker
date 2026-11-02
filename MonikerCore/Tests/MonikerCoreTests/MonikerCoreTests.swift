import Foundation
import Testing
@testable import MonikerCore

@Suite("Which files")
struct PolicyTests {
    @Test(arguments: [
        "Screenshot 2026-11-02 at 16.52.04.png",
        "Ekran Resmi 2026-11-02 16.52.04.png",
        "IMG_4821.HEIC",
        "IMG 4821.jpeg",
        "DSC00042.JPG",
        "PXL_20261102_143012345.jpg",
        "document (3).pdf",
        "Untitled 2.txt",
        "scan.pdf",
        "download.pdf",
        "20261102_143012.jpg",
        "3f2a9c1e-77b0-4c2d-9a1b-5e6f7a8b9c0d.png",
        "WhatsApp Image 2026-11-02 at 14.30.12.jpeg",
        "photo_2026-11-02_14-30-12.jpg",
    ])
    func genericNames(name: String) {
        #expect(GenericName.isGeneric(name))
    }

    @Test(arguments: [
        "Elektrik Faturası Ekim.pdf",
        "README.md",
        "invoice-acme-2026.pdf",
        "Seçkin Bedük CV.pdf",
        "Image Pipeline Notes.md",
        "Scanner Settings.png",
        "2026-11-02 Flight Booking.pdf",
    ])
    func meaningfulNames(name: String) {
        #expect(!GenericName.isGeneric(name))
    }

    @Test func onlyFinishedReadableGenericFiles() {
        #expect(RenamePolicy.shouldConsider(URL(fileURLWithPath: "/tmp/Screenshot 2026-11-02 at 16.52.04.png")))
        #expect(!RenamePolicy.shouldConsider(URL(fileURLWithPath: "/tmp/.Screenshot 2026-11-02 at 16.52.04.png")))
        #expect(!RenamePolicy.shouldConsider(URL(fileURLWithPath: "/tmp/document.pdf.crdownload")))
        #expect(!RenamePolicy.shouldConsider(URL(fileURLWithPath: "/tmp/IMG_0001.mov")))
        #expect(!RenamePolicy.shouldConsider(URL(fileURLWithPath: "/tmp/Elektrik Faturası.pdf")))
    }

    @Test func kinds() {
        #expect(FileKind(pathExtension: "HEIC") == .image)
        #expect(FileKind(pathExtension: "pdf") == .pdf)
        #expect(FileKind(pathExtension: "md") == .text)
        #expect(FileKind(pathExtension: "zip") == nil)
    }
}

@Suite("File names")
struct FileNamerTests {
    @Test func sanitizeRemovesWhatMacOSDoesNotLike() {
        #expect(FileNamer.sanitize("Invoice: October/November") == "Invoice October November")
        #expect(FileNamer.sanitize("  \"Flight Booking\"  ") == "Flight Booking")
        #expect(FileNamer.sanitize("Report.pdf", pathExtension: "pdf") == "Report")
        #expect(FileNamer.sanitize(".hidden") == "hidden")
        #expect(FileNamer.sanitize("Türkçe Başlık Ğüşiöç") == "Türkçe Başlık Ğüşiöç")
    }

    @Test func sanitizeClipsAtAWord() {
        let long = "A Very Long Title That Keeps Going Well Beyond Any Reasonable File Name Length"
        let clipped = FileNamer.sanitize(long, maxLength: 30)
        #expect(clipped.count <= 30)
        #expect(clipped == "A Very Long Title That Keeps")
    }

    @Test func filenameWithDate() {
        let date = Date(timeIntervalSince1970: 1_793_627_000)   // 2026-11-02 in UTC
        let utc = TimeZone(identifier: "UTC")!
        #expect(FileNamer.filename(title: "Electricity Bill", date: date, pathExtension: "pdf", timeZone: utc)
                == "2026-11-02 Electricity Bill.pdf")
        #expect(FileNamer.filename(title: "Notes", date: nil, pathExtension: "md") == "Notes.md")
    }

    @Test func takenNamesGetANumber() {
        let directory = URL(fileURLWithPath: "/tmp/x")
        let taken: Set<String> = ["/tmp/x/Plan.pdf", "/tmp/x/Plan 2.pdf"]
        let url = FileNamer.availableURL(for: "Plan.pdf", in: directory) { taken.contains($0.path) }
        #expect(url.lastPathComponent == "Plan 3.pdf")
    }
}

@Suite("Prompt")
struct PromptTests {
    @Test func imagePromptCarriesLabelsAndText() {
        let content = FileContent(kind: .image, originalName: "Screenshot.png", text: "Elektrik Faturası\nFatura Tutarı 412,50 TL",
                                  labels: ["screenshot", "document"])
        let prompt = Prompts.prompt(for: content)
        #expect(prompt.contains("(screenshot)"))
        #expect(prompt.contains("It looks like: screenshot, document"))
        #expect(prompt.contains("Fatura Tutarı"))
    }

    @Test func longTextIsCut() {
        let content = FileContent(kind: .text, originalName: "log.txt", text: String(repeating: "x", count: 10_000))
        #expect(Prompts.prompt(for: content).count < Prompts.textLimit + 200)
    }

    @Test func genericEmbeddedTitleIsIgnored() {
        let useful = FileContent(kind: .pdf, originalName: "a.pdf", pageCount: 2, embeddedTitle: "Q3 Board Report")
        let useless = FileContent(kind: .pdf, originalName: "a.pdf", pageCount: 1, embeddedTitle: "Untitled")
        #expect(Prompts.prompt(for: useful).contains("Q3 Board Report"))
        #expect(Prompts.prompt(for: useful).contains("2 pages"))
        #expect(!Prompts.prompt(for: useless).contains("Untitled"))
        #expect(Prompts.prompt(for: useless).contains("No readable text."))
    }
}

// MARK: - End to end, on a real temporary folder

struct FakeReader: ContentReader {
    func read(_ url: URL, kind: FileKind) async throws -> FileContent {
        FileContent(kind: kind, originalName: url.lastPathComponent, text: "elektrik faturası")
    }
}

struct FakeModel: NamingModel {
    var idea: NameIdea
    func suggest(instructions: String, prompt: String) async throws -> NameIdea { idea }
}

@Suite("Renaming")
struct RenamerTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("moniker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func makeFile(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data("hello".utf8).write(to: url)
        return url
    }

    @Test func suggestApplyUndo() async throws {
        let file = try makeFile("Screenshot 2026-11-02 at 16.52.04.png")
        let renamer = Renamer(reader: FakeReader(), model: FakeModel(idea: NameIdea(title: "Elektrik Faturası Ekim", tags: ["Bills"])))

        let suggestion = try await renamer.suggest(for: file, datePrefix: false)
        #expect(suggestion.newName == "Elektrik Faturası Ekim.png")
        #expect(suggestion.tags == ["bills"])
        #expect(FileManager.default.fileExists(atPath: file.path))   // suggesting changes nothing

        let record = try Renamer.apply(suggestion)
        #expect(record.renamed.lastPathComponent == "Elektrik Faturası Ekim.png")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: record.renamed.path))

        let restored = try Renamer.undo(record)
        #expect(restored.lastPathComponent == file.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func datePrefixUsesTheFileDate() async throws {
        let file = try makeFile("IMG_0001.jpg")
        let renamer = Renamer(reader: FakeReader(), model: FakeModel(idea: NameIdea(title: "Receipt Coffee Shop")))
        let suggestion = try await renamer.suggest(for: file, datePrefix: true)
        #expect(suggestion.newName == FileNamer.datePrefix(Date()) + " Receipt Coffee Shop.jpg")
    }

    @Test func neverOverwrites() async throws {
        _ = try makeFile("Plan.pdf")
        let file = try makeFile("document.pdf")
        let record = try Renamer.apply(Suggestion(url: file, newName: "Plan.pdf"))
        #expect(record.renamed.lastPathComponent == "Plan 2.pdf")
    }

    @Test func uselessIdeaIsRejected() async throws {
        let file = try makeFile("scan.pdf")
        let renamer = Renamer(reader: FakeReader(), model: FakeModel(idea: NameIdea(title: "Untitled")))
        await #expect(throws: MonikerError.self) { try await renamer.suggest(for: file, datePrefix: false) }
    }

    @Test func journalRoundTrip() {
        let journal = Journal(file: folder.appendingPathComponent("journal.json"), limit: 2)
        let records = (0..<3).map { RenameRecord(original: folder.appendingPathComponent("a\($0)"), renamed: folder.appendingPathComponent("b\($0)")) }
        journal.save(records)
        let loaded = journal.load()
        #expect(loaded.count == 2)
        #expect(loaded.first?.renamed.lastPathComponent == "b0")
    }
}

@Suite("Hearth replies")
struct JSONReplyTests {
    struct Idea: Decodable, Equatable { var title: String? }

    @Test func plainJSON() {
        #expect(JSONReply.decode(Idea.self, from: #"{"title": "Flight Booking"}"#) == Idea(title: "Flight Booking"))
    }

    @Test func wrappedInFencesAndThinking() {
        let reply = "<think>\nThe user wants a title.\n</think>\nSure:\n```json\n{\"title\": \"Tax Return 2025\"}\n```"
        #expect(JSONReply.decode(Idea.self, from: reply) == Idea(title: "Tax Return 2025"))
    }

    @Test func noJSON() {
        #expect(JSONReply.decode(Idea.self, from: "I can't help with that.") == nil)
    }

    @Test func engines() {
        #expect(Engine(rawValue: "hearth") == .hearth)
        #expect(Engine(rawValue: "auto") == .auto)
        #expect(Engine(rawValue: "cloud") == nil)
    }
}
