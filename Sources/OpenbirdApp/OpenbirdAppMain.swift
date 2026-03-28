import SwiftUI

@main
struct OpenbirdAppMain: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Openbird") {
            RootView(model: model)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }
            model.handleAppDidBecomeActive()
        }
    }
}
