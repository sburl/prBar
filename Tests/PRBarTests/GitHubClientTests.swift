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
        XCTAssertEqual(snapshot.menuBarTitle(includeDependabot: false), "1·1")
    }
}
