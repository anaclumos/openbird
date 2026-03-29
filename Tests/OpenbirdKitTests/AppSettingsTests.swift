import Foundation
import Testing
@testable import OpenbirdKit

struct AppSettingsTests {
    @Test func temporaryPauseExpiresAtDeadline() {
        var settings = AppSettings()
        let now = Date(timeIntervalSince1970: 1_000)
        let pauseUntil = now.addingTimeInterval(300)

        settings.pauseCapture(until: pauseUntil)

        #expect(settings.isCapturePaused(now: now))
        #expect(settings.isCapturePaused(now: pauseUntil.addingTimeInterval(-1)))
        #expect(settings.isCapturePaused(now: pauseUntil) == false)
    }

    @Test func currentSessionPauseOnlyAppliesToMatchingSession() {
        var settings = AppSettings()

        settings.pauseCaptureForCurrentSession("session-a")

        #expect(settings.isCapturePaused(sessionID: "session-a"))
        #expect(settings.isCapturePaused(sessionID: "session-b") == false)
        let didNormalize = settings.normalizeCapturePause(sessionID: "session-b")
        #expect(didNormalize)
        #expect(settings.capturePauseSessionID == nil)
    }
}
