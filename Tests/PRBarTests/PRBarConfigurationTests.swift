import XCTest
@testable import PRBarCore

final class PRBarConfigurationTests: XCTestCase {
    func testAddMoveRemove() throws {
        var config = PRBarConfiguration()
        try config.addRepo(TrackedRepo.parse("octocat/one"))
        try config.addRepo(TrackedRepo.parse("octocat/two"))
        XCTAssertThrowsError(try config.addRepo(TrackedRepo.parse("octocat/one")))
        config.moveRepos(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(config.repos.map(\.name), ["two", "one"])
        config.removeRepos(at: IndexSet(integer: 0))
        XCTAssertEqual(config.repos.map(\.name), ["one"])
    }

    func testRenameAndAbbreviation() throws {
        var config = PRBarConfiguration()
        try config.addRepo(try TrackedRepo.parse("octocat/Hello-World"))
        config.updateRepo(id: "octocat/hello-world", shortLabel: "hh", displayName: "Hello")
        XCTAssertEqual(config.repos[0].shortLabel, "HH")
        XCTAssertEqual(config.repos[0].displayName, "Hello")
        XCTAssertEqual(config.repos[0].fullName, "octocat/Hello-World")
    }

    func testRoundTripFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("config.json")
        var config = PRBarConfiguration(includeDependabotInCounts: true, refreshInterval: 90)
        try config.addRepo(TrackedRepo.parse("octocat/Hello-World"))
        try PRBarConfigFile.save(config, to: url)
        let loaded = try PRBarConfigFile.load(from: url)
        XCTAssertEqual(loaded.includeDependabotInCounts, true)
        XCTAssertEqual(loaded.refreshInterval, 90)
        XCTAssertEqual(loaded.repos.map(\.fullName), ["octocat/Hello-World"])
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testRefreshIntervalPresets() {
        XCTAssertEqual(RefreshIntervalPreset.twoMinutes.seconds, 120)
        XCTAssertEqual(RefreshIntervalPreset.matching(120), .twoMinutes)
        XCTAssertEqual(RefreshIntervalPreset.matching(0), .manual)
        XCTAssertNil(RefreshIntervalPreset.matching(90))
        XCTAssertEqual(RefreshIntervalPreset.manual.menuTitle, "Manual only")
    }

    func testMissingFileIsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).json")
        let loaded = try PRBarConfigFile.load(from: url)
        XCTAssertEqual(loaded, .empty)
    }
}
