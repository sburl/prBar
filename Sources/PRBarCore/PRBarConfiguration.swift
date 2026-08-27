import Foundation

public enum RefreshIntervalPreset: String, Equatable, Sendable, CaseIterable {
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case manual

    public var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1800
        case .manual: 0
        }
    }

    public var menuTitle: String {
        switch self {
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .manual: "Manual only"
        }
    }

    public static func matching(_ seconds: TimeInterval) -> RefreshIntervalPreset? {
        allCases.first { $0.seconds == seconds }
    }
}

public struct PRBarConfiguration: Equatable, Sendable, Codable {
    public var includeDependabotInCounts: Bool
    public var refreshInterval: TimeInterval
    public var repos: [TrackedRepo]

    public init(
        includeDependabotInCounts: Bool = false,
        refreshInterval: TimeInterval = 120,
        repos: [TrackedRepo] = []
    ) {
        self.includeDependabotInCounts = includeDependabotInCounts
        self.refreshInterval = refreshInterval
        self.repos = repos
    }

    public static let empty = PRBarConfiguration()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        includeDependabotInCounts = try container.decodeIfPresent(Bool.self, forKey: .includeDependabotInCounts) ?? false
        refreshInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 120
        repos = try container.decodeIfPresent([TrackedRepo].self, forKey: .repos) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case includeDependabotInCounts, refreshInterval, repos
    }

    public mutating func addRepo(_ repo: TrackedRepo) throws {
        if repos.contains(where: { $0.id == repo.id }) {
            throw PRBarConfigError.duplicateRepo(repo.fullName)
        }
        repos.append(repo)
    }

    public mutating func removeRepos(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            repos.remove(at: index)
        }
    }

    public mutating func moveRepos(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.sorted().map { repos[$0] }
        for index in offsets.sorted(by: >) {
            repos.remove(at: index)
        }
        let adjusted = destination - offsets.filter { $0 < destination }.count
        repos.insert(contentsOf: moving, at: min(max(adjusted, 0), repos.count))
    }

    public mutating func updateRepo(id: String, shortLabel: String, displayName: String) {
        guard let index = repos.firstIndex(where: { $0.id == id }) else { return }
        let normalized = TrackedRepo.normalizeShortLabel(shortLabel, name: repos[index].name)
        if !normalized.isEmpty {
            repos[index].shortLabel = normalized
        }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        repos[index].displayName = trimmedName.isEmpty ? repos[index].name : trimmedName
    }
}

public enum PRBarConfigError: Error, Equatable, LocalizedError {
    case invalidRepo(String)
    case duplicateRepo(String)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidRepo(raw):
            return "Could not parse “\(raw)”. Use owner/name or a github.com URL."
        case let .duplicateRepo(name):
            return "\(name) is already in the list."
        case let .unreadable(message):
            return message
        }
    }
}

public enum PRBarConfigFile {
    public static func defaultURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".config/prbar/config.json")
    }

    public static func load(
        from url: URL = PRBarConfigFile.defaultURL(),
        fileManager: FileManager = .default
    ) throws -> PRBarConfiguration {
        guard fileManager.fileExists(atPath: url.path) else {
            return .empty
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(PRBarConfiguration.self, from: data)
        } catch {
            throw PRBarConfigError.unreadable("Could not read \(url.path): \(error.localizedDescription)")
        }
    }

    public static func save(
        _ configuration: PRBarConfiguration,
        to url: URL = PRBarConfigFile.defaultURL(),
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
