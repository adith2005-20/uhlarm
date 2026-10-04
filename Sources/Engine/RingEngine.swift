import Foundation
import UIKit

/// The wake-up rules: what happens when the alert's buttons are tapped, when a code or tag is
/// verified, and when the Wake Up Check goes unanswered.
@MainActor
final class RingEngine {
    static let shared = RingEngine()

    /// How long the alert's system Stop button ("Silence 15 sec") silences the alarm.
    nonisolated static let silenceDuration: TimeInterval = 15
    /// While the ringing flow is open, a re-ring is kept this far ahead in case the user leaves the app.
    static let keepAliveLead: TimeInterval = 20
    /// How often the ringing flow pushes that re-ring back. Must stay well under `keepAliveLead`.
    static let keepAliveInterval: TimeInterval = 6
    /// Alarms are locked this long before they ring, so they can't be switched off at the last minute.
    static let preRingLock: TimeInterval = 5 * 60
    static let wakeCheckDelay: TimeInterval = 5 * 60
    static let wakeCheckWindow: TimeInterval = 60

    private let service = AlarmService.shared
    /// Bumped on every re-ring request per alarm, so a slower, older request can't overwrite a newer one.
    private var generations: [UUID: Int] = [:]

    // MARK: Alert buttons

    func systemStopTapped(ringID: UUID) async {
        DiagnosticsLog.add("Stop tapped (ring \(DiagnosticsLog.short(ringID)))")
        let parent = WakeStore.parent(of: ringID)
        Library.disableIfOneShot(parent)
        guard !WakeStore.isSatisfied(ringID) else {
            DiagnosticsLog.add("Already verified, no re-ring")
            return
        }
        if let date = await scheduleReRing(parent: parent, after: Self.silenceDuration) {
            DiagnosticsLog.add("Re-ring booked for \(DiagnosticsLog.time(date))")
        } else {
            DiagnosticsLog.add("Re-ring was not booked")
        }
        refreshLocks()
    }

    func openTapped(ringID: UUID) async {
        DiagnosticsLog.add("Prove you're awake tapped (ring \(DiagnosticsLog.short(ringID)))")
        let parent = WakeStore.parent(of: ringID)
        Library.disableIfOneShot(parent)
        guard !WakeStore.isSatisfied(ringID) else {
            DiagnosticsLog.add("Already verified, nothing to prove")
            return
        }
        // The app takes over the sound and shows the proof screen first, then books the safety re-ring
        // that covers leaving the app.
        service.stop(ringID)
        let alarm = Library.snapshot(for: parent) ?? .placeholder(id: parent)
        AppModel.shared.beginRing(parentID: parent, ringID: ringID, phase: alarm.hasCode ? .verify : .fallback)
        refreshLocks()
        if await scheduleReRing(parent: parent, after: Self.keepAliveLead) == nil {
            DiagnosticsLog.add("Safety re-ring was not booked")
        }
    }

    /// AlarmKit's alarm list changed. A ring that starts while the app is in front is taken over by the
    /// app straight away, whether or not the alert's buttons ever reach the app.
    func alertsChanged(_ alerting: [UUID]) {
        refreshLocks()
        guard UIApplication.shared.applicationState == .active,
              alerting.contains(where: { !WakeStore.isSatisfied($0) }) else { return }
        resumeUnfinishedAlarm()
    }

    /// True while this alarm is ringing, silenced with a re-ring booked, or open in the ringing flow.
    func isUnfinished(_ parent: UUID) -> Bool {
        if let session = AppModel.shared.session, session.parentID == parent, session.completedAt == nil {
            return true
        }
        if WakeStore.wakeChecks()[parent] == nil, let pending = WakeStore.pending(for: parent),
           !WakeStore.isSatisfied(pending), service.knownIDs().contains(pending) {
            return true
        }
        return service.alertingIDs().contains { WakeStore.parent(of: $0) == parent && !WakeStore.isSatisfied($0) }
    }

