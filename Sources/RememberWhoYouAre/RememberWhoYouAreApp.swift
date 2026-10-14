import SwiftUI
import Sparkle

@main
struct RememberWhoYouAreApp: App {
    @StateObject private var model = AppModel()
    private let updaterController: SPUStandardUpdaterController
    private let updates: UpdateChecker

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        updates = UpdateChecker(updater: controller.updater) {
            NSApp.activate(ignoringOtherApps: true)
            controller.checkForUpdates(nil)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model, updates: updates)
        } label: {
            HStack(spacing: 4) {
                Text(model.menuBarEmoji)
                if let title = model.menuBarTitle { Text(title) }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(model: model, updates: updates)
        }
        .windowResizability(.contentSize)
    }
}
