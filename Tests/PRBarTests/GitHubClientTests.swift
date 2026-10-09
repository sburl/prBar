import XCTest
@testable import PRBarCore

private struct MockRunner: ProcessRunning {
    var handler: @Sendable (URL, [String]) -> ProcessResult

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ProcessResult {
        handler(executable, arguments)
    }
}

final class FoundationProcessRunnerTests: XCTestCase {
    func testRunCompletesAndCapturesStdout() async throws {
        let result = try await FoundationProcessRunner().run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["prbar-ok"],
            environment: ["PATH": "/bin:/usr/bin"]
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            String(data: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            "prbar-ok"
        )
    }

    func testRunDrainsLargeStdoutWithoutDeadlock() async throws {
        let result = try await FoundationProcessRunner().run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "python3 -c 'print(\"x\"*200000)'"],
            environment: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertGreaterThan(result.stdout.count, 100_000)
    }
}

final class GitHubClientTests: XCTestCase {
    func testListsOpenPullRequestsFromGhJSON() async throws {
        let repo = TrackedRepo(owner: "octocat", name: "hello-world")
        let json = """
        [{"author":{"login":"octocat","is_bot":false},"isDraft":false,"number":10,"title":"hello","url":"https://github.com/octocat/hello-world/pull/10"}]
        """.data(using: .utf8)!

        let runner = MockRunner { _, arguments in
            XCTAssertTrue(arguments.contains("octocat/hello-world"))
            XCTAssertTrue(arguments.contains("open"))
            return ProcessResult(exitCode: 0, stdout: json, stderr: Data())
        }

        let client = try GitHubClient(
            runner: runner,
            ghURL: URL(fileURLWithPath: "/opt/homebrew/bin/gh")
        )
        let prs = try await client.listOpenPullRequests(repo: repo)
        XCTAssertEqual(prs, [
            PullRequest.fixture(repoID: repo.id, number: 10, title: "hello"),
        ])
    }

    func testCommandFailureSurfacesStderr() async throws {
        let runner = MockRunner { _, _ in
            ProcessResult(
                exitCode: 1,
                stdout: Data(),
                stderr: Data("HTTP 401: Bad credentials".utf8)
            )
        }
        let client = try GitHubClient(
            runner: runner,
            ghURL: URL(fileURLWithPath: "/opt/homebrew/bin/gh")
        )

        do {
            _ = try await client.listOpenPullRequests(repo: TrackedRepo(owner: "octocat", name: "hello-world"))
            XCTFail("expected commandFailed")
        } catch let error as GitHubError {
            XCTAssertEqual(
                error,
                .commandFailed(exitCode: 1, stderr: "HTTP 401: Bad credentials")
            )
        }
    }

