import Foundation
import OSLog

public enum OpenbirdLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.computelesscomputer.openbird"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    public static let collector = Logger(subsystem: subsystem, category: "collector")
    public static let chat = Logger(subsystem: subsystem, category: "chat")
    public static let journal = Logger(subsystem: subsystem, category: "journal")
    public static let providers = Logger(subsystem: subsystem, category: "providers")
    public static let updates = Logger(subsystem: subsystem, category: "updates")

    public static func errorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
    }
}
