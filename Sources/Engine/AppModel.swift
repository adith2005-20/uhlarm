import Foundation
import Observation
import SwiftUI

enum RingPhase: Equatable {
    case ringing
    /// Scanning the code or waiting at the NFC tag.
    case verify
    case fallback
    case success
    case wakeCheck(Date)
}

struct TagEvent: Equatable {
    let id = UUID()
    let name: String
    let matched: Bool
}

struct TagScan: Equatable {
    let id = UUID()
    let name: String
}

/// One alarm the user is currently dealing with in the app.
@MainActor
@Observable
final class RingSession: Identifiable {
    let id = UUID()
    let parentID: UUID
    var ringID: UUID
    let alarm: AlarmSnapshot
    var phase: RingPhase
    var startedAt = Date()
    var completedAt: Date?
    var fallbackStartedAt: Date?
    var tagEvent: TagEvent?

    init(parentID: UUID, ringID: UUID, alarm: AlarmSnapshot, phase: RingPhase) {
        self.parentID = parentID
        self.ringID = ringID
        self.alarm = alarm
        self.phase = phase
    }

    /// Ringing screens follow the real sky: night before 7 AM and after 7 PM, dawn otherwise.
    var isNightRing: Bool {
        let hour = Calendar.current.component(.hour, from: startedAt)
        return hour < 7 || hour >= 19
    }

    /// Night or dawn for the current screen: proof screens are always night; ringing, success and the
    /// Wake Up Check follow the real sky.
    var colorScheme: ColorScheme {
        switch phase {
        case .verify, .fallback: .dark
        case .ringing, .success, .wakeCheck: isNightRing ? .dark : .light
        }
    }

    /// Where the Stop button leads for this alarm.
    var proofPhase: RingPhase { alarm.hasCode ? .verify : .fallback }

    func receiveTag(named name: String) {
        guard completedAt == nil else { return }
        let matched = alarm.matchesTag(named: name)
        if phase != .verify { phase = .verify }
        tagEvent = TagEvent(name: name, matched: matched)
        if matched { verify() }
    }

    /// Proof accepted. Re-rings are cancelled right away; the UI moves on after its animation.
    func verify() {
        guard completedAt == nil else { return }
        completedAt = .now
        Task { await RingEngine.shared.complete(self) }
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var session: RingSession?
    /// Alarms that are ringing or silenced and not yet proven: they can't be switched off, edited or deleted.
    var lockedAlarmIDs: Set<UUID> = []
    /// The latest tag reported by the Shortcuts automation, for the tag tester and registration.
    var lastTag: TagScan?

    func beginRing(parentID: UUID, ringID: UUID, phase: RingPhase = .ringing) {
        if let current = session, current.parentID == parentID {
            current.ringID = ringID
            if current.completedAt != nil {
                // A missed Wake Up Check: the same alarm starts over.
                current.completedAt = nil
                current.startedAt = .now
                current.fallbackStartedAt = nil
                current.tagEvent = nil
                current.phase = phase
                RingTone.shared.start(soundID: current.alarm.soundID, gradual: false)
            }
            return
        }
        let alarm = Library.snapshot(for: parentID) ?? .placeholder(id: parentID)
        session = RingSession(parentID: parentID, ringID: ringID, alarm: alarm, phase: phase)
        RingTone.shared.start(soundID: alarm.soundID, gradual: alarm.gradualVolume)
    }

    func presentWakeCheck(parent: UUID, deadline: Date) {
        guard session == nil else { return }
        let alarm = Library.snapshot(for: parent) ?? .placeholder(id: parent)
        let check = RingSession(parentID: parent, ringID: parent, alarm: alarm, phase: .wakeCheck(deadline))
        check.completedAt = .now
        session = check
    }

    /// Shows a due Wake Up Check when the app is open. Past the deadline, AlarmKit's re-ring has it.
    func checkPendingWakeChecks() {
        let now = Date.now
        for (parent, deadline) in WakeStore.wakeChecks() {
            let opensAt = deadline.addingTimeInterval(-RingEngine.wakeCheckWindow)
            if now > deadline.addingTimeInterval(5) {
                WakeStore.setWakeCheck(nil, for: parent)
            } else if now >= opensAt {
                presentWakeCheck(parent: parent, deadline: deadline)
            }
        }
    }

    func endSession() {
        RingTone.shared.stop()
        session = nil
    }
}