    func testDashboardFetchesEveryRepo() async throws {
        let repos = [
            TrackedRepo(owner: "octocat", name: "one", shortLabel: "O1"),
            TrackedRepo(owner: "octocat", name: "two", shortLabel: "O2"),
        ]
        let runner = MockRunner { _, arguments in
            if arguments.contains("graphql") {
                return ProcessResult(exitCode: 0, stdout: Data("7\n".utf8), stderr: Data())
            }
            let repo = arguments[arguments.firstIndex(of: "--repo")! + 1]
            let number = repo.hasSuffix("one") ? 1 : 2
            let json = """
            [{"author":{"login":"octocat"},"isDraft":false,"number":\(number),"title":"pr","url":"https://github.com/\(repo)/pull/\(number)"}]
            """
            return ProcessResult(exitCode: 0, stdout: Data(json.utf8), stderr: Data())
        }

        let client = try GitHubClient(
            runner: runner,
            ghURL: URL(fileURLWithPath: "/usr/bin/gh")
        )
        let snapshot = await client.fetchDashboard(repos: repos, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(snapshot.repos.map(\.repo.shortLabel), ["O1", "O2"])
        XCTAssertEqual(snapshot.repos.map { $0.pullRequests.first?.number }, [1, 2])
        XCTAssertEqual(snapshot.repos.map(\.branchCount), [7, 7])
        XCTAssertEqual(snapshot.menuBarTitle(includeDependabot: false), "1·1")
    }

    func testBatchedGraphQLDashboard() async throws {
        let repos = [
            TrackedRepo(owner: "octocat", name: "one", shortLabel: "O1"),
            TrackedRepo(owner: "octocat", name: "two", shortLabel: "O2"),
        ]
        let json = """
        {"data":{
          "r0":{
            "refs":{"totalCount":32},
            "pullRequests":{
              "pageInfo":{"hasNextPage":false,"endCursor":null},
              "nodes":[{
                "number":1,"title":"pr one","url":"https://github.com/octocat/one/pull/1",
                "isDraft":false,"createdAt":"2026-08-12T10:00:00Z",
                "author":{"login":"octocat"},
                "reviewDecision":"APPROVED",
                "isInMergeQueue":true,
                "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"PENDING"}}}]}
              },{
                "number":2,"title":"no checks","url":"https://github.com/octocat/one/pull/2",
                "isDraft":false,"createdAt":"2026-08-12T10:00:00Z",
                "author":{"login":"octocat"},
                "reviewDecision":null,
                "isInMergeQueue":false,
                "commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}
              }]
            }
          },
          "r1":null
        }}
        """
        let runner = MockRunner { _, arguments in
            XCTAssertTrue(arguments.contains("graphql"))
            return ProcessResult(exitCode: 0, stdout: Data(json.utf8), stderr: Data())
        }
        let client = try GitHubClient(
            runner: runner,
            ghURL: URL(fileURLWithPath: "/usr/bin/gh")
        )

        let snapshots = try await client.fetchAllViaGraphQL(repos: repos)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].branchCount, 32)
        let pr = try XCTUnwrap(snapshots[0].pullRequests.first)
        XCTAssertEqual(pr.number, 1)
        XCTAssertEqual(pr.reviewDecision, .approved)
        XCTAssertNotNil(pr.createdAt)
        XCTAssertEqual(pr.checkStatus, .pending)
        XCTAssertTrue(pr.isInMergeQueue)
        let unchecked = try XCTUnwrap(snapshots[0].pullRequests.last)
        XCTAssertNil(unchecked.checkStatus)
        XCTAssertFalse(unchecked.isInMergeQueue)
        XCTAssertEqual(snapshots[1].error, "repo not found or inaccessible")
    }

    func testCountBranchesParsesGraphQLOutput() async throws {
        let runner = MockRunner { _, arguments in
            XCTAssertTrue(arguments.contains("graphql"))
            XCTAssertTrue(arguments.contains("owner=octocat"))
            XCTAssertTrue(arguments.contains("name=hello-world"))
            return ProcessResult(exitCode: 0, stdout: Data("32\n".utf8), stderr: Data())
        }
        let client = try GitHubClient(
            runner: runner,
            ghURL: URL(fileURLWithPath: "/usr/bin/gh")
        )
        let count = try await client.countBranches(repo: TrackedRepo(owner: "octocat", name: "hello-world"))
        XCTAssertEqual(count, 32)
    }

    func testBranchCountFailureLeavesNil() async throws {
        let runner = MockRunner { _, arguments in
            if arguments.contains("graphql") {
                return ProcessResult(exitCode: 1, stdout: Data(), stderr: Data("boom".utf8))
            }
            return ProcessResult(exitCode: 0, stdout: Data("[]".utf8), stderr: Data())
        }
        let client = try GitHubClient(
            runner: runner,
            ghURL: URL(fileURLWithPath: "/usr/bin/gh")
        )
        let snapshot = await client.fetchDashboard(repos: [TrackedRepo(owner: "octocat", name: "one")])
        XCTAssertEqual(snapshot.repos.map(\.branchCount), [nil])
        XCTAssertEqual(snapshot.repos.first?.error, nil)
    }
}

final class WorktreeCounterTests: XCTestCase {
    func testCountsLinkedWorktreesFromPorcelainOutput() async throws {
        let clone = FileManager.default.temporaryDirectory
            .appendingPathComponent("prbar-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: clone.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: clone) }

        let porcelain = """
        worktree \(clone.path)
        HEAD abc

        worktree \(clone.path)-feature
        HEAD def

        worktree \(clone.path)-fix
        HEAD ghi
        """
        let runner = MockRunner { _, arguments in
            XCTAssertEqual(Array(arguments.suffix(3)), ["worktree", "list", "--porcelain"])
            return ProcessResult(exitCode: 0, stdout: Data(porcelain.utf8), stderr: Data())
        }

        let counter = WorktreeCounter(runner: runner, searchRoots: [])
        let repo = TrackedRepo(owner: "octocat", name: "hello-world", localPath: clone.path)
        let count = await counter.countLinkedWorktrees(for: repo)
        XCTAssertEqual(count, 2)
    }

    func testNoLocalCloneReturnsNil() async {
        let counter = WorktreeCounter(
            runner: MockRunner { _, _ in ProcessResult(exitCode: 0, stdout: Data(), stderr: Data()) },
            searchRoots: [URL(fileURLWithPath: "/nonexistent-prbar-root")]
        )
        let count = await counter.countLinkedWorktrees(
            for: TrackedRepo(owner: "octocat", name: "hello-world")
        )
        XCTAssertNil(count)
    }
}
