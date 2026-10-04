import Foundation

/// A short on-device log of what the alarm engine did, for checking the re-ring on a real phone.
@MainActor
enum DiagnosticsLog {
    private static let key = "diagnostics.log"
    private static let limit = 200

    static var entries: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ message: String) {
        let stamp = Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        var all = entries
        all.append("\(stamp)  \(message)")
        UserDefaults.standard.set(Array(all.suffix(limit)), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// First characters of an ID, enough to tell rings apart in the log.
    static func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(4))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
    }
}
