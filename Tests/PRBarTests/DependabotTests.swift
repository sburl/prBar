import XCTest
@testable import PRBarCore

final class DependabotTests: XCTestCase {
    func testMatchesGitHubAppLogin() {
        XCTAssertTrue(Dependabot.matches(login: "app/dependabot"))
        XCTAssertTrue(Dependabot.matches(login: "dependabot"))
        XCTAssertTrue(Dependabot.matches(login: "dependabot[bot]"))
        XCTAssertTrue(Dependabot.matches(login: "App/Dependabot"))
    }

    func testDoesNotMatchHumanAuthors() {
        XCTAssertFalse(Dependabot.matches(login: "octocat"))
        XCTAssertFalse(Dependabot.matches(login: "renovate"))
        XCTAssertFalse(Dependabot.matches(login: ""))
    }

    func testGroupsDependabotSeparately() {
        let repo = TrackedRepo(owner: "octocat", name: "Hello-World")
        let snapshot = RepoSnapshot(
            repo: repo,
            pullRequests: [
                PullRequest.fixture(repoID: repo.id, number: 1, author: "octocat"),
                PullRequest.fixture(repoID: repo.id, number: 2, author: "app/dependabot"),
                PullRequest.fixture(repoID: repo.id, number: 3, author: "dependabot[bot]"),
            ]
        )

        XCTAssertEqual(snapshot.regularPullRequests.map(\.number), [1])
        XCTAssertEqual(snapshot.dependabotPullRequests.map(\.number), [2, 3])
        XCTAssertEqual(snapshot.visibleCount(includeDependabot: false), 1)
        XCTAssertEqual(snapshot.visibleCount(includeDependabot: true), 3)
        XCTAssertEqual(snapshot.hiddenDependabotCount, 2)
    }
}

extension PullRequest {
    static func fixture(
        repoID: String = "octocat/Hello-World",
        number: Int = 1,
        title: String = "example",
        author: String = "octocat",
        isDraft: Bool = false,
        createdAt: Date? = nil
    ) -> PullRequest {
        PullRequest(
            repoID: repoID,
            number: number,
            title: title,
            url: URL(string: "https://github.com/\(repoID)/pull/\(number)")!,
            isDraft: isDraft,
            authorLogin: author,
            createdAt: createdAt
        )
    }
}