    /// Why this alarm can't be switched off, edited or deleted right now, if it can't.
    func lock(for parent: UUID) -> AlarmLock? {
        if isUnfinished(parent) { return .ringing }
        if let alarm = Library.snapshot(for: parent), alarm.isEnabled,
           let next = NextAlarm.date(for: alarm, after: .now),
           next.timeIntervalSinceNow <= Self.preRingLock {
            return .ringsSoon
        }
        return nil
    }

    func isLocked(_ parent: UUID) -> Bool { lock(for: parent) != nil }

    func refreshLocks() {
        var locks: [UUID: AlarmLock] = [:]
        for alarm in Library.alarms() {
            if let lock = lock(for: alarm.id) { locks[alarm.id] = lock }
        }
        if AppModel.shared.alarmLocks != locks { AppModel.shared.alarmLocks = locks }
    }

    /// Opening the app while an alarm is silenced (re-ring booked) or still ringing goes straight to
    /// proving you're up, so the app is never a way around the alarm.
    func resumeUnfinishedAlarm() {
        let model = AppModel.shared
        guard model.session == nil else { return }
        let known = service.knownIDs()
        let alerting = service.alertingIDs()
        let wakeChecks = WakeStore.wakeChecks()

        // Silenced: a re-ring is booked and hasn't been dealt with. (A Wake Up Check's backup is handled
        // by the Wake Up Check itself.)
        if let pending = WakeStore.pendingRings().first(where: { entry in
            wakeChecks[entry.parent] == nil && known.contains(entry.ring) && !WakeStore.isSatisfied(entry.ring)
        }) {
            resume(parent: pending.parent, ringID: pending.ring, stopping: alerting.contains(pending.ring))
            return
        }
        // Ringing right now, but opened from the Home Screen instead of the alert.
        if let ringID = alerting.first(where: { !WakeStore.isSatisfied($0) }) {
            resume(parent: WakeStore.parent(of: ringID), ringID: ringID, stopping: true)
        }
    }

    private func resume(parent: UUID, ringID: UUID, stopping: Bool) {
        if stopping { service.stop(ringID) }
        Library.disableIfOneShot(parent)
        let alarm = Library.snapshot(for: parent) ?? .placeholder(id: parent)
        DiagnosticsLog.add("Opened with alarm unfinished (ring \(DiagnosticsLog.short(ringID))), asking for proof")
        AppModel.shared.beginRing(parentID: parent, ringID: ringID, phase: alarm.hasCode ? .verify : .fallback)
        refreshLocks()
    }

    // MARK: Ringing flow

    func keepAlive(_ session: RingSession) async {
        guard session.completedAt == nil else { return }
        if await scheduleReRing(parent: session.parentID, after: Self.keepAliveLead) == nil {
            DiagnosticsLog.add("Safety re-ring was not booked")
        }
    }

    func complete(_ session: RingSession) async {
        RingTone.shared.stop()
        let parent = session.parentID
        WakeStore.satisfy(WakeStore.rings(of: parent) + [parent, session.ringID])
        cancelPending(for: parent)
        service.stop(session.ringID)
        Library.disableIfOneShot(parent)
        DiagnosticsLog.add("Verified, re-rings cancelled")
        await scheduleWakeCheck(parent: parent)
        refreshLocks()
    }

    // MARK: NFC (from the Shortcuts automation or the URL scheme)

    func tagScanned(named name: String) async {
        DiagnosticsLog.add("Tag “\(name)” received")
        let model = AppModel.shared
        model.lastTag = TagScan(name: name)
        Library.confirmTag(named: name)

        if let session = model.session, session.completedAt == nil, session.alarm.method == .nfc {
            session.receiveTag(named: name)
            return
        }

        // The alert is still on screen and the user went straight to the tag.
        for ringID in service.alertingIDs() {
            let parent = WakeStore.parent(of: ringID)
            guard let alarm = Library.snapshot(for: parent), alarm.matchesTag(named: name) else { continue }
            Library.disableIfOneShot(parent)
            service.stop(ringID)
            model.beginRing(parentID: parent, ringID: ringID, phase: .verify)
            model.session?.receiveTag(named: name)
            return
        }
    }

