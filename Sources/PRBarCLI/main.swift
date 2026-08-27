import Foundation
import PRBarCore

@main
enum PRBarCLI {
    static func main() async {
        let includeDependabot = CommandLine.arguments.contains("--include-dependabot")
        let asJSON = CommandLine.arguments.contains("--json")
        let help = CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h")

        if help {
            print(
                """
                prbar-cli — menu-bar open-PR counts for GitHub repos you choose

                Usage:
                  prbar-cli [--include-dependabot] [--json]

                Reads GitHub via the local `gh` CLI (must be logged in).
                Repos come from ~/.config/prbar/config.json (Repos… in the app).
                Dependabot PRs are omitted from counts unless --include-dependabot is passed.
                """
            )
            return
        }

        do {
            let configuration = try PRBarConfigFile.load()
            if configuration.repos.isEmpty {
                FileHandle.standardError.write(
                    Data("No repos configured. Add some in PRBar → Repos… or edit ~/.config/prbar/config.json\n".utf8)
                )
                exit(1)
            }

            let client = try GitHubClient()
            let snapshot = await client.fetchDashboard(repos: configuration.repos)
            let include = includeDependabot || configuration.includeDependabotInCounts
            if snapshot.hasErrors, snapshot.repos.allSatisfy({ $0.error != nil }) {
                FileHandle.standardError.write(Data("Failed to load pull requests.\n".utf8))
                for repo in snapshot.repos {
                    if let error = repo.error {
                        FileHandle.standardError.write(Data("\(repo.repo.fullName): \(error)\n".utf8))
                    }
                }
                exit(1)
            }

            if asJSON {
                print(jsonOutput(snapshot: snapshot, includeDependabot: include))
            } else {
                print(textOutput(snapshot: snapshot, includeDependabot: include))
            }
            if snapshot.hasErrors {
                exit(1)
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func textOutput(snapshot: DashboardSnapshot, includeDependabot: Bool) -> String {
        var lines: [String] = []
        let nameWidth = snapshot.repos.map(\.repo.displayName.count).max() ?? 12
        for repo in snapshot.repos {
            let name = repo.repo.displayName.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            if let count = repo.visibleCount(includeDependabot: includeDependabot) {
                lines.append("\(name)  \(count)")
            } else {
                lines.append("\(name)  error: \(repo.error ?? "unknown")")
            }
        }
        lines.append(String(repeating: "─", count: nameWidth + 8))
        lines.append(
            "total".padding(toLength: nameWidth, withPad: " ", startingAt: 0)
                + "  \(snapshot.totalVisible(includeDependabot: includeDependabot))"
        )
        if !includeDependabot, snapshot.hiddenDependabotCount > 0 {
            lines.append("(\(snapshot.hiddenDependabotCount) Dependabot PRs not counted; pass --include-dependabot)")
        }
        return lines.joined(separator: "\n")
    }

    private static func jsonOutput(snapshot: DashboardSnapshot, includeDependabot: Bool) -> String {
        struct Payload: Encodable {
            struct Repo: Encodable {
                var repo: String
                var shortLabel: String
                var count: Int?
                var dependabotCount: Int
                var error: String?
            }

            var includeDependabot: Bool
            var total: Int
            var hiddenDependabot: Int
            var repos: [Repo]
        }

        let payload = Payload(
            includeDependabot: includeDependabot,
            total: snapshot.totalVisible(includeDependabot: includeDependabot),
            hiddenDependabot: snapshot.hiddenDependabotCount,
            repos: snapshot.repos.map { repo in
                Payload.Repo(
                    repo: repo.repo.fullName,
                    shortLabel: repo.repo.shortLabel,
                    count: repo.visibleCount(includeDependabot: includeDependabot),
                    dependabotCount: repo.hiddenDependabotCount,
                    error: repo.error
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try! encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
