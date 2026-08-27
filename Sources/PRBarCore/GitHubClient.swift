import Foundation

public enum GitHubError: Error, Equatable, LocalizedError {
    case ghNotFound
    case commandFailed(exitCode: Int32, stderr: String)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .ghNotFound:
            return "GitHub CLI (`gh`) not found. Install it with `brew install gh` and run `gh auth login`."
        case let .commandFailed(_, stderr):
            return stderr.isEmpty ? "gh failed" : stderr
        case let .invalidJSON(message):
            return "Could not parse gh output: \(message)"
        }
    }
}

public struct GitHubClient: Sendable {
    public var runner: any ProcessRunning
    public var ghURL: URL
    public var environment: [String: String]
    public var pullRequestLimit: Int

    public init(
        runner: any ProcessRunning = FoundationProcessRunner(),
        ghURL: URL? = nil,
        environment: [String: String] = GitHubClient.defaultEnvironment(),
        pullRequestLimit: Int = 1000
    ) throws {
        guard let resolved = ghURL ?? GitHubCLI.resolveExecutable(environment: environment) else {
            throw GitHubError.ghNotFound
        }
        self.runner = runner
        self.ghURL = resolved
        self.environment = environment
        self.pullRequestLimit = pullRequestLimit
    }

    public func listOpenPullRequests(repo: TrackedRepo) async throws -> [PullRequest] {
        let result = try await runner.run(
            executable: ghURL,
            arguments: [
                "pr", "list",
                "--repo", repo.fullName,
                "--state", "open",
                "--limit", String(pullRequestLimit),
                "--json", "number,title,author,url,isDraft,createdAt",
            ],
            environment: environment
        )

        guard result.exitCode == 0 else {
            throw GitHubError.commandFailed(exitCode: result.exitCode, stderr: result.stderrString)
        }

        return try PullRequest.decodeList(from: result.stdout, repoID: repo.id)
    }

    public func fetchDashboard(
        repos: [TrackedRepo],
        now: Date = Date()
    ) async -> DashboardSnapshot {
        await withTaskGroup(of: RepoSnapshot.self) { group in
            for repo in repos {
                group.addTask {
                    do {
                        let prs = try await listOpenPullRequests(repo: repo)
                        return RepoSnapshot(repo: repo, pullRequests: prs)
                    } catch {
                        return RepoSnapshot(
                            repo: repo,
                            error: error.localizedDescription
                        )
                    }
                }
            }

            var byID: [String: RepoSnapshot] = [:]
            for await snapshot in group {
                byID[snapshot.repo.id] = snapshot
            }

            let ordered = repos.map { repo in
                byID[repo.id] ?? RepoSnapshot(repo: repo, error: "missing snapshot")
            }
            return DashboardSnapshot(repos: ordered, fetchedAt: now)
        }
    }

    public static func defaultEnvironment(
        from base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let path = env["PATH"], !path.isEmpty {
            env["PATH"] = extraPath + ":" + path
        } else {
            env["PATH"] = extraPath
        }
        if env["HOME"] == nil || env["HOME"]?.isEmpty == true {
            env["HOME"] = NSHomeDirectory()
        }
        env["GH_PAGER"] = "cat"
        env["GH_PROMPT_DISABLED"] = "1"
        return env
    }
}

public enum GitHubCLI {
    public static let candidatePaths = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
    ]

    public static func resolveExecutable(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        for path in candidatePaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") {
                let url = URL(fileURLWithPath: String(directory)).appendingPathComponent("gh")
                if fileManager.isExecutableFile(atPath: url.path) {
                    return url
                }
            }
        }

        return nil
    }
}

private struct GHPullRequest: Decodable {
    let number: Int
    let title: String
    let url: URL
    let isDraft: Bool
    let author: GHAuthor?
    let createdAt: String?
}

private struct GHAuthor: Decodable {
    let login: String
}

extension PullRequest {
    public static func decodeList(from data: Data, repoID: String) throws -> [PullRequest] {
        do {
            let decoded = try JSONDecoder().decode([GHPullRequest].self, from: data)
            return decoded.map { row in
                PullRequest(
                    repoID: repoID,
                    number: row.number,
                    title: row.title,
                    url: row.url,
                    isDraft: row.isDraft,
                    authorLogin: row.author?.login ?? "",
                    createdAt: parseGitHubDate(row.createdAt)
                )
            }
        } catch {
            throw GitHubError.invalidJSON(error.localizedDescription)
        }
    }
}

private func parseGitHubDate(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: raw) {
        return date
    }
    let basic = ISO8601DateFormatter()
    basic.formatOptions = [.withInternetDateTime]
    return basic.date(from: raw)
}
