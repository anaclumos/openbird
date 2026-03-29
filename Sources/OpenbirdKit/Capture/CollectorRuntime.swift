import AppKit
import Foundation

public final class CollectorRuntime: NSObject, @unchecked Sendable {
    public static let leaseTimeout: TimeInterval = 20

    private let store: OpenbirdStore
    private let snapshotter = AccessibilitySnapshotter()
    private let browserURLResolver = BrowserURLResolver()
    private let exclusionEngine = ExclusionEngine()
    private let captureGate = CaptureGate()
    private let captureInterval: TimeInterval
    private let ownerID: String
    private let ownerName: String
    private let leaseTimeout: TimeInterval
    private let lifecycleLock = NSLock()
    private var timer: Timer?
    private var currentEvent: ActivityEvent?
    private var currentFingerprint: String?
    private var ownsLease = false
    private var isStopped = true

    public init(
        store: OpenbirdStore,
        captureInterval: TimeInterval = 6,
        ownerID: String = CollectorRuntime.defaultOwnerID(),
        ownerName: String = CollectorRuntime.defaultOwnerName()
    ) {
        self.store = store
        self.captureInterval = captureInterval
        self.ownerID = ownerID
        self.ownerName = ownerName
        self.leaseTimeout = max(Self.leaseTimeout, captureInterval * 3)
        super.init()
    }

    public static func defaultOwnerID() -> String {
        let executablePath = Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.processName
        return "\(ProcessInfo.processInfo.processIdentifier):\(executablePath)"
    }

    public static func defaultOwnerName() -> String {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.bundleURL.path
        }
        return Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.processName
    }

    public func start() {
        lifecycleLock.lock()
        guard isStopped else {
            lifecycleLock.unlock()
            return
        }
        isStopped = false
        lifecycleLock.unlock()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        timer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            self?.scheduleCapture()
        }
        scheduleCapture()
    }

    public func stop() {
        lifecycleLock.lock()
        isStopped = true
        lifecycleLock.unlock()
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        currentEvent = nil
        currentFingerprint = nil
    }

    public func stopAndWait() async {
        stop()
        await captureGate.waitUntilIdle()
        guard ownsLease else {
            return
        }
        try? await store.releaseCollectorLease(ownerID: ownerID)
        ownsLease = false
    }

    @objc private func activeApplicationChanged() {
        scheduleCapture()
    }

    public func captureNow() async {
        guard shouldCapture else {
            return
        }
        await captureGate.runIfIdle {
            guard self.shouldCapture else {
                return
            }
            await performCaptureNow()
        }
    }

    private func performCaptureNow() async {
        do {
            guard shouldCapture else {
                return
            }
            let now = Date()
            let claimedLease = try await store.claimCollectorLease(
                ownerID: ownerID,
                ownerName: ownerName,
                now: now,
                timeout: leaseTimeout
            )
            guard claimedLease else {
                ownsLease = false
                currentEvent = nil
                currentFingerprint = nil
                return
            }
            ownsLease = true

            guard shouldCapture else {
                return
            }

            var settings = try await store.loadSettings()
            if settings.normalizeCapturePause(now: now, sessionID: ownerID) {
                try await store.saveSettings(settings)
            }
            if settings.isCapturePaused(now: now, sessionID: ownerID) {
                currentEvent = nil
                currentFingerprint = nil
                _ = try await store.updateCollectorStatus(ownerID: ownerID, status: "paused", heartbeat: now)
                return
            }

            guard shouldCapture else {
                return
            }

            guard let frontmostApplication = await MainActor.run(body: { FrontmostApplicationContext.current() }) else {
                _ = try await store.updateCollectorStatus(ownerID: ownerID, status: "idle", heartbeat: now)
                return
            }

            guard shouldCapture else {
                return
            }

            guard var snapshot = await MainActor.run(body: {
                snapshotter.snapshotFrontmostWindow(for: frontmostApplication)
            }) else {
                _ = try await store.updateCollectorStatus(ownerID: ownerID, status: "idle", heartbeat: now)
                return
            }

            if snapshot.url == nil {
                snapshot.url = browserURLResolver.currentURL(
                    for: snapshot.bundleId,
                    windowTitle: snapshot.windowTitle
                )
            }

            guard shouldCapture else {
                return
            }

            let exclusions = try await store.loadExclusions()
            let excluded = exclusionEngine.isExcluded(snapshot: snapshot, rules: exclusions)
            if currentFingerprint == snapshot.fingerprint, var currentEvent {
                currentEvent.endedAt = snapshot.capturedAt
                try await store.saveActivityEvent(currentEvent)
                self.currentEvent = currentEvent
            } else {
                let event = snapshot.asEvent(startedAt: snapshot.capturedAt, excluded: excluded)
                try await store.saveActivityEvent(event)
                currentEvent = event
                currentFingerprint = snapshot.fingerprint
            }

            _ = try await store.updateCollectorStatus(ownerID: ownerID, status: "running", heartbeat: snapshot.capturedAt)
        } catch {
            if ownsLease {
                _ = try? await store.updateCollectorStatus(ownerID: ownerID, status: "error", heartbeat: Date())
            }
        }
    }

    private var shouldCapture: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return isStopped == false
    }

    private func scheduleCapture() {
        Task { [weak self] in
            await self?.captureNow()
        }
    }
}

actor CaptureGate {
    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func runIfIdle(_ operation: @Sendable () async -> Void) async {
        guard isRunning == false else { return }
        isRunning = true
        defer {
            isRunning = false
            let pendingWaiters = waiters
            waiters.removeAll()
            pendingWaiters.forEach { $0.resume() }
        }
        await operation()
    }

    func waitUntilIdle() async {
        guard isRunning else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
