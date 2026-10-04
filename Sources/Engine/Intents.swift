import AppIntents
import Foundation

/// The alert's system Stop button ("Silence 1 min"). It silences the alarm completely, so unless the
/// user already proved they're awake, it books a re-ring a minute out.
struct StopAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Silence Alarm"
    static let isDiscoverable = false

    @Parameter(title: "Ring ID")
    var ringID: String

    init() {
        self.ringID = ""
    }

    init(ringID: UUID) {
        self.ringID = ringID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: ringID) {
            await RingEngine.shared.systemStopTapped(ringID: id)
        }
        return .result()
    }
}

/// The alert's "Prove you're awake" button: opens the app on the ringing screen for this alarm.
struct OpenAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Prove You're Awake"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "Ring ID")
    var ringID: String

    init() {
        self.ringID = ""
    }

    init(ringID: UUID) {
        self.ringID = ringID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: ringID) {
            await RingEngine.shared.openTapped(ringID: id)
        }
        return .result()
    }
}

/// Run from a Shortcuts personal automation: "When NFC tag ‘Bathroom mirror’ is scanned → Verify Wake Tag".
/// The app has no Core NFC access; iOS reads the tag and calls this intent with the tag's name.
struct VerifyTagIntent: AppIntent {
    static let title: LocalizedStringResource = "Verify Wake Tag"
    static let openAppWhenRun = true

    @Parameter(title: "Tag Name")
    var tagName: String

    init() {
        self.tagName = ""
    }

    init(tagName: String) {
        self.tagName = tagName
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await RingEngine.shared.tagScanned(named: tagName)
        return .result()
    }
}

struct WakeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: VerifyTagIntent(),
            phrases: ["Verify wake tag in \(.applicationName)"],
            shortTitle: "Verify Wake Tag",
            systemImageName: "wave.3.right"
        )
    }
}
