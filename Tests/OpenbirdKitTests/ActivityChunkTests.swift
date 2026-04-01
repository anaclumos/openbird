import Foundation
import Testing
@testable import OpenbirdKit

struct ActivityChunkTests {
    @Test func activityChunksBackfillFromGroupedEvidence() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let start = Date(timeIntervalSince1970: 1_720_000_000)

        let events = [
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(30),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice Profile 9:31 PM See you there Enter a message Search Voice Call Video Call Menu",
                source: "accessibility",
                contentHash: "chat-a",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(31),
                endedAt: start.addingTimeInterval(60),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice 9:39 PM See you there tomorrow Enter a message Search Menu",
                source: "accessibility",
                contentHash: "chat-b",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(90),
                endedAt: start.addingTimeInterval(180),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice 10:23 PM Shared the pickup plan",
                source: "accessibility",
                contentHash: "chat-c",
                isExcluded: false
            ),
        ]

        for event in events {
            try await store.saveActivityEvent(event)
        }

        let chunks = try await store.activityChunks(for: start)

        #expect(chunks.count == 1)
        #expect(chunks.first?.title == "Alice")
        #expect(chunks.first?.sourceEventCount == 3)
        #expect(chunks.first?.excerpt.contains("Enter a message") == false)
        #expect(chunks.first?.excerpt.contains("Voice Call") == false)
    }

    @Test func activityChunksRefreshWhenNewLogsArrive() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let start = Date(timeIntervalSince1970: 1_720_000_000)

        try await store.saveActivityEvent(
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(30),
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "ComputelessComputer/openbird",
                url: "https://github.com/ComputelessComputer/openbird",
                visibleText: "Reviewed the current activity pipeline.",
                source: "accessibility",
                contentHash: "chunk-a",
                isExcluded: false
            )
        )

        let initialChunks = try await store.activityChunks(for: start)
        #expect(initialChunks.count == 1)
        #expect(initialChunks.first?.sourceEventCount == 1)

        try await store.saveActivityEvent(
            ActivityEvent(
                startedAt: start.addingTimeInterval(31),
                endedAt: start.addingTimeInterval(80),
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "ComputelessComputer/openbird",
                url: "https://github.com/ComputelessComputer/openbird",
                visibleText: "Reviewed the chunk storage follow-up.",
                source: "accessibility",
                contentHash: "chunk-b",
                isExcluded: false
            )
        )

        let refreshedChunks = try await store.activityChunks(for: start)
        #expect(refreshedChunks.count == 1)
        #expect(refreshedChunks.first?.sourceEventCount == 2)
    }

    @Test func deleteAllEventsClearsPersistedActivityChunks() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let start = Date(timeIntervalSince1970: 1_720_000_000)

        try await store.saveActivityEvent(
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(60),
                bundleId: "com.microsoft.VSCode",
                appName: "VS Code",
                windowTitle: "openbird",
                url: nil,
                visibleText: "Implemented persistent activity chunks.",
                source: "accessibility",
                contentHash: "chunk-delete",
                isExcluded: false
            )
        )

        #expect(try await store.activityChunks(for: start).count == 1)

        try await store.deleteAllEvents()

        #expect(try await store.activityChunks(for: start).isEmpty)
    }
}
