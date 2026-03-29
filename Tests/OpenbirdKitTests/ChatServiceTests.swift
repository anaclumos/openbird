import Foundation
import Testing
@testable import OpenbirdKit

@Suite(.serialized)
struct ChatServiceTests {
    @Test func createThreadStartsFreshConversationForDay() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let service = ChatService(store: store, retrievalService: RetrievalService(store: store))
        let day = "2026-03-29"

        let firstThread = try await service.ensureThread(for: day)
        try await Task.sleep(for: .milliseconds(10))
        let newThread = try await service.createThread(for: day)
        let restoredThread = try await service.ensureThread(for: day)
        let threads = try await store.loadThreads()

        #expect(firstThread.id != newThread.id)
        #expect(restoredThread.id == newThread.id)
        #expect(threads.count == 2)
        #expect(threads.first?.id == newThread.id)
    }
}
