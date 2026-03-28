import Testing
@testable import OpenbirdKit

struct ProviderConnectionAdvisorTests {
    @Test func picksChatAndEmbeddingSuggestions() {
        let models = [
            ProviderModelInfo(id: "text-embedding-nomic-embed-text-v1.5"),
            ProviderModelInfo(id: "tts-1"),
            ProviderModelInfo(id: "google/gemma-3n-e4b"),
            ProviderModelInfo(id: "openai/gpt-oss-20b"),
        ]

        #expect(ProviderConnectionAdvisor.suggestedChatModel(from: models) == "google/gemma-3n-e4b")
        #expect(ProviderConnectionAdvisor.suggestedEmbeddingModel(from: models) == "text-embedding-nomic-embed-text-v1.5")
    }

    @Test func recognizesPlaceholderModelNames() {
        #expect(ProviderConnectionAdvisor.shouldReplaceChatModel("local-model"))
        #expect(ProviderConnectionAdvisor.shouldReplaceEmbeddingModel("text-embedding-model"))
        #expect(ProviderConnectionAdvisor.shouldReplaceChatModel("") == true)
        #expect(ProviderConnectionAdvisor.shouldReplaceEmbeddingModel("nomic-embed-text") == false)
    }

    @Test func detectsEmbeddingModels() {
        #expect(ProviderConnectionAdvisor.isEmbeddingModel("text-embedding-3-large"))
        #expect(ProviderConnectionAdvisor.isEmbeddingModel("nomic-embed-text"))
        #expect(ProviderConnectionAdvisor.isEmbeddingModel("claude-sonnet-4-5") == false)
    }

    @Test func filtersToVisibleChatModels() {
        let models = [
            ProviderModelInfo(id: "gpt-4o"),
            ProviderModelInfo(id: "gpt-4o-2024-08-06"),
            ProviderModelInfo(id: "gpt-4o-audio-preview"),
            ProviderModelInfo(id: "tts-1"),
            ProviderModelInfo(id: "dall-e-3"),
            ProviderModelInfo(id: "omni-moderation-latest"),
            ProviderModelInfo(id: "babbage-002"),
            ProviderModelInfo(id: "text-embedding-3-large"),
            ProviderModelInfo(id: "claude-sonnet-4-5"),
        ]

        #expect(ProviderConnectionAdvisor.visibleChatModels(from: models).map(\.id) == [
            "gpt-4o",
            "claude-sonnet-4-5",
        ])
    }

    @Test func keepsDatedChatModelWhenAliasIsMissing() {
        let models = [
            ProviderModelInfo(id: "gemini-2.5-pro-2025"),
            ProviderModelInfo(id: "text-embedding-004"),
        ]

        #expect(ProviderConnectionAdvisor.visibleChatModels(from: models).map(\.id) == ["gemini-2.5-pro-2025"])
    }
}
