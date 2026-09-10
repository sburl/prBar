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

        XCTAssertEqual(snapshot.menuBarTitle(includeDependabot: false), "1·1·—")
        XCTAssertEqual(snapshot.menuBarTitle(includeDependabot: true), "2·1·—")
        XCTAssertEqual(snapshot.totalVisible(includeDependabot: false), 2)
        XCTAssertEqual(snapshot.hiddenDependabotCount, 1)
        XCTAssertTrue(snapshot.tooltip(includeDependabot: false).contains("Dependabot not counted: 1"))
        XCTAssertEqual(
            snapshot.reposOrderedForMenu(includeDependabot: false).map(\.repo.shortLabel),
            ["O1", "O2", "O4", "O3"]
        )
    }

    func testAllZeroTitle() {
        let one = TrackedRepo(owner: "octocat", name: "one", shortLabel: "O1")
        let snapshot = DashboardSnapshot(repos: [RepoSnapshot(repo: one, pullRequests: [])])
        XCTAssertEqual(snapshot.menuBarTitle(includeDependabot: false), "✓")
    }

    func testDependabotOnlyRepoHiddenWhenNotCounted() {
        let one = TrackedRepo(owner: "octocat", name: "one", shortLabel: "O1")
        let two = TrackedRepo(owner: "octocat", name: "two", shortLabel: "O2")
        let snapshot = DashboardSnapshot(repos: [
            RepoSnapshot(
                repo: one,
                pullRequests: [.fixture(repoID: one.id, number: 1, author: "app/dependabot")]
            ),
            RepoSnapshot(repo: two, pullRequests: [.fixture(repoID: two.id, number: 2)]),
        ])
        XCTAssertEqual(snapshot.menuBarTitle(includeDependabot: false), "1")
        XCTAssertEqual(snapshot.menuBarTitle(includeDependabot: true), "1·1")
        XCTAssertEqual(
            snapshot.reposOrderedForMenu(includeDependabot: false).map(\.repo.shortLabel),
            ["O2", "O1"]
        )
    }

    func testMenuRowTitleSegments() {
        let repo = TrackedRepo(owner: "octocat", name: "acorn", displayName: "Acorn-Compute")
        var snapshot = RepoSnapshot(
            repo: repo,
            pullRequests: (1...3).map { .fixture(repoID: repo.id, number: $0) },
            branchCount: 32,
            worktreeCount: 1
        )
        XCTAssertEqual(
            snapshot.menuRowTitle(includeDependabot: false),
            "Acorn-Compute  3 PRs | 32 branches | 1 worktree"
        )

        snapshot.branchCount = nil
        snapshot.worktreeCount = nil
        XCTAssertEqual(snapshot.menuRowTitle(includeDependabot: false), "Acorn-Compute  3 PRs")

        let errored = RepoSnapshot(repo: repo, error: "gh failed", branchCount: 5)
        XCTAssertEqual(errored.menuRowTitle(includeDependabot: false), "Acorn-Compute  — | 5 branches")
    }

    func testStatusGlyphsAndMenuTitle() {
        let changesRequested = PullRequest(
            repoID: "octocat/one",
            number: 7,
            title: "fix things",
            url: URL(string: "https://github.com/octocat/one/pull/7")!,
            isDraft: false,
            authorLogin: "octocat",
            reviewDecision: .changesRequested
        )
        XCTAssertEqual(changesRequested.statusGlyphs, "±")
        XCTAssertEqual(changesRequested.statusSummary, "Changes requested")
        XCTAssertEqual(changesRequested.menuTitle(markDependabot: true), "       #7 ±  fix things")

        let clean = PullRequest.fixture(number: 8)
        XCTAssertEqual(clean.statusGlyphs, "")
        XCTAssertNil(clean.statusSummary)
        XCTAssertEqual(clean.menuTitle(markDependabot: true), "       #8  example")

        let approved = PullRequest(
            repoID: "octocat/one",
            number: 9,
            title: "ship it",
            url: URL(string: "https://github.com/octocat/one/pull/9")!,
            isDraft: false,
            authorLogin: "octocat",
            reviewDecision: .approved
        )
        XCTAssertEqual(approved.statusGlyphs, "✓")
    }

    func testHeaderSummaryTotals() {
        let one = TrackedRepo(owner: "octocat", name: "one")
        let two = TrackedRepo(owner: "octocat", name: "two")
        let snapshot = DashboardSnapshot(repos: [
            RepoSnapshot(
                repo: one,
                pullRequests: [.fixture(repoID: one.id, number: 1)],
                branchCount: 30,
                worktreeCount: 4
            ),
            RepoSnapshot(
                repo: two,
                pullRequests: [.fixture(repoID: two.id, number: 2)],
                branchCount: 12
            ),
        ])
        XCTAssertEqual(
            snapshot.headerSummary(includeDependabot: false),
            "2 open PRs | 42 branches | 4 worktrees"
        )

        let bare = DashboardSnapshot(repos: [RepoSnapshot(repo: one)])
        XCTAssertEqual(bare.headerSummary(includeDependabot: false), "No open PRs")
    }

    func testEmptyTitle() {
        XCTAssertEqual(DashboardSnapshot.empty.menuBarTitle(includeDependabot: false), "PRBar")
    }
}
