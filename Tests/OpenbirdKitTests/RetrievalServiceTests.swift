import Foundation
import Testing
@testable import OpenbirdKit

struct RetrievalServiceTests {
    @Test func searchChunksFindsChunkLevelContext() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let retrievalService = RetrievalService(store: store)
        let start = Date(timeIntervalSince1970: 1_720_000_000)

        let events = [
            ActivityEvent(
                id: "alice-chat-1",
                startedAt: start,
                endedAt: start.addingTimeInterval(30),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice Profile 9:31 PM See you there Enter a message Search Voice Call Video Call Menu",
                source: "accessibility",
                contentHash: "alice-chat-1",
                isExcluded: false
            ),
            ActivityEvent(
                id: "alice-chat-2",
                startedAt: start.addingTimeInterval(31),
                endedAt: start.addingTimeInterval(60),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice 9:39 PM See you there tomorrow Enter a message Search Menu",
                source: "accessibility",
                contentHash: "alice-chat-2",
                isExcluded: false
            ),
            ActivityEvent(
                id: "alice-chat-3",
                startedAt: start.addingTimeInterval(90),
                endedAt: start.addingTimeInterval(180),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice 10:23 PM Shared the pickup plan",
                source: "accessibility",
                contentHash: "alice-chat-3",
                isExcluded: false
            ),
        ]

        for event in events {
            try await store.saveActivityEvent(event)
        }

        let chunks = try await retrievalService.searchChunks(
            query: "pickup plan",
            range: Calendar.current.dayRange(for: start),
            appFilters: [],
            topK: 3
        )

        #expect(chunks.count == 1)
        #expect(chunks.first?.title == "Alice")
        #expect(chunks.first?.sourceEventIDs == ["alice-chat-1", "alice-chat-2", "alice-chat-3"])
        #expect(chunks.first?.excerpt.contains("pickup plan") == true)
    }
}