    // MARK: Wake Up Check

    func confirmWakeCheck(parent: UUID) {
        generations[parent, default: 0] += 1
        cancelPending(for: parent)
        WakeStore.setWakeCheck(nil, for: parent)
        Notifier.cancelWakeCheck(parent: parent)
    }

    /// The timer ran out with the app open: ring again in-app, same stop method.
    func wakeCheckMissed(parent: UUID) {
        generations[parent, default: 0] += 1
        cancelPending(for: parent)
        WakeStore.setWakeCheck(nil, for: parent)
        let ringID = UUID()
        WakeStore.link(ringID: ringID, to: parent)
        AppModel.shared.beginRing(parentID: parent, ringID: ringID)
    }

    // MARK: Test alarm (Diagnostics)

    /// Rings a throwaway alarm shortly, so the Stop → re-ring loop can be tried without waiting.
    func ringTestAlarm(in seconds: TimeInterval) async {
        let parent = AlarmSnapshot.testAlarmID
        if let date = await scheduleReRing(parent: parent, after: seconds) {
            DiagnosticsLog.add("Test alarm booked for \(DiagnosticsLog.time(date))")
        } else {
            DiagnosticsLog.add("Test alarm was not booked")
        }
    }

    func stopTestAlarms() {
        let parent = AlarmSnapshot.testAlarmID
        generations[parent, default: 0] += 1
        cancelPending(for: parent)
        WakeStore.satisfy(WakeStore.rings(of: parent) + [parent])
        if AppModel.shared.session?.parentID == parent { AppModel.shared.endSession() }
        DiagnosticsLog.add("Test alarms stopped")
    }

    // MARK: Helpers

    func resyncAll() async {
        guard service.isAuthorized else { return }
        await service.resync(Library.snapshots(), keeping: WakeStore.allPending())
    }

    private func scheduleWakeCheck(parent: UUID) async {
        let deadline = Date.now.addingTimeInterval(Self.wakeCheckDelay + Self.wakeCheckWindow)
        // AlarmKit's backup rings just after the in-app deadline, so an open app handles it first.
        if let date = await scheduleReRing(parent: parent, after: deadline.timeIntervalSinceNow + 10) {
            DiagnosticsLog.add("Wake Up Check backup booked for \(DiagnosticsLog.time(date))")
        }
        WakeStore.setWakeCheck(deadline, for: parent)
        await Notifier.scheduleWakeCheck(parent: parent, at: deadline.addingTimeInterval(-Self.wakeCheckWindow))
    }

    /// Books a one-off ring for this alarm, replacing any pending one. Returns when it will ring.
    @discardableResult
    private func scheduleReRing(parent: UUID, after seconds: TimeInterval) async -> Date? {
        let generation = (generations[parent] ?? 0) + 1
        generations[parent] = generation
        cancelPending(for: parent)
        let alarm = Library.snapshot(for: parent) ?? .placeholder(id: parent)
        let date = Date.now.addingTimeInterval(seconds)
        guard let ringID = await service.scheduleOneShot(for: alarm, at: date) else { return nil }
        guard generations[parent] == generation else {
            // A newer request (or a verification) happened while this one was scheduling.
            service.cancel(ringID)
            return nil
        }
        cancelPending(for: parent)
        WakeStore.link(ringID: ringID, to: parent)
        WakeStore.setPending(ringID, for: parent)
        return date
    }

    private func cancelPending(for parent: UUID) {
        if let pending = WakeStore.pending(for: parent) {
            service.cancel(pending)
            WakeStore.setPending(nil, for: parent)
        }
    }
}
