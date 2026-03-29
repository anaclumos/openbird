import Foundation
import Testing
@testable import OpenbirdKit

struct AccessibilitySnapshotterTests {
    @Test func usesMinimalSnapshotForCurrentProcess() async {
        let snapshotter = AccessibilitySnapshotter()
        let application = FrontmostApplicationContext(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            bundleID: "com.computelesscomputer.openbird",
            appName: "Openbird"
        )

        let snapshot = await MainActor.run {
            snapshotter.snapshotFrontmostWindow(for: application)
        }

        #expect(snapshot != nil)
        #expect(snapshot?.bundleId == "com.computelesscomputer.openbird")
        #expect(snapshot?.appName == "Openbird")
        #expect(snapshot?.windowTitle == "Openbird")
        #expect(snapshot?.url == nil)
        #expect(snapshot?.visibleText == "")
        #expect(snapshot?.source == "workspace")
    }
}
