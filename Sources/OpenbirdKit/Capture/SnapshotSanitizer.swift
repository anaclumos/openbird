import Foundation

struct SnapshotSanitizer {
    func sanitize(_ snapshot: WindowSnapshot) -> WindowSnapshot {
        var sanitized = snapshot
        let normalizedTitle = normalizedWindowTitle(
            snapshot.windowTitle,
            bundleId: snapshot.bundleId
        )
        let preferredTitle = fallbackTitle(
            currentTitle: normalizedTitle,
            visibleText: snapshot.visibleText,
            appName: snapshot.appName,
            bundleId: snapshot.bundleId
        )

        sanitized.windowTitle = preferredTitle
        sanitized.visibleText = normalizedVisibleText(
            snapshot.visibleText,
            appName: snapshot.appName,
            bundleId: snapshot.bundleId,
            title: preferredTitle
        )
        return sanitized
    }

    func shouldDiscard(_ snapshot: WindowSnapshot) -> Bool {
        if snapshot.bundleId == "com.apple.loginwindow" || snapshot.appName.normalizedComparisonKey == "loginwindow" {
            return true
        }
        return false
    }

    private func normalizedWindowTitle(_ title: String, bundleId: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        switch bundleId {
        case "com.tinyspeck.slackmacgap":
            return normalizedSlackTitle(trimmed)
        case "com.kakao.KakaoTalkMac":
            return normalizedKakaoTalkTitle(trimmed)
        default:
            return trimmed
        }
    }

    private func fallbackTitle(currentTitle: String, visibleText: String, appName: String, bundleId: String) -> String {
        guard isGenericTitle(currentTitle, appName: appName) else { return currentTitle }

        let lines = filteredLines(
            from: visibleText,
            appName: appName,
            bundleId: bundleId,
            title: currentTitle
        )
        return lines.first ?? currentTitle
    }

    private func normalizedVisibleText(_ visibleText: String, appName: String, bundleId: String, title: String) -> String {
        filteredLines(from: visibleText, appName: appName, bundleId: bundleId, title: title)
            .joined(separator: "\n")
    }

    private func filteredLines(from visibleText: String, appName: String, bundleId: String, title: String) -> [String] {
        visibleText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { normalizedWindowTitle($0, bundleId: bundleId) }
            .map { cleanedLine($0, bundleId: bundleId) }
            .filter { $0.isEmpty == false }
            .filter { isDuplicateLine($0, title: title, appName: appName, bundleId: bundleId) == false }
            .filter { isLowSignalLine($0, bundleId: bundleId) == false }
            .deduplicatedByNormalizedText()
    }

    private func cleanedLine(_ line: String, bundleId: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        if browserBundleIDs.contains(bundleId) {
            if browserChromeFragments.filter({ trimmed.normalizedComparisonKey.contains($0) }).count >= 2 {
                return ""
            }
        }

        if bundleId == "com.kakao.KakaoTalkMac" {
            if kakaoTalkChromeFragments.filter({ trimmed.normalizedComparisonKey.contains($0) }).count >= 2 {
                return ""
            }
        }

        if bundleId == "com.tinyspeck.slackmacgap" {
            if slackChromeFragments.filter({ trimmed.normalizedComparisonKey.contains($0) }).count >= 2 {
                return ""
            }
        }

        return trimmed
    }

    private func normalizedSlackTitle(_ title: String) -> String {
        guard title.hasSuffix(" - Slack") else { return title }

        let withoutSuffix = String(title.dropLast(" - Slack".count))
        var parts = withoutSuffix.components(separatedBy: " - ")
        guard parts.count >= 2 else { return title }

        if let last = parts.last, isSlackStatusSegment(last) {
            parts.removeLast()
        }

        guard parts.count >= 2 else { return parts.first ?? withoutSuffix }

        parts.removeLast()
        let normalized = parts.joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty == false {
            return normalized
        }
        return withoutSuffix
    }

    private func isSlackStatusSegment(_ segment: String) -> Bool {
        let normalized = segment.normalizedComparisonKey
        let words = normalized.split(separator: " ")
        guard let first = words.first, Int(first) != nil else { return false }

        return normalized.contains("new item")
            || normalized.contains("new message")
            || normalized.contains("unread")
            || normalized.contains("mention")
            || normalized.contains("reply")
            || normalized.contains("thread")
    }

