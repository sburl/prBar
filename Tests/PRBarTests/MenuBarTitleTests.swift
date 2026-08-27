import XCTest
@testable import PRBarCore

final class MenuBarTitleTests: XCTestCase {
    func testCompactPerRepoCounts() {
        let one = TrackedRepo(owner: "octocat", name: "one", shortLabel: "O1")
        let two = TrackedRepo(owner: "octocat", name: "two", shortLabel: "O2")
        let three = TrackedRepo(owner: "octocat", name: "three", shortLabel: "O3")
        let four = TrackedRepo(owner: "octocat", name: "four", shortLabel: "O4")
        let snapshot = DashboardSnapshot(repos: [
            RepoSnapshot(
                repo: one,
                pullRequests: [
                    .fixture(repoID: one.id, number: 1, author: "octocat"),
                    .fixture(repoID: one.id, number: 2, author: "app/dependabot"),
                ]
            ),
            RepoSnapshot(
                repo: two,
                pullRequests: [.fixture(repoID: two.id, number: 3)]
            ),
            RepoSnapshot(repo: three, pullRequests: []),
            RepoSnapshot(repo: four, error: "gh failed"),
        ])

        XCTAssertEqual(snapshot.menuBarTitle(includeDependabot: false), "1·1·0·—")
        XCTAssertEqual(snapshot.menuBarTitle(includeDependabot: true), "2·1·0·—")
        XCTAssertEqual(snapshot.totalVisible(includeDependabot: false), 2)
        XCTAssertEqual(snapshot.hiddenDependabotCount, 1)
        XCTAssertTrue(snapshot.tooltip(includeDependabot: false).contains("Dependabot not counted: 1"))
    }

    func testEmptyTitle() {
        XCTAssertEqual(DashboardSnapshot.empty.menuBarTitle(includeDependabot: false), "PRBar")
    }
}
