import AppKit
import SwiftUI
import PRBarCore

struct ReposSettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var draft = ""
    @State private var displayName = ""
    @State private var shortLabel = ""
    @State private var suggestedDisplayName = ""
    @State private var suggestedShortLabel = ""
    @State private var errorMessage: String?
    @State private var selection = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracked repositories")
                .font(.headline)

            Text("Drag to reorder. Counts in the menu bar follow this order. Name and abbreviation are yours — they do not have to match GitHub.")
                .foregroundStyle(.secondary)
                .font(.callout)

            List(selection: $selection) {
                ForEach(settings.repos) { repo in
                    RepoRowView(repo: repo) { label, name in
                        settings.updateRepo(id: repo.id, shortLabel: label, displayName: name)
                    }
                    .tag(repo.id)
                }
                .onMove(perform: settings.moveRepos)
                .onDelete(perform: settings.removeRepos)
            }
            .listStyle(.inset)
            .frame(minHeight: 180)

            VStack(alignment: .leading, spacing: 8) {
                TextField("owner/name or GitHub URL", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addRepo)
                    .onChange(of: draft, applySuggestions)

                HStack(spacing: 8) {
                    TextField("Name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addRepo)
                    TextField("AB", text: $shortLabel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 52)
                        .onChange(of: shortLabel) { _, value in
                            let clipped = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(2))
                            if clipped != value {
                                shortLabel = clipped
                            }
                        }
                        .onSubmit(addRepo)
                    Button("Add", action: addRepo)
                        .keyboardShortcut(.defaultAction)
                    Button("Remove", action: removeSelected)
                        .disabled(selection.isEmpty)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Text("Saved to ~/.config/prbar/config.json")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 400)
    }

    private func applySuggestions(_ old: String, _ new: String) {
        guard let parsed = try? TrackedRepo.parse(new) else { return }
        if displayName.isEmpty || displayName == suggestedDisplayName {
            displayName = parsed.displayName
        }
        if shortLabel.isEmpty || shortLabel == suggestedShortLabel {
            shortLabel = parsed.shortLabel
        }
        suggestedDisplayName = parsed.displayName
        suggestedShortLabel = parsed.shortLabel
    }

    private func addRepo() {
        do {
            try settings.addRepo(from: draft, displayName: displayName, shortLabel: shortLabel)
            draft = ""
            displayName = ""
            shortLabel = ""
            suggestedDisplayName = ""
            suggestedShortLabel = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeSelected() {
        let offsets = IndexSet(
            settings.repos.enumerated().compactMap { index, repo in
                selection.contains(repo.id) ? index : nil
            }
        )
        settings.removeRepos(at: offsets)
        selection.removeAll()
    }
}

private struct RepoRowView: View {
    let repo: TrackedRepo
    let onChange: (String, String) -> Void

    @State private var shortLabel: String
    @State private var displayName: String

    init(repo: TrackedRepo, onChange: @escaping (String, String) -> Void) {
        self.repo = repo
        self.onChange = onChange
        _shortLabel = State(initialValue: repo.shortLabel)
        _displayName = State(initialValue: repo.displayName)
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("AB", text: $shortLabel)
                .font(.body.monospaced())
                .frame(width: 44)
                .onChange(of: shortLabel) { _, value in
                    let clipped = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(2))
                    if clipped != value {
                        shortLabel = clipped
                        return
                    }
                    onChange(clipped, displayName)
                }
            TextField("Name", text: $displayName)
                .onChange(of: displayName) { _, value in
                    onChange(shortLabel, value)
                }
                .onSubmit {
                    onChange(shortLabel, displayName)
                }
            Text(repo.fullName)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

@MainActor
final class ReposWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
    }

    func show() {
        if window == nil {
            let view = ReposSettingsView(settings: settings)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "PRBar Repos"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 600, height: 440))
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
