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

    public func countBranches(repo: TrackedRepo) async throws -> Int {
        let query = """
        query($owner: String!, $name: String!) { \
        repository(owner: $owner, name: $name) { \
        refs(refPrefix: "refs/heads/") { totalCount } } }
        """
        let result = try await runner.run(
            executable: ghURL,
            arguments: [
                "api", "graphql",
                "-f", "query=\(query)",
                "-f", "owner=\(repo.owner)",
                "-f", "name=\(repo.name)",
                "--jq", ".data.repository.refs.totalCount",
            ],
            environment: environment
        )
        guard result.exitCode == 0 else {
            throw GitHubError.commandFailed(exitCode: result.exitCode, stderr: result.stderrString)
        }
        let raw = String(data: result.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let count = Int(raw) else {
            throw GitHubError.invalidJSON("expected branch count, got “\(raw)”")
        }
        return count
    }

    public func fetchDashboard(
        repos: [TrackedRepo],
        worktreeCounter: WorktreeCounter? = nil,
        now: Date = Date()
    ) async -> DashboardSnapshot {
        guard !repos.isEmpty else {
            return DashboardSnapshot(repos: [], fetchedAt: now)
        }

        async let worktreeCountsTask = worktreeCounts(repos: repos, counter: worktreeCounter)

        var snapshots: [RepoSnapshot]
        do {
            snapshots = try await fetchAllViaGraphQL(repos: repos)
        } catch {
            // One gh call for everything is the fast path; fall back to
            // per-repo REST calls if the batched query fails outright.
            snapshots = await fetchPerRepo(repos: repos)
        }

        let worktrees = await worktreeCountsTask
        for index in snapshots.indices {
            snapshots[index].worktreeCount = worktrees[snapshots[index].repo.id]
        }
        return DashboardSnapshot(repos: snapshots, fetchedAt: now)
    }

    private func worktreeCounts(
        repos: [TrackedRepo],
        counter: WorktreeCounter?
    ) async -> [String: Int] {
        guard let counter else { return [:] }
        return await withTaskGroup(of: (String, Int?).self) { group in
            for repo in repos {
                group.addTask {
                    (repo.id, await counter.countLinkedWorktrees(for: repo))
                }
            }
            var counts: [String: Int] = [:]
            for await (id, count) in group {
                counts[id] = count
            }
            return counts
        }
    }

    // MARK: - Batched GraphQL fetch

    private static let pullRequestPageSize = 100
    private static let maxPullRequestPages = 10

    func fetchAllViaGraphQL(repos: [TrackedRepo]) async throws -> [RepoSnapshot] {
        let fragments = repos.enumerated().map { index, repo in
            Self.repoFragment(alias: "r\(index)", repo: repo, after: nil)
        }
        let query = "query { \(fragments.joined(separator: " ")) }"
        let response = try await runGraphQL(query: query)

        var snapshots: [RepoSnapshot] = []
        for (index, repo) in repos.enumerated() {
            guard let node = response["r\(index)"] ?? nil else {
                snapshots.append(RepoSnapshot(repo: repo, error: "repo not found or inaccessible"))
                continue
            }
            var pulls = node.pullRequests.nodes.map { $0.pullRequest(repoID: repo.id) }
            var pageInfo = node.pullRequests.pageInfo
            var pages = 1
            while pageInfo.hasNextPage, let cursor = pageInfo.endCursor, pages < Self.maxPullRequestPages {
                guard let next = try? await fetchPullRequestPage(repo: repo, after: cursor) else { break }
                pulls += next.nodes.map { $0.pullRequest(repoID: repo.id) }
                pageInfo = next.pageInfo
                pages += 1
            }
            snapshots.append(RepoSnapshot(
                repo: repo,
                pullRequests: pulls,
                branchCount: node.refs?.totalCount
            ))
        }
        return snapshots
    }

    private func fetchPullRequestPage(
        repo: TrackedRepo,
        after cursor: String
    ) async throws -> GHGraphPullRequests {
        let query = "query { \(Self.repoFragment(alias: "r0", repo: repo, after: cursor)) }"
        let response = try await runGraphQL(query: query)
        guard let node = response["r0"] ?? nil else {
            throw GitHubError.invalidJSON("missing repository node for \(repo.fullName)")
        }
        return node.pullRequests
    }

    private func runGraphQL(query: String) async throws -> [String: GHGraphRepo?] {
        let result = try await runner.run(
            executable: ghURL,
            arguments: ["api", "graphql", "-f", "query=\(query)"],
            environment: environment
        )
        // gh exits non-zero when the response carries GraphQL errors, but
        // partial data may still be present in stdout — try to use it.
        let decoded = try? JSONDecoder().decode(GHGraphResponse.self, from: result.stdout)
        guard let data = decoded?.data else {
            if result.exitCode != 0 {
                throw GitHubError.commandFailed(exitCode: result.exitCode, stderr: result.stderrString)
            }
            throw GitHubError.invalidJSON("unexpected GraphQL response shape")
        }
        return data
    }

    /// Owner and name are validated against GitHub's allowed characters at
    /// parse time, so direct interpolation into the query is safe.
    private static func repoFragment(alias: String, repo: TrackedRepo, after: String?) -> String {
        let afterArg = after.map { ", after: \"\($0)\"" } ?? ""
        return """
        \(alias): repository(owner: "\(repo.owner)", name: "\(repo.name)") { \
        refs(refPrefix: "refs/heads/") { totalCount } \
        pullRequests(states: OPEN, first: \(pullRequestPageSize), \
        orderBy: {field: CREATED_AT, direction: DESC}\(afterArg)) { \
        pageInfo { hasNextPage endCursor } \
        nodes { number title url isDraft createdAt \
        author { login } reviewDecision } } }
        """
    }

    // MARK: - Per-repo REST fallback

    private func fetchPerRepo(repos: [TrackedRepo]) async -> [RepoSnapshot] {
        await withTaskGroup(of: RepoSnapshot.self) { group in
            for repo in repos {
                group.addTask {
                    async let branches = try? countBranches(repo: repo)
                    do {
                        let prs = try await listOpenPullRequests(repo: repo)
                        return await RepoSnapshot(repo: repo, pullRequests: prs, branchCount: branches)
                    } catch {
                        return await RepoSnapshot(
                            repo: repo,
                            error: error.localizedDescription,
                            branchCount: branches
                        )
                    }
                }
            }

            var byID: [String: RepoSnapshot] = [:]
            for await snapshot in group {
                byID[snapshot.repo.id] = snapshot
            }

            return repos.map { repo in
                byID[repo.id] ?? RepoSnapshot(repo: repo, error: "missing snapshot")
            }
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

struct GHGraphResponse: Decodable {
    let data: [String: GHGraphRepo?]?
}

struct GHGraphRepo: Decodable {
    struct Refs: Decodable {
        let totalCount: Int
    }

    let refs: Refs?
    let pullRequests: GHGraphPullRequests
}

struct GHGraphPullRequests: Decodable {
    struct PageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }

    let pageInfo: PageInfo
    let nodes: [GHGraphPullRequest]
}

struct GHGraphPullRequest: Decodable {
    struct Author: Decodable {
        let login: String
    }

    let number: Int
    let title: String
    let url: URL
    let isDraft: Bool
    let createdAt: String?
    let author: Author?
    let reviewDecision: String?

    func pullRequest(repoID: String) -> PullRequest {
        PullRequest(
            repoID: repoID,
            number: number,
            title: title,
            url: url,
            isDraft: isDraft,
            authorLogin: author?.login ?? "",
            createdAt: parseGitHubDate(createdAt),
            reviewDecision: reviewDecision.flatMap(ReviewDecision.init(rawValue:))
        )
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