    private func normalizedKakaoTalkTitle(_ title: String) -> String {
        let normalized = title.normalizedComparisonKey
        if normalized.isEmpty {
            return ""
        }
        if normalized.allSatisfy({ $0.isNumber || $0 == " " }) {
            return ""
        }
        return title
    }

    private func isGenericTitle(_ title: String, appName: String) -> Bool {
        title.isEmpty || title.normalizedComparisonKey == appName.normalizedComparisonKey
    }

    private func isDuplicateLine(_ line: String, title: String, appName: String, bundleId: String) -> Bool {
        let normalized = line.normalizedComparisonKey
        guard normalized.isEmpty == false else { return true }

        let normalizedLineTitle = normalizedWindowTitle(line, bundleId: bundleId).normalizedComparisonKey
        return normalized == title.normalizedComparisonKey
            || normalizedLineTitle == title.normalizedComparisonKey
            || normalized == appName.normalizedComparisonKey
    }

    private func isLowSignalLine(_ line: String, bundleId: String) -> Bool {
        let normalized = line.normalizedComparisonKey
        guard normalized.isEmpty == false else { return true }

        let boilerplate = Set([
            "add page to reading list",
            "downloads window",
            "hide sidebar",
            "page menu",
            "pin window",
            "show sidebar",
            "smart search field",
            "start meeting recording",
            "tab group picker",
            "tauri react typescript",
        ])

        if boilerplate.contains(normalized) {
            return true
        }

        if browserBundleIDs.contains(bundleId),
           browserChromeFragments.contains(where: normalized.contains) {
            return true
        }

        if bundleId == "com.apple.MobileSMS" {
            if messageChromeLines.contains(normalized) {
                return true
            }
            if normalized.hasPrefix("search ") {
                return true
            }
        }

        if bundleId == "com.kakao.KakaoTalkMac" {
            if kakaoTalkChromeLines.contains(normalized) {
                return true
            }
            if kakaoTalkChromeFragments.contains(where: normalized.contains) {
                return true
            }
            if normalized.contains("new message") || normalized.contains("new messages") {
                return true
            }
            if normalized.contains("chatrooms") {
                return true
            }
            if normalized.allSatisfy({ $0.isNumber || $0 == " " }) {
                return true
            }
            if isTimeLikeLine(normalized) {
                return true
            }
        }

        if bundleId == "com.tinyspeck.slackmacgap" && normalized == "slack" {
            return true
        }

        if bundleId == "com.tinyspeck.slackmacgap",
           slackChromeFragments.contains(where: normalized.contains) {
            return true
        }

        return false
    }

    private func isTimeLikeLine(_ normalized: String) -> Bool {
        let words = normalized.split(separator: " ")
        guard words.isEmpty == false else { return true }

        let dateTokens = Set(["am", "pm", "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec"])
        return words.allSatisfy { word in
            word.allSatisfy(\.isNumber) || dateTokens.contains(String(word))
        }
    }
}

private let messageChromeLines: Set<String> = [
    "compose",
    "filter",
    "message",
    "messages",
    "search",
    "start facetime",
]

private let browserBundleIDs: Set<String> = [
    "com.apple.Safari",
    "com.google.Chrome",
    "company.thebrowser.Browser",
    "com.brave.Browser",
    "com.microsoft.edgemac",
]

private let browserChromeFragments: [String] = [
    "add page to reading list",
    "downloads",
    "go back",
    "go forward",
    "page menu",
    "pinned tabs",
    "show sidebar",
    "sidebar",
    "tab bar",
    "tab group picker",
    "tabs",
]

private let kakaoTalkChromeLines: Set<String> = [
    "add chatroom",
    "all folder",
    "button",
    "chatlist icon notioff",
    "chatroom folder",
    "chats",
    "common icon newdot",
    "common icon triangledown",
    "emoticon",
    "enter a message",
    "kakaotalk",
    "notifications",
    "profile",
    "search",
    "settings",
    "silent chatroom",
    "unread folder",
]

private let kakaoTalkChromeFragments: [String] = [
    "add chatroom",
    "all folder",
    "chatroom folder",
    "common icon",
    "newdot",
    "notifications",
    "search",
    "settings",
    "silent chatroom",
    "unread folder",
]

private let slackChromeFragments: [String] = [
    "activity",
    "channels",
    "direct messages",
    "huddles",
    "jump to",
    "later",
    "more",
    "threads",
]
