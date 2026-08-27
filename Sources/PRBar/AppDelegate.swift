import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: PRStore?
    private var settings: SettingsStore?
    private var statusItemController: StatusItemController?
    private var reposWindow: ReposWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore()
        let store = PRStore(settings: settings)
        self.settings = settings
        self.store = store
        let reposWindow = ReposWindowController(settings: settings)
        self.reposWindow = reposWindow
        statusItemController = StatusItemController(
            store: store,
            settings: settings,
            onEditRepos: { reposWindow.show() }
        )
        store.start()
        if settings.repos.isEmpty {
            reposWindow.show()
        }
    }
}
