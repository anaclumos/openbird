import AppKit
import Foundation

public struct CurrentActivityContext: Equatable, Sendable {
    public let appName: String
    public let bundleID: String
    public let domain: String?

    public init(appName: String, bundleID: String, domain: String?) {
        self.appName = appName
        self.bundleID = bundleID
        self.domain = domain
    }
}

public struct CurrentActivityContextService: Sendable {
    private let snapshotter = AccessibilitySnapshotter()
    private let browserURLResolver = BrowserURLResolver()

    public init() {}

    @MainActor
    public func currentContext() -> CurrentActivityContext? {
        guard let application = FrontmostApplicationContext.current() else {
            return nil
        }

        let snapshot = snapshotter.snapshotFrontmostWindow(for: application)
        let url = snapshot?.url ?? browserURLResolver.currentURL(
            for: application.bundleID,
            windowTitle: snapshot?.windowTitle ?? application.appName
        )

        return CurrentActivityContext(
            appName: application.appName,
            bundleID: application.bundleID,
            domain: normalizedDomain(from: url)
        )
    }

}
