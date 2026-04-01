import Foundation

public struct ActivityChunk: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var day: String
    public var startedAt: Date
    public var endedAt: Date
    public var bundleId: String
    public var appName: String
    public var title: String
    public var url: String?
    public var excerpt: String
    public var isExcluded: Bool
    public var sourceEventIDs: [String]

    public init(
        id: String = UUID().uuidString,
        day: String,
        startedAt: Date,
        endedAt: Date,
        bundleId: String,
        appName: String,
        title: String,
        url: String?,
        excerpt: String,
        isExcluded: Bool,
        sourceEventIDs: [String]
    ) {
        self.id = id
        self.day = day
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.bundleId = bundleId
        self.appName = appName
        self.title = title
        self.url = url
        self.excerpt = excerpt
        self.isExcluded = isExcluded
        self.sourceEventIDs = sourceEventIDs
    }

    public var sourceEventCount: Int {
        sourceEventIDs.count
    }
}
