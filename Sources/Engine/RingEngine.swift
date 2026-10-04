import Foundation
import UIKit

/// The wake-up rules: what happens when the alert's buttons are tapped, when a code or tag is
/// verified, and when the Wake Up Check goes unanswered.
///
/// One question drives everything: which alarms are *unfinished* (ringing right now, or rung and not yet
/// proven)? The alert buttons, the AlarmKit watcher, opening the app, the NFC intent and the periodic
/// check all ask `unfinishedRings()`, so they can't disagree. Two facts are never second-guessed:
/// an alarm that is ringing always needs proof, and a proof only covers rings that started before it.
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

    struct OpenRing: Equatable {
        let parent: UUID
        let ring: UUID
        let isAlerting: Bool
    }

    private enum Booking {
        case booked(Date)
        /// A newer request replaced this one while it was being scheduled.
        case superseded
        case failed
    }

    private let service = AlarmService.shared
    /// Bumped on every re-ring request per alarm, so a slower, older request can't overwrite a newer one.
    private var generations: [UUID: Int] = [:]

    // MARK: - What's unfinished

    /// Every alarm that still needs proof, ringing ones first.
    func unfinishedRings() -> [OpenRing] {
        let alerting = service.alertingIDs()
        var result: [OpenRing] = []
        var parents: Set<UUID> = []
        for ring in alerting {
            let parent = WakeStore.parent(of: ring)
            if !parents.contains(parent) && !isTestAlarmFinished(parent) {
                result.append(OpenRing(parent: parent, ring: ring, isAlerting: true))
                parents.insert(parent)
            }
        }
        for (parent, _) in WakeStore.openCycles().sorted(by: { $0.value < $1.value }) where !parents.contains(parent) {
            let ring = WakeStore.pending(for: parent) ?? WakeStore.scheduledID(for: parent) ?? parent
            result.append(OpenRing(parent: parent, ring: ring, isAlerting: false))
            parents.insert(parent)
        }
        return result
    }

    /// True while this alarm is ringing, rung and unproven, or open in the ringing flow.
    func isUnfinished(_ parent: UUID) -> Bool {
        if let session = AppModel.shared.session, session.parentID == parent, session.completedAt == nil {
            return true
        }
        return unfinishedRings().contains { $0.parent == parent }
    }

    /// Whether a proof was given after this ring started. A ringing alarm is never proven.
    func isProven(_ ringID: UUID) -> Bool {
        if service.alertingIDs().contains(ringID) { return false }
        guard let provenAt = WakeStore.provenAt(ringID) else { return false }
        if let start = ringStart(ringID) { return provenAt >= start }
        // Unknown start: only a proof from moments ago counts (a duplicate tap, not a new ring).
        return Date.now.timeIntervalSince(provenAt) < 20
    }

    /// When this ring began: a one-off's booked time, or a scheduled alarm's latest occurrence.
    private func ringStart(_ ringID: UUID) -> Date? {
        if let fire = WakeStore.fireDate(of: ringID) { return fire }
        let parent = WakeStore.parent(of: ringID)
        guard let alarm = Library.snapshot(for: parent) else { return nil }
        return NextAlarm.previousDate(for: alarm, before: .now)
    }

    // MARK: - Alert buttons

    func systemStopTapped(ringID: UUID) async {
        DiagnosticsLog.add("Stop tapped (ring \(DiagnosticsLog.short(ringID)))")
        let parent = WakeStore.parent(of: ringID)
        guard !isProven(ringID) else {
            DiagnosticsLog.add("That ring was already proven, no re-ring")
            return
        }
        WakeStore.openCycle(for: parent)
        Library.disableIfOneShot(parent)
        switch await scheduleReRing(parent: parent, after: Self.silenceDuration) {
        case .booked(let date): DiagnosticsLog.add("Re-ring booked for \(DiagnosticsLog.time(date))")
        case .superseded: break
        case .failed: DiagnosticsLog.add("Re-ring could not be booked")
        }
        refreshLocks()
    }

    func openTapped(ringID: UUID) async {
        DiagnosticsLog.add("Prove you're awake tapped (ring \(DiagnosticsLog.short(ringID)))")
        let parent = WakeStore.parent(of: ringID)
        guard !isProven(ringID) else {
            DiagnosticsLog.add("That ring was already proven")
            service.stop(ringID)
            resumeUnfinishedAlarm()
            return
        }
        WakeStore.openCycle(for: parent)
        Library.disableIfOneShot(parent)
        // The app takes over the sound and shows the proof screen first; then the safety re-ring that
        // covers leaving the app.
        service.stop(ringID)
        present(parent: parent, ringID: ringID)
        if case .failed = await scheduleReRing(parent: parent, after: Self.keepAliveLead) {
            DiagnosticsLog.add("Safety re-ring could not be booked")
        }
    }

    // MARK: - Taking over the screen

    /// Shows the proof screen for the first unfinished alarm, if there is one and nothing is showing.
    /// Called on launch, on every return to the foreground, by the AlarmKit watcher and every few
    /// seconds while the app is open, so an unfinished alarm can't sit behind the alarm list.
    func resumeUnfinishedAlarm() {
        guard AppModel.shared.session == nil, let open = unfinishedRings().first else { return }
        if open.isAlerting {
            service.stop(open.ring)
            WakeStore.openCycle(for: open.parent)
            Library.disableIfOneShot(open.parent)
        }
        DiagnosticsLog.add("Showing proof screen (ring \(DiagnosticsLog.short(open.ring))\(open.isAlerting ? ", was ringing" : ""))")
        present(parent: open.parent, ringID: open.ring)
    }

    /// AlarmKit's alarm list changed.
    func alertsChanged(_ alerting: [UUID]) {
        for ring in alerting {
            let parent = WakeStore.parent(of: ring)
            if !isTestAlarmFinished(parent) { WakeStore.openCycle(for: parent) }
        }
        refreshLocks()
        if UIApplication.shared.applicationState == .active { resumeUnfinishedAlarm() }
    }

    private func present(parent: UUID, ringID: UUID) {
        let alarm = Library.snapshot(for: parent) ?? .placeholder(id: parent)
        AppModel.shared.beginRing(parentID: parent, ringID: ringID, phase: alarm.hasCode ? .verify : .fallback)
        refreshLocks()
    }

    // MARK: - Locks

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

    // MARK: - Ringing flow

    func keepAlive(_ session: RingSession) async {
        guard session.completedAt == nil else { return }
        if case .failed = await scheduleReRing(parent: session.parentID, after: Self.keepAliveLead) {
            DiagnosticsLog.add("Safety re-ring could not be booked")
        }
    }

    func complete(_ session: RingSession) async {
        RingTone.shared.stop()
        let parent = session.parentID
        generations[parent, default: 0] += 1
        let rings = [session.ringID, parent] + [WakeStore.pending(for: parent), WakeStore.scheduledID(for: parent)].compactMap { $0 }
        WakeStore.satisfy(rings)
        WakeStore.closeCycle(for: parent)
        cancelPending(for: parent)
        for ring in service.alertingIDs() where WakeStore.parent(of: ring) == parent { service.stop(ring) }
        service.stop(session.ringID)
        Library.disableIfOneShot(parent)
        DiagnosticsLog.add("Proven, alarm off")
        if session.alarm.wakeCheck {
            await scheduleWakeCheck(parent: parent)
        }
        refreshLocks()
    }

    // MARK: - NFC (from the Shortcuts automation or the URL scheme)

    func tagScanned(named name: String) async {
        DiagnosticsLog.add("Tag “\(name)” received")
        let model = AppModel.shared
        model.lastTag = TagScan(name: name)
        Library.confirmTag(named: name)

        if let session = model.session, session.completedAt == nil {
            guard session.alarm.method == .nfc else {
                DiagnosticsLog.add("The open alarm is turned off by a \(session.alarm.method.noun), not a tag")
                return
            }
            session.receiveTag(named: name)
            return
        }

        // Ringing or silenced, with the app not showing it: a matching tag alarm first, then any tag alarm
        // (so a wrong tag shows "That's not the … tag" instead of nothing).
        let candidates = unfinishedRings().compactMap { open -> (OpenRing, AlarmSnapshot)? in
            guard let alarm = Library.snapshot(for: open.parent), alarm.method == .nfc else { return nil }
            return (open, alarm)
        }
        guard let pick = candidates.first(where: { $0.1.matchesTag(named: name) }) ?? candidates.first else {
            resumeUnfinishedAlarm()
            return
        }
        let open = pick.0
        if open.isAlerting { service.stop(open.ring) }
        WakeStore.openCycle(for: open.parent)
        Library.disableIfOneShot(open.parent)
        model.beginRing(parentID: open.parent, ringID: open.ring, phase: .verify)
        model.session?.receiveTag(named: name)
        refreshLocks()
    }

    // MARK: - Wake Up Check

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
        WakeStore.openCycle(for: parent)
        let ringID = UUID()
        WakeStore.link(ringID: ringID, to: parent)
        AppModel.shared.beginRing(parentID: parent, ringID: ringID)
        refreshLocks()
    }

    // MARK: - Test alarm (Diagnostics)

    /// Rings a throwaway alarm shortly, so the Stop → re-ring loop can be tried without waiting.
    func ringTestAlarm(in seconds: TimeInterval) async {
        let parent = AlarmSnapshot.testAlarmID
        WakeStore.closeCycle(for: parent)
        UserDefaults.standard.set(false, forKey: Self.testFinishedKey)
        switch await scheduleReRing(parent: parent, after: seconds) {
        case .booked(let date): DiagnosticsLog.add("Test alarm booked for \(DiagnosticsLog.time(date))")
        case .superseded: break
        case .failed: DiagnosticsLog.add("Test alarm could not be booked")
        }
    }

    func stopTestAlarms() {
        let parent = AlarmSnapshot.testAlarmID
        generations[parent, default: 0] += 1
        cancelPending(for: parent)
        for ring in service.alertingIDs() where WakeStore.parent(of: ring) == parent { service.stop(ring) }
        WakeStore.closeCycle(for: parent)
        UserDefaults.standard.set(true, forKey: Self.testFinishedKey)
        if AppModel.shared.session?.parentID == parent { AppModel.shared.endSession() }
        refreshLocks()
        DiagnosticsLog.add("Test alarms stopped")
    }

    private static let testFinishedKey = "diagnostics.testFinished"

    private func isTestAlarmFinished(_ parent: UUID) -> Bool {
        parent == AlarmSnapshot.testAlarmID && UserDefaults.standard.bool(forKey: Self.testFinishedKey)
    }

    // MARK: - Helpers

    func resyncAll() async {
        guard service.isAuthorized else { return }
        await service.resync(Library.snapshots(), keeping: WakeStore.allPending())
    }

    /// Stops everything for an alarm that's being deleted.
    func forget(_ parent: UUID) {
        generations[parent, default: 0] += 1
        service.cancelScheduled(for: parent)
        cancelPending(for: parent)
        WakeStore.closeCycle(for: parent)
        WakeStore.setWakeCheck(nil, for: parent)
        refreshLocks()
    }

    private func scheduleWakeCheck(parent: UUID) async {
        let deadline = Date.now.addingTimeInterval(Self.wakeCheckDelay + Self.wakeCheckWindow)
        // AlarmKit's backup rings just after the in-app deadline, so an open app handles it first.
        if case .booked(let date) = await scheduleReRing(parent: parent, after: deadline.timeIntervalSinceNow + 10) {
            DiagnosticsLog.add("Wake Up Check backup booked for \(DiagnosticsLog.time(date))")
        }
        WakeStore.setWakeCheck(deadline, for: parent)
        await Notifier.scheduleWakeCheck(parent: parent, at: deadline.addingTimeInterval(-Self.wakeCheckWindow))
    }

    /// Books a one-off ring for this alarm, replacing any pending one.
    private func scheduleReRing(parent: UUID, after seconds: TimeInterval) async -> Booking {
        let generation = (generations[parent] ?? 0) + 1
        generations[parent] = generation
        cancelPending(for: parent)
        let alarm = Library.snapshot(for: parent) ?? .placeholder(id: parent)
        let date = Date.now.addingTimeInterval(seconds)
        guard let ringID = await service.scheduleOneShot(for: alarm, at: date) else { return .failed }
        guard generations[parent] == generation else {
            service.cancel(ringID)
            return .superseded
        }
        cancelPending(for: parent)
        WakeStore.link(ringID: ringID, to: parent)
        WakeStore.setFireDate(date, for: ringID)
        WakeStore.setPending(ringID, for: parent)
        return .booked(date)
    }

    private func cancelPending(for parent: UUID) {
        if let pending = WakeStore.pending(for: parent) {
            service.cancel(pending)
            WakeStore.setPending(nil, for: parent)
        }
    }
}
