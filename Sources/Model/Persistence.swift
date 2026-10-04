import Foundation
import SwiftData

@MainActor
enum Persistence {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: AlarmItem.self, WakeCode.self)
        } catch {
            fatalError("Could not open the alarm store: \(error)")
        }
    }()
}

/// Model access for code that runs outside a view: intents and the ringing engine.
@MainActor
enum Library {
    static var context: ModelContext { Persistence.container.mainContext }

    static func alarms() -> [AlarmItem] {
        (try? context.fetch(FetchDescriptor<AlarmItem>())) ?? []
    }

    static func codes() -> [WakeCode] {
        (try? context.fetch(FetchDescriptor<WakeCode>())) ?? []
    }

    static func code(_ id: UUID?) -> WakeCode? {
        guard let id else { return nil }
        return codes().first { $0.id == id }
    }

    static func alarm(_ id: UUID) -> AlarmItem? {
        alarms().first { $0.id == id }
    }

    static func snapshot(for id: UUID) -> AlarmSnapshot? {
        guard let item = alarm(id) else { return nil }
        return item.snapshot(code: code(item.codeID))
    }

    static func snapshots() -> [AlarmSnapshot] {
        let codes = codes()
        return alarms().map { item in item.snapshot(code: codes.first { $0.id == item.codeID }) }
    }

    /// The Shortcuts automation reached the app with this tag name, so the tag works.
    static func confirmTag(named name: String) {
        var changed = false
        for code in codes() where code.kind == .nfc && !code.isConfirmed && TagName.matches(code.name, name) {
            code.isConfirmed = true
            changed = true
        }
        if changed { try? context.save() }
    }

    /// A one-shot alarm has rung, so it switches itself off like the Clock app does.
    static func disableIfOneShot(_ id: UUID) {
        guard let item = alarm(id), item.isEnabled, item.weekdays.isEmpty else { return }
        item.isEnabled = false
        try? context.save()
    }
}
