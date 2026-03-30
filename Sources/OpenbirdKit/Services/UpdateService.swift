import Foundation
import OSLog

public final class UpdateService: Sendable {
    private let session: URLSession
    private let latestReleaseURL: URL
    private let logger = OpenbirdLog.updates

    public init(
        session: URLSession = .shared,
        latestReleaseURL: URL = URL(string: "https://api.github.com/repos/ComputelessComputer/openbird/releases/latest")!
    ) {
        self.session = session
        self.latestReleaseURL = latestReleaseURL
    }

    public func latestUpdate(currentVersion: String) async throws -> AppUpdate? {
        let normalizedCurrentVersion = Self.normalizedVersionString(currentVersion)
        guard normalizedCurrentVersion.isEmpty == false else {
            return nil
        }
        logger.notice("Checking for updates from \(normalizedCurrentVersion, privacy: .public)")

        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Openbird", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Update check failed with status \(statusCode, privacy: .public)")
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        let release = try decoder.decode(GitHubRelease.self, from: data)
        let latestVersion = Self.normalizedVersionString(release.tagName)
        guard Self.isVersion(latestVersion, newerThan: normalizedCurrentVersion) else {
            logger.notice("No update available; latest version is \(latestVersion, privacy: .public)")
            return nil
        }

        guard let downloadURL = release.assets.first(where: \.isDiskImage)?.downloadURL else {
            logger.error("Latest release \(latestVersion, privacy: .public) is missing a DMG asset")
            return nil
        }

        logger.notice("Update available: \(latestVersion, privacy: .public)")
        return AppUpdate(
            version: latestVersion,
            releaseURL: release.htmlURL,
            downloadURL: downloadURL
        )
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = versionComponents(from: candidate)
        let currentParts = versionComponents(from: current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidateValue = index < candidateParts.count ? candidateParts[index] : 0
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            if candidateValue != currentValue {
                return candidateValue > currentValue
            }
        }

        return false
    }

    static func normalizedVersionString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let coreVersion = withoutPrefix.split(separator: "-", maxSplits: 1).first.map(String.init) ?? withoutPrefix
        return coreVersion
    }

    private static func versionComponents(from value: String) -> [Int] {
        normalizedVersionString(value)
            .split(separator: ".")
            .compactMap { Int($0) }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let downloadURL: URL

    var isDiskImage: Bool {
        name.hasSuffix(".dmg")
    }

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
    }
}
