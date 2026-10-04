import Foundation

/// Ring-session bookkeeping shared by the intents and the app (they run in the same process).
///
/// Every AlarmKit alarm that rings has a ring ID. A scheduled alarm's ring ID is its own ID; each
/// re-ring gets a fresh one that is linked back to its parent alarm.
@MainActor
enum WakeStore {
    private static let defaults = UserDefaults.standard
    private static let parentsKey = "wake.parentOf"
    private static let pendingKey = "wake.pending"
    private static let satisfiedKey = "wake.satisfied"
    private static let wakeChecksKey = "wake.checks"

    /// How long a verified scan keeps the system Stop button from re-ringing.
    static let satisfiedWindow: TimeInterval = 30 * 60

    // MARK: Ring IDs

    static func parent(of ringID: UUID) -> UUID {
        strings(parentsKey)[ringID.uuidString].flatMap { UUID(uuidString: $0) } ?? ringID
    }

    static func link(ringID: UUID, to parent: UUID) {
        var map = strings(parentsKey)
        map[ringID.uuidString] = parent.uuidString
        defaults.set(map, forKey: parentsKey)
    }

    static func rings(of parent: UUID) -> [UUID] {
        strings(parentsKey).compactMap { key, value in
            value == parent.uuidString ? UUID(uuidString: key) : nil
        }
    }

    // MARK: Pending re-ring

    static func pending(for parent: UUID) -> UUID? {
        strings(pendingKey)[parent.uuidString].flatMap { UUID(uuidString: $0) }
    }

    static func setPending(_ ringID: UUID?, for parent: UUID) {
        var map = strings(pendingKey)
        map[parent.uuidString] = ringID?.uuidString
        defaults.set(map, forKey: pendingKey)
    }

    /// Every alarm with a re-ring booked, and that ring's ID.
    static func pendingRings() -> [(parent: UUID, ring: UUID)] {
        strings(pendingKey).compactMap { key, value -> (parent: UUID, ring: UUID)? in
            guard let parent = UUID(uuidString: key), let ring = UUID(uuidString: value) else { return nil }
            return (parent: parent, ring: ring)
        }
    }

    static func allPending() -> Set<UUID> {
        Set(strings(pendingKey).values.compactMap { UUID(uuidString: $0) })
    }

    // MARK: Verification

    static func satisfy(_ ringIDs: [UUID]) {
        let now = Date().timeIntervalSince1970
        var map = numbers(satisfiedKey).filter { now - $0.value < 86_400 }
        for id in ringIDs { map[id.uuidString] = now }
        defaults.set(map, forKey: satisfiedKey)
    }

    static func isSatisfied(_ ringID: UUID) -> Bool {
        guard let stamp = numbers(satisfiedKey)[ringID.uuidString] else { return false }
        return Date().timeIntervalSince1970 - stamp < satisfiedWindow
    }

    // MARK: Wake Up Check

    static func wakeChecks() -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for (key, value) in numbers(wakeChecksKey) {
            if let id = UUID(uuidString: key) { result[id] = Date(timeIntervalSince1970: value) }
        }
        return result
    }

    static func setWakeCheck(_ deadline: Date?, for parent: UUID) {
        var map = numbers(wakeChecksKey)
        map[parent.uuidString] = deadline?.timeIntervalSince1970
        defaults.set(map, forKey: wakeChecksKey)
    }

    // MARK: Storage

    private static func strings(_ key: String) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private static func numbers(_ key: String) -> [String: Double] {
        defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }
}
