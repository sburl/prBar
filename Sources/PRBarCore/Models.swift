import Foundation

public struct TrackedRepo: Equatable, Sendable, Identifiable, Codable {
    public var id: String { fullName.lowercased() }
    public var owner: String
    public var name: String
    public var shortLabel: String
    public var displayName: String

    public var fullName: String { "\(owner)/\(name)" }

    public var pullsURL: URL {
        URL(string: "https://github.com/\(fullName)/pulls")!
    }

    public init(owner: String, name: String, shortLabel: String? = nil, displayName: String? = nil) {
        self.owner = owner
        self.name = name
        self.displayName = displayName?.isEmpty == false ? displayName! : name
        self.shortLabel = Self.makeShortLabel(shortLabel, name: name)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let owner = try container.decode(String.self, forKey: .owner)
        let name = try container.decode(String.self, forKey: .name)
        let shortLabel = try container.decodeIfPresent(String.self, forKey: .shortLabel)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        self.init(owner: owner, name: name, shortLabel: shortLabel, displayName: displayName)
    }

    private enum CodingKeys: String, CodingKey {
        case owner, name, shortLabel, displayName
    }

    public static func parse(
        _ raw: String,
        shortLabel: String? = nil,
        displayName: String? = nil
    ) throws -> TrackedRepo {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PRBarConfigError.invalidRepo(raw)
        }

        var path = trimmed
        if trimmed.lowercased().hasPrefix("git@") {
            guard let colon = trimmed.firstIndex(of: ":") else {
                throw PRBarConfigError.invalidRepo(raw)
            }
            path = String(trimmed[trimmed.index(after: colon)...])
        } else if let url = URL(string: trimmed), let host = url.host?.lowercased(), host.contains("github.com") {
            path = url.path
        } else if trimmed.contains("://") {
            throw PRBarConfigError.invalidRepo(raw)
        }

        if path.hasSuffix(".git") {
            path = String(path.dropLast(4))
        }

        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard parts.count >= 2 else {
            throw PRBarConfigError.invalidRepo(raw)
        }

        let owner = parts[0]
        let name = parts[1]
        guard isGitHubName(owner), isGitHubName(name) else {
            throw PRBarConfigError.invalidRepo(raw)
        }
        return TrackedRepo(owner: owner, name: name, shortLabel: shortLabel, displayName: displayName)
    }

    public static func normalizeShortLabel(_ requested: String?, name: String) -> String {
        if let requested {
            let compact = requested
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
                .filter { $0.isLetter || $0.isNumber }
            if !compact.isEmpty {
                return String(compact.prefix(2))
            }
        }
        let tokens = name.split { $0 == "-" || $0 == "_" || $0 == "." }
        if tokens.count >= 2 {
            return tokens.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private static func isGitHubName(_ value: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return !value.isEmpty && value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func makeShortLabel(_ requested: String?, name: String) -> String {
        normalizeShortLabel(requested, name: name)
    }
}

public struct PullRequest: Equatable, Sendable, Identifiable {
    public var id: String { "\(repoID)#\(number)" }
    public let repoID: String
    public let number: Int
    public let title: String
    public let url: URL
    public let isDraft: Bool
    public let authorLogin: String
    public let createdAt: Date?

    public var isDependabot: Bool {
        Dependabot.matches(login: authorLogin)
    }

    public init(
        repoID: String,
        number: Int,
        title: String,
        url: URL,
        isDraft: Bool,
        authorLogin: String,
        createdAt: Date? = nil
    ) {
        self.repoID = repoID
        self.number = number
        self.title = title
        self.url = url
        self.isDraft = isDraft
        self.authorLogin = authorLogin
        self.createdAt = createdAt
    }

    /// Fixed-width opened date so submenu rows line up: `08-12`.
    public var openedDateLabel: String {
        guard let createdAt else { return "     " }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.month, .day], from: createdAt)
        guard let month = parts.month, let day = parts.day else {
            return "     "
        }
        return String(format: "%02d-%02d", month, day)
    }

    public func menuTitle(markDependabot: Bool, titleLimit: Int = 72) -> String {
        var prefix = "#\(number)"
        if isDraft { prefix += " [draft]" }
        if markDependabot, isDependabot { prefix += " [deps]" }
        let clipped: String
        if title.count > titleLimit {
            clipped = String(title.prefix(titleLimit - 1)) + "…"
        } else {
            clipped = title
        }
        return "\(openedDateLabel)  \(prefix)  \(clipped)"
    }
}

public enum Dependabot {
    public static func matches(login: String) -> Bool {
        login.lowercased().contains("dependabot")
    }
}

public struct RepoSnapshot: Equatable, Sendable {
    public var repo: TrackedRepo
    public var pullRequests: [PullRequest]
    public var error: String?

    public init(repo: TrackedRepo, pullRequests: [PullRequest] = [], error: String? = nil) {
        self.repo = repo
        self.pullRequests = pullRequests
        self.error = error
    }

    public var regularPullRequests: [PullRequest] {
        pullRequests.filter { !$0.isDependabot }
    }

    public var dependabotPullRequests: [PullRequest] {
        pullRequests.filter(\.isDependabot)
    }

    public func visiblePullRequests(includeDependabot: Bool) -> [PullRequest] {
        includeDependabot ? pullRequests : regularPullRequests
    }

    public func visibleCount(includeDependabot: Bool) -> Int? {
        if error != nil, pullRequests.isEmpty { return nil }
        return visiblePullRequests(includeDependabot: includeDependabot).count
    }

    public var hiddenDependabotCount: Int {
        dependabotPullRequests.count
    }
}

public struct DashboardSnapshot: Equatable, Sendable {
    public var repos: [RepoSnapshot]
    public var fetchedAt: Date?

    public init(repos: [RepoSnapshot] = [], fetchedAt: Date? = nil) {
        self.repos = repos
        self.fetchedAt = fetchedAt
    }

    public static let empty = DashboardSnapshot()

    public func totalVisible(includeDependabot: Bool) -> Int {
        repos.reduce(0) { partial, repo in
            partial + (repo.visibleCount(includeDependabot: includeDependabot) ?? 0)
        }
    }

    public var hiddenDependabotCount: Int {
        repos.reduce(0) { $0 + $1.hiddenDependabotCount }
    }

    public var hasErrors: Bool {
        repos.contains { $0.error != nil }
    }

    public func menuBarTitle(includeDependabot: Bool) -> String {
        guard !repos.isEmpty else { return "PRBar" }
        return repos.map { snapshot in
            if let value = snapshot.visibleCount(includeDependabot: includeDependabot) {
                return String(value)
            }
            return "—"
        }
        .joined(separator: "·")
    }

    public func tooltip(includeDependabot: Bool) -> String {
        guard !repos.isEmpty else {
            return "No repos yet. Open Repos… to add some."
        }
        var lines = repos.map { snapshot -> String in
            let count = snapshot.visibleCount(includeDependabot: includeDependabot)
                .map(String.init) ?? "error"
            let suffix = snapshot.error.map { " (\($0))" } ?? ""
            return "\(snapshot.repo.displayName): \(count)\(suffix)"
        }
        let hidden = hiddenDependabotCount
        if !includeDependabot, hidden > 0 {
            lines.append("Dependabot not counted: \(hidden)")
        }
        return lines.joined(separator: "\n")
    }
}
