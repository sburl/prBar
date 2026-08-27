import AppKit
import Observation
import PRBarCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: PRStore
    private let settings: SettingsStore
    private let statusItem: NSStatusItem
    private var menu: NSMenu
    private let listedPRLimit = 40
    private let onEditRepos: () -> Void

    init(store: PRStore, settings: SettingsStore, onEditRepos: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.onEditRepos = onEditRepos
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        super.init()

        menu.delegate = self
        statusItem.menu = menu
        if let button = statusItem.button {
            button.image = nil
            button.imagePosition = .noImage
            button.setAccessibilityTitle("PRBar")
        }
        render()
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = store.snapshot
            _ = store.isRefreshing
            _ = store.lastError
            _ = settings.includeDependabot
            _ = settings.repos
            _ = settings.refreshInterval
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.render()
                self?.observe()
            }
        }
    }

    private func render() {
        updateStatusButton()
        rebuildMenu()
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let include = settings.includeDependabot
        let title = store.snapshot.fetchedAt == nil && store.isRefreshing
            ? "PRBar"
            : store.snapshot.menuBarTitle(includeDependabot: include)
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize(for: .small),
            weight: .medium
        )
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .kern: -0.4,
            ]
        )
        button.toolTip = store.snapshot.tooltip(includeDependabot: include)
        button.setAccessibilityTitle(
            "PRBar \(store.snapshot.tooltip(includeDependabot: include).replacingOccurrences(of: "\n", with: ", "))"
        )
        button.appearsDisabled = store.lastError != nil && store.snapshot.fetchedAt == nil
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let include = settings.includeDependabot
        let snapshot = store.snapshot

        let header = NSMenuItem(
            title: headerTitle(snapshot: snapshot, includeDependabot: include),
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        if let fetchedAt = snapshot.fetchedAt, !snapshot.repos.isEmpty {
            let updated = NSMenuItem(
                title: "Updated \(Self.relativeDateFormatter.localizedString(for: fetchedAt, relativeTo: Date()))",
                action: nil,
                keyEquivalent: ""
            )
            updated.isEnabled = false
            menu.addItem(updated)
        }

        menu.addItem(.separator())

        if snapshot.repos.isEmpty {
            let empty = NSMenuItem(
                title: "No repos yet",
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for repo in snapshot.repos {
                menu.addItem(repoMenuItem(repo, includeDependabot: include))
            }
        }

        menu.addItem(.separator())

        let dependabot = NSMenuItem(
            title: "Count Dependabot PRs",
            action: #selector(toggleDependabot(_:)),
            keyEquivalent: ""
        )
        dependabot.target = self
        dependabot.state = include ? .on : .off
        dependabot.toolTip = "Menu-bar counts only. Dependabot PRs always appear at the bottom of each repo list."
        menu.addItem(dependabot)

        let hidden = snapshot.hiddenDependabotCount
        if !include, hidden > 0 {
            let note = NSMenuItem(
                title: "\(hidden) Dependabot PR\(hidden == 1 ? "" : "s") not counted",
                action: nil,
                keyEquivalent: ""
            )
            note.isEnabled = false
            menu.addItem(note)
        }

        let reposItem = NSMenuItem(
            title: "Repos…",
            action: #selector(editRepos(_:)),
            keyEquivalent: ","
        )
        reposItem.target = self
        menu.addItem(reposItem)

        let refreshEvery = NSMenuItem(title: "Refresh Every", action: nil, keyEquivalent: "")
        refreshEvery.submenu = refreshIntervalMenu()
        menu.addItem(refreshEvery)

        let refresh = NSMenuItem(
            title: store.isRefreshing ? "Refreshing…" : "Refresh Now",
            action: #selector(refreshNow(_:)),
            keyEquivalent: "r"
        )
        refresh.target = self
        refresh.isEnabled = !store.isRefreshing
        menu.addItem(refresh)

        menu.addItem(.separator())

        if LaunchAtLogin.isBundledApp {
            let login = NSMenuItem(
                title: "Open at Login",
                action: #selector(toggleLaunchAtLogin(_:)),
                keyEquivalent: ""
            )
            login.target = self
            login.state = LaunchAtLogin.isEnabled ? .on : .off
            menu.addItem(login)
        }

        let quit = NSMenuItem(
            title: "Quit PRBar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
    }

    private func headerTitle(snapshot: DashboardSnapshot, includeDependabot: Bool) -> String {
        if snapshot.repos.isEmpty {
            return store.lastError ?? "Add repos to get started"
        }
        if snapshot.fetchedAt == nil {
            return store.lastError ?? "Fetching open PRs…"
        }
        let total = snapshot.totalVisible(includeDependabot: includeDependabot)
        return "\(total) open PR\(total == 1 ? "" : "s")"
    }

    private func repoMenuItem(_ repo: RepoSnapshot, includeDependabot: Bool) -> NSMenuItem {
        let countLabel = repo.visibleCount(includeDependabot: includeDependabot).map(String.init) ?? "—"
        let title = "\(repo.repo.displayName) (\(countLabel))"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = repoSubmenu(repo)
        if repo.error != nil {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: NSColor.systemRed]
            )
        }
        return item
    }

    private func repoSubmenu(_ repo: RepoSnapshot) -> NSMenu {
        let submenu = NSMenu(title: repo.repo.displayName)

        let openAll = NSMenuItem(
            title: "Open pull requests on GitHub",
            action: #selector(openRepo(_:)),
            keyEquivalent: ""
        )
        openAll.target = self
        openAll.representedObject = repo.repo.pullsURL
        submenu.addItem(openAll)

        if let error = repo.error {
            submenu.addItem(.separator())
            let errorItem = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            submenu.addItem(errorItem)
        }

        let regular = repo.regularPullRequests
        let dependabot = repo.dependabotPullRequests

        if !regular.isEmpty {
            submenu.addItem(.separator())
            appendPRItems(regular, to: submenu, repo: repo.repo)
        }

        if !dependabot.isEmpty {
            submenu.addItem(.separator())
            let header = NSMenuItem(title: "Dependabot", action: nil, keyEquivalent: "")
            header.isEnabled = false
            submenu.addItem(header)
            appendPRItems(dependabot, to: submenu, repo: repo.repo, markDependabot: false)
        }

        if regular.isEmpty, dependabot.isEmpty, repo.error == nil {
            submenu.addItem(.separator())
            let empty = NSMenuItem(title: "No open pull requests", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }

        return submenu
    }

    private func appendPRItems(
        _ pulls: [PullRequest],
        to menu: NSMenu,
        repo: TrackedRepo,
        markDependabot: Bool = true
    ) {
        let listed = pulls.prefix(listedPRLimit)
        for pr in listed {
            menu.addItem(prMenuItem(pr, markDependabot: markDependabot))
        }
        let remaining = pulls.count - listed.count
        if remaining > 0 {
            let more = NSMenuItem(
                title: "and \(remaining) more…",
                action: #selector(openRepo(_:)),
                keyEquivalent: ""
            )
            more.target = self
            more.representedObject = repo.pullsURL
            menu.addItem(more)
        }
    }

    private func prMenuItem(_ pr: PullRequest, markDependabot: Bool) -> NSMenuItem {
        let item = NSMenuItem(
            title: pr.menuTitle(markDependabot: markDependabot),
            action: #selector(openURL(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = pr.url
        item.toolTip = "Opened \(pr.openedDateLabel)\n\(pr.authorLogin)\n\(pr.title)"
        return item
    }

    private func refreshIntervalMenu() -> NSMenu {
        let submenu = NSMenu(title: "Refresh Every")
        let selected = RefreshIntervalPreset.matching(settings.refreshInterval)
        for preset in RefreshIntervalPreset.allCases {
            let item = NSMenuItem(
                title: preset.menuTitle,
                action: #selector(chooseRefreshInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.rawValue
            item.state = selected == preset ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func chooseRefreshInterval(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = RefreshIntervalPreset(rawValue: raw)
        else { return }
        settings.refreshInterval = preset.seconds
    }

    @objc private func toggleDependabot(_ sender: NSMenuItem) {
        settings.includeDependabot.toggle()
    }

    @objc private func editRepos(_ sender: NSMenuItem) {
        onEditRepos()
    }

    @objc private func refreshNow(_ sender: NSMenuItem) {
        Task { await store.refresh() }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
            render()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update Open at Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func openRepo(_ sender: NSMenuItem) {
        openURL(sender)
    }

    @objc private func openURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
