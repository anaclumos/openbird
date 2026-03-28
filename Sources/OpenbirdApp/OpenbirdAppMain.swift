import AppKit
import SwiftUI

private enum OpenbirdSceneID {
    static let main = "main"
}

@main
struct OpenbirdAppMain: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Openbird", id: OpenbirdSceneID.main) {
            RootView(model: model)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }
            model.handleAppDidBecomeActive()
        }
        .commands {
            OpenbirdAppCommands(model: model)
        }
    }
}

private struct OpenbirdAppCommands: Commands {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                model.checkForUpdates()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                model.selection = .settings
                openWindow(id: OpenbirdSceneID.main)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
