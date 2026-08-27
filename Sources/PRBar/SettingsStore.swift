import Foundation
import Observation
import PRBarCore

@MainActor
@Observable
final class SettingsStore {
    var includeDependabot: Bool {
        didSet { persist() }
    }

    var refreshInterval: TimeInterval {
        didSet { persist() }
    }

    var repos: [TrackedRepo] {
        didSet { persist() }
    }

    private let fileURL: URL

    init(fileURL: URL = PRBarConfigFile.defaultURL()) {
        self.fileURL = fileURL
        let loaded = (try? PRBarConfigFile.load(from: fileURL)) ?? .empty
        includeDependabot = loaded.includeDependabotInCounts
        refreshInterval = loaded.refreshInterval > 0 ? loaded.refreshInterval : 120
        repos = loaded.repos

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let legacy = UserDefaults.standard.object(forKey: "includeDependabot") as? Bool
            if let legacy {
                includeDependabot = legacy
            }
            persist()
        }
    }

    func addRepo(from raw: String, displayName: String = "", shortLabel: String = "") throws {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = shortLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        var configuration = currentConfiguration
        try configuration.addRepo(
            try TrackedRepo.parse(
                raw,
                shortLabel: label.isEmpty ? nil : label,
                displayName: name.isEmpty ? nil : name
            )
        )
        repos = configuration.repos
    }

    func removeRepos(at offsets: IndexSet) {
        var configuration = currentConfiguration
        configuration.removeRepos(at: offsets)
        repos = configuration.repos
    }

    func moveRepos(from offsets: IndexSet, to destination: Int) {
        var configuration = currentConfiguration
        configuration.moveRepos(from: offsets, to: destination)
        repos = configuration.repos
    }

    func updateRepo(id: String, shortLabel: String, displayName: String) {
        var configuration = currentConfiguration
        configuration.updateRepo(id: id, shortLabel: shortLabel, displayName: displayName)
        repos = configuration.repos
    }

    private var currentConfiguration: PRBarConfiguration {
        PRBarConfiguration(
            includeDependabotInCounts: includeDependabot,
            refreshInterval: refreshInterval,
            repos: repos
        )
    }

    private func persist() {
        try? PRBarConfigFile.save(currentConfiguration, to: fileURL)
    }
}
