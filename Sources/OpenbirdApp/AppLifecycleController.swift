import AppKit

@MainActor
final class AppLifecycleController: NSObject, NSApplicationDelegate {
    private var openMainWindow: () -> Void = {}
    private var prepareForTermination: () async -> Void = {}
    private var allowsFullTermination = false
    private var isHandlingTermination = false

    func configure(
        openMainWindow: @escaping () -> Void,
        prepareForTermination: @escaping () async -> Void
    ) {
        self.openMainWindow = openMainWindow
        self.prepareForTermination = prepareForTermination
    }

    func openApp() {
        openMainWindow()
    }

    func closeAllWindows() {
        for window in NSApp.windows where window.styleMask.contains(.closable) {
            window.performClose(nil)
        }
    }

    func quitCompletely() {
        allowsFullTermination = true
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard allowsFullTermination else {
            closeAllWindows()
            return .terminateCancel
        }

        guard isHandlingTermination == false else {
            return .terminateLater
        }

        isHandlingTermination = true
        Task { [weak self] in
            guard let self else { return }
            await prepareForTermination()
            await MainActor.run {
                isHandlingTermination = false
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard flag == false else {
            return false
        }

        openApp()
        return true
    }
}
