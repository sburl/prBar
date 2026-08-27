import Foundation
import Observation
import PRBarCore

@MainActor
@Observable
final class PRStore {
    private(set) var snapshot: DashboardSnapshot
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    let settings: SettingsStore
    private var client: GitHubClient?
    private var timer: Timer?
    private var lastFetchedIDs: [String] = []

    init(settings: SettingsStore) {
        self.settings = settings
        snapshot = DashboardSnapshot(repos: settings.repos.map { RepoSnapshot(repo: $0) })
        do {
            client = try GitHubClient()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func start() {
        observeSettings()
        Task { await refresh() }
        restartTimer()
    }

    func restartTimer() {
        timer?.invalidate()
        timer = nil
        let interval = settings.refreshInterval
        guard interval > 0 else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        timer.tolerance = min(15, interval / 4)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() async {
        if client == nil {
            do {
                client = try GitHubClient()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                return
            }
        }

        guard let client, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let ids = settings.repos.map(\.id)
        if settings.repos.isEmpty {
            lastFetchedIDs = []
            snapshot = DashboardSnapshot(repos: [], fetchedAt: Date())
            lastError = nil
            return
        }

        let next = await client.fetchDashboard(repos: settings.repos)
        lastFetchedIDs = ids
        snapshot = next
        lastError = next.hasErrors
            ? next.repos.compactMap(\.error).first
            : nil
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.repos
            _ = settings.refreshInterval
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.restartTimer()
                self?.syncReposWithoutFetch()
                if self?.needsRefetch == true {
                    await self?.refresh()
                }
                self?.observeSettings()
            }
        }
    }

    private var needsRefetch: Bool {
        settings.repos.map(\.id) != lastFetchedIDs
    }

    private func syncReposWithoutFetch() {
        let byID = Dictionary(uniqueKeysWithValues: snapshot.repos.map { ($0.repo.id, $0) })
        snapshot.repos = settings.repos.map { repo in
            var existing = byID[repo.id] ?? RepoSnapshot(repo: repo)
            existing.repo = repo
            return existing
        }
        if snapshot.fetchedAt == nil, !settings.repos.isEmpty {
            snapshot.fetchedAt = Date()
        }
    }
}
