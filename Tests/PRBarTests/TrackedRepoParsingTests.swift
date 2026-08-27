import XCTest
@testable import PRBarCore

final class TrackedRepoParsingTests: XCTestCase {
    func testParsesOwnerName() throws {
        let repo = try TrackedRepo.parse("octocat/Hello-World")
        XCTAssertEqual(repo.owner, "octocat")
        XCTAssertEqual(repo.name, "Hello-World")
        XCTAssertEqual(repo.shortLabel, "HW")
        XCTAssertEqual(repo.displayName, "Hello-World")
    }

    func testParsesGitHubHTTPSURL() throws {
        let repo = try TrackedRepo.parse("https://github.com/octocat/Spoon-Knife/pulls")
        XCTAssertEqual(repo.fullName, "octocat/Spoon-Knife")
        XCTAssertEqual(repo.shortLabel, "SK")
    }

    func testParsesSSHURL() throws {
        let repo = try TrackedRepo.parse("git@github.com:octocat/Hello-World.git")
        XCTAssertEqual(repo.fullName, "octocat/Hello-World")
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try TrackedRepo.parse(""))
        XCTAssertThrowsError(try TrackedRepo.parse("just-a-name"))
        XCTAssertThrowsError(try TrackedRepo.parse("https://gitlab.com/octocat/Hello-World"))
    }

    func testSuggestedLabelForSingleToken() throws {
        let repo = try TrackedRepo.parse("apple/swift")
        XCTAssertEqual(repo.shortLabel, "SW")
    }

    func testCustomNameAndTwoLetterAbbreviation() throws {
        let repo = try TrackedRepo.parse(
            "octocat/Hello-World",
            shortLabel: "ok",
            displayName: "Hello"
        )
        XCTAssertEqual(repo.shortLabel, "OK")
        XCTAssertEqual(repo.displayName, "Hello")
        XCTAssertEqual(repo.fullName, "octocat/Hello-World")
    }

    func testAbbreviationKeepsTwoLetters() {
        XCTAssertEqual(TrackedRepo.normalizeShortLabel("firehose", name: "firehose"), "FI")
        XCTAssertEqual(TrackedRepo.normalizeShortLabel("a", name: "firehose"), "A")
        XCTAssertEqual(TrackedRepo.normalizeShortLabel("  acorn  ", name: "ignored"), "AC")
        XCTAssertEqual(TrackedRepo.normalizeShortLabel("o1", name: "one"), "O1")
    }
}
