import AppKit
import OSLog
import OpenbirdKit

@MainActor
final class AppLifecycleController: NSObject, NSApplicationDelegate {
    private let logger = OpenbirdLog.lifecycle
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
        logger.notice("Opening main window")
        openMainWindow()
    }

    func closeAllWindows() {
        logger.notice("Closing all windows")
        for window in NSApp.windows where window.styleMask.contains(.closable) {
            window.performClose(nil)
        }
    }

    func quitCompletely() {
        logger.notice("Quitting Openbird completely")
        allowsFullTermination = true
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard allowsFullTermination else {
            logger.notice("Intercepted termination request and closed windows instead")
            closeAllWindows()
            return .terminateCancel
        }

        guard isHandlingTermination == false else {
            logger.debug("Termination already in progress")
            return .terminateLater
        }

        isHandlingTermination = true
        logger.notice("Preparing for application termination")
        Task { [weak self] in
            guard let self else { return }
            await prepareForTermination()
            await MainActor.run {
                isHandlingTermination = false
                logger.notice("Application termination cleanup finished")
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard flag == false else {
            return false
        }

        logger.notice("Reopening application without visible windows")
        openApp()
        return true
    }
}
