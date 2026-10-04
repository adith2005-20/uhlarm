import Foundation

/// The wake-up rules: what happens when the alert's buttons are tapped, when a code or tag is
/// verified, and when the Wake Up Check goes unanswered.
@MainActor
final class RingEngine {
    static let shared = RingEngine()

    /// How long after "Silence 1 min" the alarm rings again.
    static let silenceDuration: TimeInterval = 60
    /// While the ringing flow is open, a re-ring is kept this far ahead in case the user leaves the app.
    static let keepAliveLead: TimeInterval = 75
    static let wakeCheckDelay: TimeInterval = 5 * 60
    static let wakeCheckWindow: TimeInterval = 60

    private let service = AlarmService.shared
    /// Bumped on every re-ring request per alarm, so a slower, older request can't overwrite a newer one.
    private var generations: [UUID: Int] = [:]

    // MARK: Alert buttons

    func systemStopTapped(ringID: UUID) async {
        let parent = WakeStore.parent(of: ringID)
        Library.disableIfOneShot(parent)
        guard !WakeStore.isSatisfied(ringID) else { return }
        await scheduleReRing(parent: parent, after: Self.silenceDuration)
    }

    func openTapped(ringID: UUID) async {
        let parent = WakeStore.parent(of: ringID)
        Library.disableIfOneShot(parent)
        guard !WakeStore.isSatisfied(ringID) else { return }
        // The app takes over the sound from here; a safety re-ring covers leaving the app.
        service.stop(ringID)
        await scheduleReRing(parent: parent, after: Self.keepAliveLead)
        AppModel.shared.beginRing(parentID: parent, ringID: ringID)
    }

    // MARK: Ringing flow

    func keepAlive(_ session: RingSession) async {
        guard session.completedAt == nil else { return }
        await scheduleReRing(parent: session.parentID, after: Self.keepAliveLead)
    }

    func complete(_ session: RingSession) async {
        RingTone.shared.stop()
        let parent = session.parentID
        WakeStore.satisfy(WakeStore.rings(of: parent) + [parent, session.ringID])
        cancelPending(for: parent)
        service.stop(session.ringID)
        Library.disableIfOneShot(parent)
        await scheduleWakeCheck(parent: parent)
    }

    // MARK: NFC (from the Shortcuts automation or the URL scheme)

    func tagScanned(named name: String) async {
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

    // MARK: Helpers

    func resyncAll() async {
        guard service.isAuthorized else { return }
        await service.resync(Library.snapshots(), keeping: WakeStore.allPending())
    }

    private func scheduleWakeCheck(parent: UUID) async {
        let deadline = Date.now.addingTimeInterval(Self.wakeCheckDelay + Self.wakeCheckWindow)
        // AlarmKit's backup rings just after the in-app deadline, so an open app handles it first.
        await scheduleReRing(parent: parent, after: deadline.timeIntervalSinceNow + 10)
        WakeStore.setWakeCheck(deadline, for: parent)
        await Notifier.scheduleWakeCheck(parent: parent, at: deadline.addingTimeInterval(-Self.wakeCheckWindow))
    }

    private func scheduleReRing(parent: UUID, after seconds: TimeInterval) async {
        let generation = (generations[parent] ?? 0) + 1
        generations[parent] = generation
        cancelPending(for: parent)
        let alarm = Library.snapshot(for: parent) ?? .placeholder(id: parent)
        guard let ringID = await service.scheduleOneShot(for: alarm, at: .now.addingTimeInterval(seconds)) else { return }
        guard generations[parent] == generation else {
            // A newer request (or a verification) happened while this one was scheduling.
            service.cancel(ringID)
            return
        }
        cancelPending(for: parent)
        WakeStore.link(ringID: ringID, to: parent)
        WakeStore.setPending(ringID, for: parent)
    }

    private func cancelPending(for parent: UUID) {
        if let pending = WakeStore.pending(for: parent) {
            service.cancel(pending)
            WakeStore.setPending(nil, for: parent)
        }
    }
}
