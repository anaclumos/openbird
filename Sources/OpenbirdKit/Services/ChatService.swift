import Foundation
import OSLog

public actor ChatService {
    private let store: OpenbirdStore
    private let retrievalService: RetrievalService
    private let logger = OpenbirdLog.chat

    public init(store: OpenbirdStore, retrievalService: RetrievalService) {
        self.store = store
        self.retrievalService = retrievalService
    }

    @discardableResult
    public func createThread(for day: String) async throws -> ChatThread {
        let thread = ChatThread(title: "Chat for \(day)", startDay: day)
        try await store.saveThread(thread)
        logger.notice("Created chat thread for \(day, privacy: .public)")
        return thread
    }

    @discardableResult
    public func ensureThread(for day: String) async throws -> ChatThread {
        let threads = try await store.loadThreads()
        if let existing = threads.first(where: { $0.startDay == day }) {
            logger.debug("Reused existing chat thread for \(day, privacy: .public)")
            return existing
        }
        return try await createThread(for: day)
    }

    public func answer(_ query: ChatQuery) async throws -> ChatMessage {
        logger.notice("Answering chat query with topK=\(query.topK, privacy: .public)")
        let settings = try await store.loadSettings()
        let providerConfigs = try await store.loadProviderConfigs()
        let providerConfig = ProviderSelection.resolve(
            configs: providerConfigs,
            settings: settings
        )
        let relevantEvents = try await retrievalService.search(
            query: query.question,
            range: query.dateRange,
            appFilters: query.appFilters,
            topK: query.topK,
            providerConfig: providerConfig
        )
        logger.notice("Retrieved \(relevantEvents.count, privacy: .public) events for chat answer")

        let citations = relevantEvents.map {
            Citation(
                eventID: $0.id,
                label: "\(OpenbirdDateFormatting.timeString(for: $0.startedAt)) • \($0.appName)"
            )
        }

        let answerText: String
        if let providerConfig {
            do {
                let provider = ProviderFactory.makeProvider(for: providerConfig)
                let day = OpenbirdDateFormatting.dayString(for: query.dateRange.lowerBound)
                let journal = try await store.loadJournal(for: day)
                let evidence = relevantEvents.enumerated().map { index, event in
                    """
                    [\(index + 1)] \(OpenbirdDateFormatting.timeString(for: event.startedAt)) \(event.appName)
                    Title: \(event.windowTitle)
                    URL: \(event.url ?? "n/a")
                    Text: \(event.visibleText)
                    """
                }.joined(separator: "\n\n")
                let prompt = """
                Answer the question using only the supplied evidence.
                If the evidence is weak, say so.
                Keep the answer concise.

                Journal:
                \(journal?.markdown ?? "No journal generated yet.")

                Evidence:
                \(evidence)

                Question:
                \(query.question)
                """
                let response = try await provider.chat(
                    request: ProviderChatRequest(
                        messages: [
                            ChatTurn(role: .system, content: "You are a private local activity assistant. Do not invent facts."),
                            ChatTurn(role: .user, content: prompt),
                        ]
                    )
                )
                answerText = response.content
                logger.notice(
                    "Answered chat with provider kind=\(providerConfig.kind.rawValue, privacy: .public) evidenceCount=\(relevantEvents.count, privacy: .public)"
                )
            } catch {
                logger.error(
                    "Provider chat failed; using heuristic answer. kind=\(providerConfig.kind.rawValue, privacy: .public) error=\(OpenbirdLog.errorDescription(error), privacy: .public)"
                )
                answerText = heuristicAnswer(for: query.question, events: relevantEvents)
            }
        } else {
            logger.notice("No active provider configured; using heuristic chat answer")
            answerText = heuristicAnswer(for: query.question, events: relevantEvents)
        }

        let userMessage = ChatMessage(
            id: query.userMessageID,
            threadID: query.threadID,
            role: .user,
            content: query.question
        )
        let assistantMessage = ChatMessage(
            id: query.assistantMessageID,
            threadID: query.threadID,
            role: .assistant,
            content: answerText,
            citations: citations
        )
        try await store.saveMessage(userMessage)
        try await store.saveMessage(assistantMessage)
        logger.debug("Saved chat exchange for thread \(query.threadID, privacy: .public)")
        return assistantMessage
    }

    private func heuristicAnswer(for question: String, events: [ActivityEvent]) -> String {
        guard events.isEmpty == false else {
            return "I could not find matching activity in the selected date range."
        }

        let summary = events.prefix(5).map {
            "\(OpenbirdDateFormatting.timeString(for: $0.startedAt)): \($0.appName) — \($0.displayTitle)"
        }.joined(separator: "\n")

        return """
        Based on the captured activity, here are the strongest matches for "\(question)":
        \(summary)
        """
    }
}
