import Foundation

/// Tells you about files that appear in a set of folders after watching starts.
/// Files already there are never reported, so Moniker never touches your existing files.
@MainActor
final class FolderWatcher {
    var onNewFile: ((URL) -> Void)?
    /// Folders that couldn't be watched, with the reason.
    private(set) var problems: [String] = []

    private var sources: [DispatchSourceFileSystemObject] = []
    private var known: [URL: Set<String>] = [:]
    private var pending: [URL: Task<Void, Never>] = [:]

    func watch(_ folders: [URL]) {
        stop()
        for folder in folders {
            let name = FileManager.default.displayName(atPath: folder.path)
            do {
                known[folder] = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
            } catch {
                problems.append("Can't read \(name). Allow Moniker in System Settings → Privacy & Security → Files & Folders.")
                continue
            }
            let descriptor = open(folder.path, O_EVTONLY)
            guard descriptor >= 0 else {
                problems.append("Can't watch \(name) (error \(errno)).")
                continue
            }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.changed(folder) }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        problems = []
        sources.forEach { $0.cancel() }
        sources = []
        pending.values.forEach { $0.cancel() }
        pending = [:]
        known = [:]
    }

    /// Folder events come in bursts (a screenshot is written, then renamed into place); wait for quiet.
    private func changed(_ folder: URL) {
        pending[folder]?.cancel()
        pending[folder] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.compare(folder)
        }
    }

    private func compare(_ folder: URL) {
        let now = Self.names(in: folder)
        let added = now.subtracting(known[folder] ?? [])
        known[folder] = now
        for name in added.sorted() {
            onNewFile?(folder.appendingPathComponent(name))
        }
    }

    static func names(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }
}
