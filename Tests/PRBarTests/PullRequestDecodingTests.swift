import XCTest
@testable import PRBarCore

final class PullRequestDecodingTests: XCTestCase {
    func testDecodesGhPrListJSON() throws {
        let json = """
        [
          {
            "author": {"id": "1", "is_bot": false, "login": "octocat", "name": "The Octocat"},
            "isDraft": true,
            "number": 12,
            "title": "add a widget",
            "url": "https://github.com/octocat/Hello-World/pull/12",
            "createdAt": "2026-08-12T15:22:00Z"
          },
          {
            "author": {"is_bot": true, "login": "app/dependabot"},
            "isDraft": false,
            "number": 13,
            "title": "chore(deps): bump uv",
            "url": "https://github.com/octocat/Hello-World/pull/13"
          },
          {
            "isDraft": false,
            "number": 1,
            "title": "ghost",
            "url": "https://github.com/octocat/Hello-World/pull/1"
          }
        ]
        """.data(using: .utf8)!

        let prs = try PullRequest.decodeList(from: json, repoID: "octocat/hello-world")
        XCTAssertEqual(prs.count, 3)
        XCTAssertEqual(prs[0].number, 12)
        XCTAssertTrue(prs[0].isDraft)
        XCTAssertEqual(prs[0].authorLogin, "octocat")
        XCTAssertFalse(prs[0].isDependabot)
        XCTAssertEqual(prs[0].openedDateLabel, "08-12")
        XCTAssertEqual(
            prs[0].menuTitle(markDependabot: true),
            "08-12  #12 [draft]  add a widget"
        )
        XCTAssertTrue(prs[1].isDependabot)
        XCTAssertEqual(prs[2].authorLogin, "")
        XCTAssertEqual(prs[2].openedDateLabel, "     ")
    }
}
