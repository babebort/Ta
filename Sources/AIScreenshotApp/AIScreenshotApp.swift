import SwiftUI
import AIScreenshotCore

@main
struct AIScreenshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel: AppModel

    init() {
        let model = AppModel()
        _appModel = StateObject(wrappedValue: model)
        model.start()
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .accentColor(TaPalette.cinnabar)
                .tint(TaPalette.cinnabar)
        }
    }
}
