import Foundation

/// Ring bookkeeping shared by the intents and the app. Everything is persisted, so it survives the
/// app being launched in the background for an intent and then terminated.
///
/// Every AlarmKit alarm that rings has a ring ID linked back to its parent alarm (the saved AlarmItem):
/// the scheduled alarm gets a fresh ID each time it's saved, and each re-ring gets its own.
///
/// An alarm's *cycle* opens the first time we learn it rang and closes only when the user proves
/// they're up. While it's open, the app always asks for proof.
@MainActor
enum WakeStore {
    private static let defaults = UserDefaults.standard
    private static let parentsKey = "wake.parentOf"
    private static let pendingKey = "wake.pending"
    private static let satisfiedKey = "wake.satisfied"
    private static let wakeChecksKey = "wake.checks"
    private static let scheduledKey = "wake.scheduled"
    private static let fireDatesKey = "wake.fireDates"
    private static let cyclesKey = "wake.openCycles"

    /// An open cycle older than this is treated as stale (it can't still be ringing).
    static let cycleLifetime: TimeInterval = 12 * 60 * 60

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

    // MARK: Scheduled alarm (current AlarmKit ID of each saved alarm)

    static func scheduledID(for parent: UUID) -> UUID? {
        strings(scheduledKey)[parent.uuidString].flatMap { UUID(uuidString: $0) }
    }

    static func setScheduledID(_ ringID: UUID?, for parent: UUID) {
        var map = strings(scheduledKey)
        map[parent.uuidString] = ringID?.uuidString
        defaults.set(map, forKey: scheduledKey)
    }

    static func isScheduledID(_ ringID: UUID) -> Bool {
        strings(scheduledKey).values.contains(ringID.uuidString)
    }

    // MARK: One-off ring times

    static func fireDate(of ringID: UUID) -> Date? {
        numbers(fireDatesKey)[ringID.uuidString].map { Date(timeIntervalSince1970: $0) }
    }

    static func setFireDate(_ date: Date, for ringID: UUID) {
        let now = Date().timeIntervalSince1970
        var map = numbers(fireDatesKey).filter { now - $0.value < 86_400 }
        map[ringID.uuidString] = date.timeIntervalSince1970
        defaults.set(map, forKey: fireDatesKey)
    }

    // MARK: Open cycles (rang, not yet proven)

    static func openCycles() -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        let now = Date()
        for (key, value) in numbers(cyclesKey) {
            let opened = Date(timeIntervalSince1970: value)
            if let id = UUID(uuidString: key), now.timeIntervalSince(opened) < cycleLifetime { result[id] = opened }
        }
        return result
    }

    static func openCycle(for parent: UUID) {
        var map = numbers(cyclesKey)
        if map[parent.uuidString] == nil { map[parent.uuidString] = Date().timeIntervalSince1970 }
        defaults.set(map, forKey: cyclesKey)
    }

    static func closeCycle(for parent: UUID) {
        var map = numbers(cyclesKey)
        map[parent.uuidString] = nil
        defaults.set(map, forKey: cyclesKey)
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

    /// When this ring was last proven, if ever. Whether that proof covers a given ring is decided by
    /// `RingEngine.isProven`, which compares it with when the ring started.
    static func provenAt(_ ringID: UUID) -> Date? {
        numbers(satisfiedKey)[ringID.uuidString].map { Date(timeIntervalSince1970: $0) }
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
