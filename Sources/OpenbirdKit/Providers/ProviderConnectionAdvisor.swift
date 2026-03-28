import Foundation

public enum ProviderConnectionAdvisor {
    public static func suggestedChatModel(from models: [ProviderModelInfo]) -> String? {
        visibleChatModels(from: models).first?.id
    }

    public static func suggestedEmbeddingModel(from models: [ProviderModelInfo]) -> String? {
        models
            .map(\.id)
            .first(where: isEmbeddingModel)
    }

    public static func visibleChatModels(from models: [ProviderModelInfo]) -> [ProviderModelInfo] {
        let visibleModels = models.filter { isVisibleChatModel($0.id) }
        let visibleIDs = Set(visibleModels.map {
            $0.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        return visibleModels.filter { model in
            let modelID = model.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let canonicalID = canonicalChatModelID(model.id)
            if canonicalID == modelID {
                return true
            }
            return visibleIDs.contains(canonicalID) == false
        }
    }

    public static func shouldReplaceChatModel(_ current: String) -> Bool {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty || trimmed == "local-model"
    }

    public static func shouldReplaceEmbeddingModel(_ current: String) -> Bool {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty || trimmed == "text-embedding-model"
    }

    public static func isEmbeddingModel(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let embeddingHints = [
            "embed",
            "embedding",
            "nomic",
            "bge",
            "e5",
            "gte",
        ]
        return embeddingHints.contains { lowered.contains($0) }
    }

    public static func isVisibleChatModel(_ value: String) -> Bool {
        let lowered = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard lowered.isEmpty == false, isEmbeddingModel(lowered) == false else {
            return false
        }

        let blockedPrefixes = [
            "tts-",
            "text-to-speech",
            "dall-e",
            "whisper",
            "omni-moderation",
            "text-moderation",
            "babbage",
            "davinci",
        ]
        if blockedPrefixes.contains(where: lowered.hasPrefix) {
            return false
        }

        let blockedTerms = [
            "audio-preview",
            "realtime-preview",
            "transcribe",
            "moderation",
            "image-generation",
            "image-preview",
            "speech",
            "instruct",
            "rerank",
        ]
        return blockedTerms.contains(where: lowered.contains) == false
    }

    static func canonicalChatModelID(_ value: String) -> String {
        var candidate = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        while let range = candidate.range(
            of: #"-(\d{4}-\d{2}-\d{2}|\d{4}|\d{3}|\d{2})$"#,
            options: .regularExpression
        ) {
            candidate.removeSubrange(range)
        }

        return candidate
    }
}
