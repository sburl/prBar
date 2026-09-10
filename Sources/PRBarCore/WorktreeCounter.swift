import Foundation

/// Counts linked git worktrees for a tracked repo's local clone.
public struct WorktreeCounter: Sendable {
    public var runner: any ProcessRunning
    public var gitURL: URL
    public var searchRoots: [URL]

    public init(
        runner: any ProcessRunning = FoundationProcessRunner(),
        gitURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        searchRoots: [URL] = WorktreeCounter.defaultSearchRoots()
    ) {
        self.runner = runner
        self.gitURL = gitURL
        self.searchRoots = searchRoots
    }

    public static func defaultSearchRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            home.appendingPathComponent("developer"),
            home.appendingPathComponent("Developer"),
        ]
    }

    public func localCloneURL(
        for repo: TrackedRepo,
        fileManager: FileManager = .default
    ) -> URL? {
        if let localPath = repo.localPath {
            let expanded = (localPath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            return isGitCheckout(url, fileManager: fileManager) ? url : nil
        }
        for root in searchRoots {
            let url = root.appendingPathComponent(repo.name)
            if isGitCheckout(url, fileManager: fileManager) {
                return url
            }
        }
        return nil
    }

    /// Linked worktrees (the main checkout is not counted). nil when no
    /// local clone was found or git failed.
    public func countLinkedWorktrees(for repo: TrackedRepo) async -> Int? {
        guard let clone = localCloneURL(for: repo) else { return nil }
        guard let result = try? await runner.run(
            executable: gitURL,
            arguments: ["-C", clone.path, "worktree", "list", "--porcelain"],
            environment: ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        ), result.exitCode == 0 else {
            return nil
        }
        let output = String(data: result.stdout, encoding: .utf8) ?? ""
        let checkouts = output
            .split(separator: "\n")
            .filter { $0.hasPrefix("worktree ") }
            .count
        return max(checkouts - 1, 0)
    }

    private func isGitCheckout(_ url: URL, fileManager: FileManager) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent(".git").path)
    }
}
