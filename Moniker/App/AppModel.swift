import AppKit
import Foundation
import HearthKit
import MonikerCore
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    // MARK: State shown in the panel

    var recent: [RenameRecord] = []
    var pending: [Suggestion] = []
    var isWorking = false
    var lastError: String?
    var availabilityProblem: String?
    /// The last thing Moniker noticed or did, so it's clear why a file was or wasn't renamed.
    var activity: String?
    var folderProblems: [String] = []

    // MARK: Settings

    var isWatching: Bool {
        didSet { defaults.set(isWatching, forKey: Keys.watching); restartWatcher() }
    }
    var renameAutomatically: Bool {
        didSet { defaults.set(renameAutomatically, forKey: Keys.automatic) }
    }
    var addDate: Bool {
        didSet { defaults.set(addDate, forKey: Keys.date) }
    }
    var addTags: Bool {
        didSet { defaults.set(addTags, forKey: Keys.tags) }
    }
    var folders: [URL] {
        didSet { defaults.set(folders.map(\.path), forKey: Keys.folders); restartWatcher() }
    }
    var engine: Engine {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine); refreshAvailability() }
    }
    /// What Moniker asks Hearth for: Apple's model ("apple-intelligence", default) or its local one ("hearth").
    var hearthModel: String {
        didSet { defaults.set(hearthModel, forKey: Keys.hearthModel); refreshAvailability() }
    }
    /// "Apple Intelligence" or "Hearth (model)", whichever names files right now.
    var engineDescription: String?
    var openAtLogin: Bool {
        didSet {
            if openAtLogin { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: Internals

    private enum Keys {
        static let watching = "watching", automatic = "renameAutomatically", date = "addDate"
        static let tags = "addTags", folders = "folders", engine = "engine", hearthModel = "hearthModel"
    }
    private struct Job {
        var url: URL
        var manual: Bool
    }

    private let defaults = UserDefaults.standard
    private let watcher = FolderWatcher()
    private let journal = Journal(file: AppModel.supportDirectory.appendingPathComponent("journal.json"))
    private var queue: [Job] = []
    /// Files Moniker itself just renamed or put back with Undo. They show up in the folder as
    /// "new" files; they must not be renamed again or reported.
    private var ignoreOnce: Set<String> = []

    init() {
        defaults.register(defaults: [Keys.watching: true, Keys.automatic: true, Keys.date: true, Keys.tags: false])
        isWatching = defaults.bool(forKey: Keys.watching)
        renameAutomatically = defaults.bool(forKey: Keys.automatic)
        addDate = defaults.bool(forKey: Keys.date)
        addTags = defaults.bool(forKey: Keys.tags)
        if let paths = defaults.stringArray(forKey: Keys.folders) {
            folders = paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        } else {
            folders = Self.defaultFolders()
        }
        engine = Engine(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .auto
        hearthModel = defaults.string(forKey: Keys.hearthModel) ?? "apple-intelligence"
        openAtLogin = SMAppService.mainApp.status == .enabled
        recent = journal.load()
    }

    /// Apple Intelligence can be turned on, or finish downloading, while Moniker runs.
    func refreshAvailability() {
        Task { _ = await namingModel() }
    }

    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    /// The model for the chosen engine, or nil with the reason in `availabilityProblem`.
    /// Automatic: Hearth when it's running, so usage shows up there; Apple Intelligence directly otherwise.
    private func namingModel() async -> (any NamingModel)? {
        if engine != .apple, let status = await HearthModel.status() {
            let backend: HearthModel.Backend = hearthModel == "hearth" ? .local : .appleIntelligence
            availabilityProblem = nil
            engineDescription = backend == .local
                ? "Hearth's local model" + (status.localModel.map { " (\($0))" } ?? " (none loaded, so Apple Intelligence)")
                : "Apple Intelligence through Hearth"
            return FoundationNamer(model: HearthModel(backend, appName: "Moniker"))
        }
        if engine == .hearth {
            availabilityProblem = HearthError.notRunning.errorDescription
            engineDescription = nil
            return nil
        }
        if let problem = AppleIntelligence.unavailableReason() {
            availabilityProblem = problem + " Or run Hearth with a local model; Moniker uses it automatically."
            engineDescription = nil
            return nil
        }
        availabilityProblem = nil
        engineDescription = "Apple Intelligence"
        return FoundationNamer.appleIntelligence()
    }

    func launch() {
        refreshAvailability()
        watcher.onNewFile = { [weak self] url in self?.noticed(url) }
        restartWatcher()
    }

    var statusLine: String {
        if isWorking { return "Reading a file…" }
        guard isWatching else { return "Paused" }
        let names = folders.map { FileManager.default.displayName(atPath: $0.path) }
        return names.isEmpty ? "No folders to watch" : "Watching " + ListFormatter.localizedString(byJoining: names)
    }

    // MARK: Renaming

    private func restartWatcher() {
        if isWatching { watcher.watch(folders) } else { watcher.stop() }
        folderProblems = watcher.problems
    }

    private func noticed(_ url: URL) {
        if ignoreOnce.remove(url.path) != nil { return }
        let name = url.lastPathComponent
        guard !name.hasPrefix(".") else { return }   // temporary files, e.g. a screenshot being written
        guard RenamePolicy.shouldConsider(url) else {
            if FileKind(pathExtension: url.pathExtension) == nil {
                activity = "Saw “\(name)”: not a kind of file Moniker reads."
            } else if !GenericName.isGeneric(name) {
                activity = "Saw “\(name)”: it already has a good name."
            }
            return
        }
        activity = "Saw “\(name)”."
        enqueue(Job(url: url, manual: false))
    }

    /// Files the user picked by hand: renamed whatever their current name.
    func rename(_ urls: [URL]) {
        for url in urls where FileKind(pathExtension: url.pathExtension) != nil {
            enqueue(Job(url: url, manual: true))
        }
    }

    private func enqueue(_ job: Job) {
        queue.append(job)
        guard !isWorking else { return }
        isWorking = true
        Task { await drain() }
    }

    private func drain() async {
        while !queue.isEmpty {
            await process(queue.removeFirst())
        }
        isWorking = false
    }

    private func process(_ job: Job) async {
        guard let model = await namingModel() else { return }
        if !job.manual, !(await Self.waitUntilSettled(job.url)) { return }
        let renamer = Renamer(reader: SystemContentReader(), model: model)

        activity = "Reading “\(job.url.lastPathComponent)”…"
        do {
            let suggestion = try await renamer.suggest(for: job.url, datePrefix: addDate)
            activity = "Named “\(suggestion.newName)”."
            if renameAutomatically || job.manual {
                try apply(suggestion)
            } else {
                pending.removeAll { $0.url == suggestion.url }
                pending.insert(suggestion, at: 0)
            }
            lastError = nil
        } catch {
            lastError = Self.describe(error, file: job.url)
            activity = nil
        }
    }

    private func apply(_ suggestion: Suggestion) throws {
        let record = try Renamer.apply(suggestion, addTags: addTags)
        ignoreOnce.insert(record.renamed.path)
        pending.removeAll { $0.url == suggestion.url }
        recent.insert(record, at: 0)
        recent = Array(recent.prefix(journal.limit))
        journal.save(recent)
    }

    func accept(_ suggestion: Suggestion) {
        do { try apply(suggestion) } catch { lastError = Self.describe(error, file: suggestion.url) }
    }

    func dismiss(_ suggestion: Suggestion) {
        pending.removeAll { $0.url == suggestion.url }
    }

    func undo(_ record: RenameRecord) {
        do {
            let restored = try Renamer.undo(record)
            ignoreOnce.insert(restored.path)
            recent.removeAll { $0.id == record.id }
            journal.save(recent)
        } catch {
            lastError = Self.describe(error, file: record.renamed)
        }
    }

    /// Empties the list. Files keep their names; only the way back is forgotten.
    func clearRecent() {
        recent = []
        journal.save(recent)
    }

    // MARK: Finder and panels

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func chooseFilesToRename() {
        let panel = NSOpenPanel()
        panel.title = "Rename with Moniker"
        panel.prompt = "Rename"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate()
        if panel.runModal() == .OK { rename(panel.urls) }
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "Watch a Folder"
        panel.prompt = "Watch"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url, !folders.contains(url) { folders.append(url) }
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0 == url }
    }

    // MARK: Helpers

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Moniker", isDirectory: true)
    }

    /// Where screenshots go (Desktop unless changed in the Screenshot app), plus Downloads.
    static func defaultFolders() -> [URL] {
        let fileManager = FileManager.default
        var screenshots = fileManager.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        if let path = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !path.isEmpty {
            screenshots = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        return screenshots.standardizedFileURL == downloads.standardizedFileURL ? [downloads] : [screenshots, downloads]
    }

    /// Screenshots and downloads are written in steps; wait until the size stops changing.
    static func waitUntilSettled(_ url: URL) async -> Bool {
        var last = -1
        for _ in 0..<20 {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
            if size > 0, size == last { return true }
            last = size
            try? await Task.sleep(for: .milliseconds(400))
        }
        return true
    }

    static func describe(_ error: Error, file: URL) -> String {
        if "\(error)".contains("guardrail") {
            return "Apple Intelligence wouldn't name \(file.lastPathComponent)."
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
