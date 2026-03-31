import Foundation

public func normalizedDomain(from url: String?) -> String? {
    guard let value = url?.trimmingCharacters(in: .whitespacesAndNewlines),
          value.isEmpty == false
    else {
        return nil
    }

    let candidates = value.contains("://") ? [value] : [value, "https://\(value)"]
    for candidate in candidates {
        if let host = URLComponents(string: candidate)?.host?.lowercased(),
           host.isEmpty == false {
            return host
        }
    }

    return nil
}

extension String {
    var normalizedComparisonKey: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}

extension Array where Element == String {
    func deduplicatedByNormalizedText() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.normalizedComparisonKey).inserted }
    }
}
