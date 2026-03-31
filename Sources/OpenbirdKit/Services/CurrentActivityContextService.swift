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

        var snapshot = snapshotter.snapshotFrontmostWindow(for: application)
            ?? WindowSnapshot(
                bundleId: application.bundleID,
                appName: application.appName,
                windowTitle: application.appName,
                url: nil,
                visibleText: "",
                source: "workspace"
            )

        if snapshot.url == nil {
            snapshot.url = browserURLResolver.currentURL(
                for: snapshot.bundleId,
                windowTitle: snapshot.windowTitle
            )
        }

        return CurrentActivityContext(
            appName: snapshot.appName,
            bundleID: snapshot.bundleId,
            domain: normalizedDomain(from: snapshot.url)
        )
    }

}
