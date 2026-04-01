import Foundation

public enum ActivityChunker {
    public static func makeChunks(
        from groupedEvents: [GroupedActivityEvent],
        day: String
    ) -> [ActivityChunk] {
        groupedEvents.map { event in
            ActivityChunk(
                id: event.id,
                day: day,
                startedAt: event.startedAt,
                endedAt: event.endedAt,
                bundleId: event.bundleId,
                appName: event.appName,
                title: event.displayTitle,
                url: event.url,
                excerpt: event.excerpt,
                isExcluded: event.isExcluded,
                sourceEventIDs: event.sourceEventIDs
            )
        }
    }
}
