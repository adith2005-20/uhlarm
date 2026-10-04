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

    /// When an alarm rings, as plain Sendable values (AlarmKit's own types aren't Sendable).
    private enum RingTime: Sendable {
        case daily(hour: Int, minute: Int, weekdays: [Int])
        case at(Date)
    }

    var isAuthorized: Bool { AlarmManager.shared.authorizationState == .authorized }

    func requestAuthorization() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await Self.askForAuthorization()
        @unknown default:
            return false
        }
    }

    /// Schedules (or reschedules) a user alarm under its own ID.
    func sync(_ alarm: AlarmSnapshot) async throws {
        cancel(alarm.id)
        guard alarm.isEnabled else { return }
        try await Self.schedule(
            alarm,
            ringID: alarm.id,
            time: .daily(hour: alarm.hour, minute: alarm.minute, weekdays: alarm.weekdays),
            soundFile: soundFile(for: alarm)
        )
    }

    /// A one-off ring for the re-ring workaround and the Wake Up Check. Returns its ring ID.
    func scheduleOneShot(for alarm: AlarmSnapshot, at date: Date) async -> UUID? {
        let ringID = UUID()
        do {
            try await Self.schedule(alarm, ringID: ringID, time: .at(date), soundFile: soundFile(for: alarm))
            return ringID
        } catch {
            return nil
        }
    }

    func cancel(_ id: UUID) {
        try? AlarmManager.shared.cancel(id: id)
    }

    func stop(_ id: UUID) {
        try? AlarmManager.shared.stop(id: id)
    }

    func alertingIDs() -> [UUID] {
        ((try? AlarmManager.shared.alarms) ?? []).filter { $0.state == .alerting }.map(\.id)
    }

    /// Brings AlarmKit in line with the saved alarms, leaving pending re-rings alone.
    func resync(_ alarms: [AlarmSnapshot], keeping pending: Set<UUID>) async {
        let scheduled = Set(((try? AlarmManager.shared.alarms) ?? []).map(\.id))
        let wanted = Set(alarms.filter(\.isEnabled).map(\.id))
        for id in scheduled where !wanted.contains(id) && !pending.contains(id) {
            cancel(id)
        }
        for alarm in alarms where alarm.isEnabled && !scheduled.contains(alarm.id) {
            try? await sync(alarm)
        }
    }

    /// The sound's file name in Library/Sounds, or nil for the system sound (or a missing file).
    private func soundFile(for alarm: AlarmSnapshot) -> String? {
        let sound = SoundLibrary.sound(id: alarm.soundID)
        guard let fileName = sound.fileName, let url = SoundLibrary.url(for: sound),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return fileName
    }

    // MARK: AlarmKit calls (off the main actor)

    private nonisolated static func askForAuthorization() async -> Bool {
        let state = try? await AlarmManager.shared.requestAuthorization()
        return state == .authorized
    }

    private nonisolated static func schedule(_ alarm: AlarmSnapshot, ringID: UUID, time: RingTime,
                                             soundFile: String?) async throws {
        let schedule: Alarm.Schedule
        switch time {
        case .daily(let hour, let minute, let weekdays):
            let repeats: Alarm.Schedule.Relative.Recurrence = weekdays.isEmpty
                ? .never
                : .weekly(weekdays.sorted().compactMap(Weekdays.localeWeekday))
            schedule = .relative(Alarm.Schedule.Relative(
                time: Alarm.Schedule.Relative.Time(hour: hour, minute: minute),
                repeats: repeats
            ))
        case .at(let date):
            schedule = .fixed(date)
        }

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
        let sound: AlertConfiguration.AlertSound = soundFile.map { .named($0) } ?? .default
        let configuration = AlarmManager.AlarmConfiguration<WakeMetadata>.alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmIntent(ringID: ringID),
            secondaryIntent: OpenAlarmIntent(ringID: ringID),
            sound: sound
        )
        _ = try await AlarmManager.shared.schedule(id: ringID, configuration: configuration)
    }
}
