import Foundation

public actor RetrievalService {
    private let store: OpenbirdStore

    public init(store: OpenbirdStore) {
        self.store = store
    }

    public func searchChunks(
        query: String,
        range: ClosedRange<Date>,
        appFilters: [String],
        topK: Int
    ) async throws -> [ActivityChunk] {
        let directChunkHits = try await store.searchActivityChunks(
            query: query,
            in: range,
            appFilters: appFilters,
            topK: topK
        )
        if directChunkHits.isEmpty == false {
            return directChunkHits
        }

        let eventHits = try await store.searchActivityEvents(
            query: query,
            in: range,
            appFilters: appFilters,
            topK: topK * 4
        )
        guard eventHits.isEmpty == false else {
            return []
        }

        var chunksBySourceEventID: [String: ActivityChunk] = [:]
        for day in daysCovered(by: range) {
            let chunks = try await store.activityChunks(for: day)
            for chunk in chunks {
                for sourceEventID in chunk.sourceEventIDs {
                    chunksBySourceEventID[sourceEventID] = chunk
                }
            }
        }

        var rankedChunks: [ActivityChunk] = []
        var seenChunkIDs = Set<String>()
        for event in eventHits {
            guard var chunk = chunksBySourceEventID[event.id],
                  seenChunkIDs.insert(chunk.id).inserted else {
                continue
            }
            if event.excerpt.isEmpty == false {
                chunk.excerpt = event.excerpt
            }
            rankedChunks.append(chunk)
            if rankedChunks.count == topK {
                break
            }
        }

        return rankedChunks
    }

    public func search(
        query: String,
        range: ClosedRange<Date>,
        appFilters: [String],
        topK: Int,
        providerConfig: ProviderConfig? = nil
    ) async throws -> [ActivityEvent] {
        let ftsResults = try await store.searchActivityEvents(
            query: query,
            in: range,
            appFilters: appFilters,
            topK: topK * 2
        )

        guard let providerConfig,
              providerConfig.embeddingModel.isEmpty == false,
              ftsResults.isEmpty == false
        else {
            return Array(ftsResults.prefix(topK))
        }

        let provider = ProviderFactory.makeProvider(for: providerConfig)
        let queryVector = try await provider.embed(texts: [query]).first ?? []
        guard queryVector.isEmpty == false else { return Array(ftsResults.prefix(topK)) }

        var storedVectors = Dictionary(uniqueKeysWithValues: try await store.loadEmbeddingChunks(
            providerID: providerConfig.id,
            model: providerConfig.embeddingModel
        ).map {
            ($0.eventID, $0.vector)
        })

        for event in ftsResults where storedVectors[event.id] == nil {
            let embedding = try await provider.embed(texts: [event.visibleText.isEmpty ? event.displayTitle : event.visibleText]).first ?? []
            guard embedding.isEmpty == false else { continue }
            try await store.saveEmbeddingChunk(
                id: "\(providerConfig.id)-\(event.id)",
                eventID: event.id,
                providerID: providerConfig.id,
                model: providerConfig.embeddingModel,
                vector: embedding,
                snippet: event.excerpt
            )
            storedVectors[event.id] = embedding
        }

        let ranked = ftsResults
            .map { event in
                (event, cosineSimilarity(lhs: queryVector, rhs: storedVectors[event.id] ?? []))
            }
            .sorted { lhs, rhs in lhs.1 > rhs.1 }
            .prefix(topK)
            .map(\.0)

        return Array(ranked)
    }

    private func cosineSimilarity(lhs: [Double], rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, lhs.isEmpty == false else { return -1 }
        let dot = zip(lhs, rhs).map(*).reduce(0, +)
        let lhsMagnitude = sqrt(lhs.map { $0 * $0 }.reduce(0, +))
        let rhsMagnitude = sqrt(rhs.map { $0 * $0 }.reduce(0, +))
        guard lhsMagnitude > 0, rhsMagnitude > 0 else { return -1 }
        return dot / (lhsMagnitude * rhsMagnitude)
    }

    private func daysCovered(by range: ClosedRange<Date>) -> [Date] {
        var dates: [Date] = []
        let calendar = Calendar.current
        var current = calendar.startOfDay(for: range.lowerBound)
        let last = calendar.startOfDay(for: range.upperBound)

        while current <= last {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                break
            }
            current = next
        }

        return dates
    }
}
