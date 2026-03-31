import Foundation

public struct AppSettings: Codable, Hashable, Sendable {
    public var capturePaused: Bool
    public var capturePauseUntil: Date?
    public var capturePauseSessionID: String?
    public var retentionDays: Int
    public var activeProviderID: String?
    public var selectedProviderID: String?
    public var lastCollectorHeartbeat: Date?
    public var collectorStatus: String
    public var collectorOwnerID: String?
    public var collectorOwnerName: String?

    public init(
        capturePaused: Bool = false,
        capturePauseUntil: Date? = nil,
        capturePauseSessionID: String? = nil,
        retentionDays: Int = 14,
        activeProviderID: String? = nil,
        selectedProviderID: String? = nil,
        lastCollectorHeartbeat: Date? = nil,
        collectorStatus: String = "stopped",
        collectorOwnerID: String? = nil,
        collectorOwnerName: String? = nil
    ) {
        self.capturePaused = capturePaused
        self.capturePauseUntil = capturePauseUntil
        self.capturePauseSessionID = capturePauseSessionID
        self.retentionDays = retentionDays
        self.activeProviderID = activeProviderID
        self.selectedProviderID = selectedProviderID
        self.lastCollectorHeartbeat = lastCollectorHeartbeat
        self.collectorStatus = collectorStatus
        self.collectorOwnerID = collectorOwnerID
        self.collectorOwnerName = collectorOwnerName
    }

    public func isCapturePaused(now: Date = Date(), sessionID: String? = nil) -> Bool {
        if capturePaused {
            return true
        }
        if let capturePauseUntil, capturePauseUntil > now {
            return true
        }
        if let sessionID, capturePauseSessionID == sessionID {
            return true
        }
        return false
    }

    public func activeCapturePauseUntil(now: Date = Date()) -> Date? {
        guard let capturePauseUntil, capturePauseUntil > now else {
            return nil
        }

        return capturePauseUntil
    }

    public func isCapturePausedForCurrentSession(_ sessionID: String) -> Bool {
        capturePauseSessionID == sessionID
    }

    public mutating func setManualCapturePaused(_ paused: Bool) {
        capturePaused = paused
        if paused {
            capturePauseUntil = nil
            capturePauseSessionID = nil
            return
        }

        resumeCapture()
    }

    public mutating func pauseCapture(until date: Date) {
        capturePaused = false
        capturePauseUntil = date
        capturePauseSessionID = nil
    }

    public mutating func pauseCaptureForCurrentSession(_ sessionID: String) {
        capturePaused = false
        capturePauseUntil = nil
        capturePauseSessionID = sessionID
    }

    @discardableResult
    public mutating func normalizeCapturePause(now: Date = Date(), sessionID: String? = nil) -> Bool {
        var changed = false

        if let capturePauseUntil, capturePauseUntil <= now {
            self.capturePauseUntil = nil
            changed = true
        }

        if let sessionID,
           let capturePauseSessionID,
           capturePauseSessionID != sessionID {
            self.capturePauseSessionID = nil
            changed = true
        }

        return changed
    }

    public mutating func resumeCapture() {
        capturePaused = false
        capturePauseUntil = nil
        capturePauseSessionID = nil
    }
}

public enum DataDeletionScope: String, CaseIterable, Sendable {
    case lastHour
    case lastDay
    case all
}
