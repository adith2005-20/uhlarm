import ActivityKit
import AlarmKit
import SwiftUI

struct WakeMetadata: AlarmMetadata {
    var parentID: UUID
    var label: String
}

/// Thin wrapper over AlarmKit. Every ring (scheduled alarm or re-ring) gets the same presentation:
/// a "Silence 1 min" stop button and a "Prove you're awake" button that opens the app.
@MainActor
final class AlarmService {
    static let shared = AlarmService()

    private let manager = AlarmManager.shared

    var isAuthorized: Bool { manager.authorizationState == .authorized }

    func requestAuthorization() async -> Bool {
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            let state = try? await manager.requestAuthorization()
            return state == .authorized
        @unknown default:
            return false
        }
    }

    /// Schedules (or reschedules) a user alarm under its own ID.
    func sync(_ alarm: AlarmSnapshot) async throws {
        try? manager.cancel(id: alarm.id)
        guard alarm.isEnabled else { return }
        let repeats: Alarm.Schedule.Relative.Recurrence = alarm.isRepeating
            ? .weekly(alarm.weekdays.sorted().compactMap(Weekdays.localeWeekday))
            : .never
        let relative = Alarm.Schedule.Relative(
            time: Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute),
            repeats: repeats
        )
        _ = try await manager.schedule(id: alarm.id,
                                       configuration: configuration(for: alarm, ringID: alarm.id, schedule: .relative(relative)))
    }

    /// A one-off ring for the re-ring workaround and the Wake Up Check. Returns its ring ID.
    func scheduleOneShot(for alarm: AlarmSnapshot, at date: Date) async -> UUID? {
        let ringID = UUID()
        do {
            _ = try await manager.schedule(id: ringID,
                                           configuration: configuration(for: alarm, ringID: ringID, schedule: .fixed(date)))
            return ringID
        } catch {
            return nil
        }
    }

    func cancel(_ id: UUID) {
        try? manager.cancel(id: id)
    }

    func stop(_ id: UUID) {
        try? manager.stop(id: id)
    }

    func alertingIDs() -> [UUID] {
        ((try? manager.alarms) ?? []).filter { $0.state == .alerting }.map(\.id)
    }

    /// Brings AlarmKit in line with the saved alarms, leaving pending re-rings alone.
    func resync(_ alarms: [AlarmSnapshot], keeping pending: Set<UUID>) async {
        let scheduled = Set(((try? manager.alarms) ?? []).map(\.id))
        let wanted = Set(alarms.filter(\.isEnabled).map(\.id))
        for id in scheduled where !wanted.contains(id) && !pending.contains(id) {
            cancel(id)
        }
        for alarm in alarms where alarm.isEnabled && !scheduled.contains(alarm.id) {
            try? await sync(alarm)
        }
    }

    private func configuration(for alarm: AlarmSnapshot, ringID: UUID,
                               schedule: Alarm.Schedule) -> AlarmManager.AlarmConfiguration<WakeMetadata> {
        let silence = AlarmButton(text: "Silence 1 min", textColor: .white, systemImageName: "speaker.slash.fill")
        let prove = AlarmButton(text: "Prove you're awake", textColor: .white, systemImageName: alarm.method.scanSymbol)
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: alarm.displayLabel),
            stopButton: silence,
            secondaryButton: prove,
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakeMetadata(parentID: alarm.id, label: alarm.displayLabel),
            tintColor: Theme.alarmTint
        )
        return .alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmIntent(ringID: ringID),
            secondaryIntent: OpenAlarmIntent(ringID: ringID),
            sound: SoundLibrary.alertSound(for: alarm.soundID)
        )
    }
}
