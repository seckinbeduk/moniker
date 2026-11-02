import AppKit
import QuickLookThumbnailing
import MonikerCore
import SwiftUI

struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let problem = model.availabilityProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            ForEach(model.folderProblems, id: \.self) { problem in
                Label(problem, systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let activity = model.activity {
                Text(activity).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if !model.pending.isEmpty { suggestions }
            recent
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            if showSettings {
                Divider()
                SettingsSection()
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 380)
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: model.isWorking ? "sparkles" : "tag.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text("Moniker").font(.headline)
                Text(model.statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("Watching", isOn: $model.isWatching)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help(model.isWatching ? "Pause" : "Resume")
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested names").font(.subheadline.weight(.semibold))
            ForEach(model.pending) { suggestion in
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.newName).fontWeight(.medium).lineLimit(2)
                    Text(suggestion.url.lastPathComponent)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    HStack {
                        Button("Rename") { model.accept(suggestion) }
                            .buttonStyle(.borderedProminent)
                        Button("Skip") { model.dismiss(suggestion) }
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recently named").font(.subheadline.weight(.semibold))
                Spacer()
                if !model.recent.isEmpty {
                    Button("Clear") { withAnimation(.snappy) { model.clearRecent() } }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Clear the list. Files keep their new names.")
                }
            }
            if model.recent.isEmpty {
                Text("Take a screenshot or download a PDF. Moniker reads it on your Mac and gives it a name that says what's inside.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.recent.prefix(5)) { record in
                        RecordRow(record: record)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Name Files…") { model.chooseFilesToRename() }
                .help("Pick files to name, whatever they're called now")
            Spacer()
            Button {
                withAnimation(.snappy) { showSettings.toggle() }
            } label: {
                Image(systemName: showSettings ? "gearshape.fill" : "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .controlSize(.small)
    }
}

private struct RecordRow: View {
    @Environment(AppModel.self) private var model
    let record: RenameRecord
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Thumbnail(url: record.renamed)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.renamed.lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                Text("was " + record.original.lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button { model.reveal(record.renamed) } label: { Image(systemName: "magnifyingglass") }
                .help("Show in Finder")
            Button { model.undo(record) } label: { Image(systemName: "arrow.uturn.backward") }
                .help("Undo: put the old name back")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
        .onHover { hovering = $0 }
    }
}

private struct SettingsSection: View {
    @Environment(AppModel.self) private var model

    private var engineHelp: String {
        let now = model.engineDescription.map { "Now using \($0). " } ?? ""
        switch model.engine {
        case .apple: return now + "On-device, built into macOS."
        case .hearth: return now + "Hearth runs a local model on your Mac and shows Moniker's usage. github.com/seckinbeduk/hearth"
        case .auto: return now + "Apple Intelligence when it's available, Hearth otherwise."
        }
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            Picker("Engine", selection: $model.engine) {
                Text("Apple Intelligence").tag(Engine.apple)
                Text("Hearth").tag(Engine.hearth)
                Text("Automatic").tag(Engine.auto)
            }
            .pickerStyle(.menu)
            if model.engine != .apple {
                Picker("Hearth model", selection: $model.hearthModel) {
                    Text("Local model").tag("hearth")
                    Text("Apple Intelligence").tag("apple-intelligence")
                }
                .pickerStyle(.menu)
            }
            Text(engineHelp)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Rename automatically", isOn: $model.renameAutomatically)
            if !model.renameAutomatically {
                Text("New names wait here until you confirm them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Start names with the date", isOn: $model.addDate)
            Toggle("Add Finder tags", isOn: $model.addTags)
            Toggle("Open at login", isOn: $model.openAtLogin)

            Text("Folders").font(.subheadline.weight(.semibold)).padding(.top, 4)
            ForEach(model.folders, id: \.self) { folder in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                        .resizable().frame(width: 18, height: 18)
                    Text(FileManager.default.displayName(atPath: folder.path))
                    Spacer()
                    Button { model.removeFolder(folder) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Stop watching")
                }
            }
            Button("Add Folder…") { model.addFolder() }
                .controlSize(.small)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

/// A QuickLook preview of the file, like Finder shows; the file's icon until it's ready.
private struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(.rect(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 68, height: 68),
                                                       scale: 2, representationTypes: .thumbnail)
            if let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                image = thumbnail.nsImage
            }
        }
    }
}
