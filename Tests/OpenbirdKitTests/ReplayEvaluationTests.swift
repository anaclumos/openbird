import Foundation
import Testing
@testable import OpenbirdKit

@Suite(.serialized)
struct ReplayEvaluationTests {
    @Test func engineeringReplayMaintainsQualityBar() async throws {
        let report = try await evaluate(.engineeringDay)

        #expect(report.retrievalTop3HitRate == 1)
        #expect(report.chatCitationHitRate == 1)
        #expect(report.missingRequiredJournalPhrases.isEmpty)
        #expect(report.presentForbiddenJournalPhrases.isEmpty)
        #expect(report.journalGenerationDuration < 1.5)
        #expect(report.averageChatAnswerDuration < 1.0)
    }

    @Test func messagingReplayMaintainsQualityBar() async throws {
        let report = try await evaluate(.messagingDay)

        #expect(report.retrievalTop3HitRate == 1)
        #expect(report.chatCitationHitRate == 1)
        #expect(report.missingRequiredJournalPhrases.isEmpty)
        #expect(report.presentForbiddenJournalPhrases.isEmpty)
        #expect(report.journalGenerationDuration < 1.5)
        #expect(report.averageChatAnswerDuration < 1.0)
    }

    private func evaluate(_ scenario: DayReplayScenario) async throws -> ScenarioEvaluationReport {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let retrievalService = RetrievalService(store: store)
        let journalGenerator = JournalGenerator(store: store)
        let chatService = ChatService(store: store, retrievalService: retrievalService)
        let day = OpenbirdDateFormatting.dayString(for: scenario.day)
        let dateRange = Calendar.current.dayRange(for: scenario.day)

        for event in scenario.events {
            try await store.saveActivityEvent(event)
        }

        let journalStart = Date()
        let journal = try await journalGenerator.generate(
            request: JournalGenerationRequest(
                date: scenario.day,
                providerID: nil
            )
        )
        let journalGenerationDuration = Date().timeIntervalSince(journalStart)

        var retrievalHitCount = 0
        var chatCitationHitCount = 0
        var totalChatAnswerDuration: TimeInterval = 0

        for question in scenario.questions {
            let retrievalResults = try await retrievalService.search(
                query: question.query,
                range: dateRange,
                appFilters: [],
                topK: 3,
                providerConfig: nil
            )
            if retrievalResults.contains(where: { $0.id == question.expectedEventID }) {
                retrievalHitCount += 1
            }

            let thread = try await chatService.createThread(for: day)
            let chatStart = Date()
            let answer = try await chatService.answer(
                ChatQuery(
                    threadID: thread.id,
                    question: question.query,
                    dateRange: dateRange
                )
            )
            totalChatAnswerDuration += Date().timeIntervalSince(chatStart)

            if answer.citations.contains(where: { $0.eventID == question.expectedEventID }) {
                chatCitationHitCount += 1
            }
        }

        let missingRequiredJournalPhrases = scenario.requiredJournalPhrases.filter {
            journal.markdown.contains($0) == false
        }
        let presentForbiddenJournalPhrases = scenario.forbiddenJournalPhrases.filter {
            journal.markdown.contains($0)
        }

        return ScenarioEvaluationReport(
            retrievalTop3HitRate: Double(retrievalHitCount) / Double(scenario.questions.count),
            chatCitationHitRate: Double(chatCitationHitCount) / Double(scenario.questions.count),
            journalGenerationDuration: journalGenerationDuration,
            averageChatAnswerDuration: totalChatAnswerDuration / Double(scenario.questions.count),
            missingRequiredJournalPhrases: missingRequiredJournalPhrases,
            presentForbiddenJournalPhrases: presentForbiddenJournalPhrases
        )
    }
}

private struct ScenarioEvaluationReport {
    let retrievalTop3HitRate: Double
    let chatCitationHitRate: Double
    let journalGenerationDuration: TimeInterval
    let averageChatAnswerDuration: TimeInterval
    let missingRequiredJournalPhrases: [String]
    let presentForbiddenJournalPhrases: [String]
}

private struct DayReplayScenario {
    struct QuestionExpectation {
        let query: String
        let expectedEventID: String
    }

    let day: Date
    let events: [ActivityEvent]
    let questions: [QuestionExpectation]
    let requiredJournalPhrases: [String]
    let forbiddenJournalPhrases: [String]

    static let engineeringDay: DayReplayScenario = {
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_720_000_000))
        let start = day.addingTimeInterval(9 * 3600)

        return DayReplayScenario(
            day: day,
            events: [
                ActivityEvent(
                    id: "pr-review",
                    startedAt: start,
                    endedAt: start.addingTimeInterval(420),
                    bundleId: "com.apple.Safari",
                    appName: "Safari",
                    windowTitle: "ComputelessComputer/openbird",
                    url: "https://github.com/ComputelessComputer/openbird/pull/42",
                    visibleText: "Reviewed PR fixing grouped activity cache invalidation and collector heartbeat state.",
                    source: "accessibility",
                    contentHash: "pr-review",
                    isExcluded: false
                ),
                ActivityEvent(
                    id: "retrieval-work",
                    startedAt: start.addingTimeInterval(900),
                    endedAt: start.addingTimeInterval(1500),
                    bundleId: "com.microsoft.VSCode",
                    appName: "VS Code",
                    windowTitle: "openbird",
                    url: nil,
                    visibleText: "Implemented chunked retrieval ranking and a local replay evaluation harness.",
                    source: "accessibility",
                    contentHash: "retrieval-work",
                    isExcluded: false
                ),
                ActivityEvent(
                    id: "fts-docs",
                    startedAt: start.addingTimeInterval(2400),
                    endedAt: start.addingTimeInterval(2820),
                    bundleId: "com.apple.Safari",
                    appName: "Safari",
                    windowTitle: "SQLite FTS5",
                    url: "https://sqlite.org/fts5.html",
                    visibleText: "Read FTS5 docs about MATCH queries, tokenizers, and BM25 ranking.",
                    source: "accessibility",
                    contentHash: "fts-docs",
                    isExcluded: false
                ),
            ],
            questions: [
                QuestionExpectation(
                    query: "What PR was I reviewing?",
                    expectedEventID: "pr-review"
                ),
                QuestionExpectation(
                    query: "What retrieval work did I implement?",
                    expectedEventID: "retrieval-work"
                ),
                QuestionExpectation(
                    query: "What docs did I read about MATCH queries?",
                    expectedEventID: "fts-docs"
                ),
            ],
            requiredJournalPhrases: [
                "Looked through your context.",
                "## ComputelessComputer/openbird",
                "## openbird",
                "## SQLite FTS5",
            ],
            forbiddenJournalPhrases: [
                "Enter a message",
                "Voice Call",
                "Page Menu",
            ]
        )
    }()

    static let messagingDay: DayReplayScenario = {
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_720_086_400))
        let start = day.addingTimeInterval(19 * 3600)

        return DayReplayScenario(
            day: day,
            events: [
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
            ],
            questions: [
                QuestionExpectation(
                    query: "What did Alice say about tomorrow?",
                    expectedEventID: "alice-chat-2"
                ),
                QuestionExpectation(
                    query: "What was the pickup plan?",
                    expectedEventID: "alice-chat-3"
                ),
            ],
            requiredJournalPhrases: [
                "Looked through your context.",
                "## Alice",
            ],
            forbiddenJournalPhrases: [
                "Enter a message",
                "Voice Call",
                "Search",
                "Menu",
            ]
        )
    }()
}
