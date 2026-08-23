import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = TaBrandAssets.appIcon {
            NSApplication.shared.applicationIconImage = icon
        }
        if let appModel = AppModel.current {
            menuBarController = MenuBarController(appModel: appModel)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard let appModel = AppModel.current, !appModel.isCapturing else {
            return false
        }
        appModel.showWelcome()
        return true
    }
}
