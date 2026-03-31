import Foundation

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
