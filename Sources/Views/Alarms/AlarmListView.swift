import SwiftData
import SwiftUI

/// 01 Alarm list (night).
struct AlarmListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\AlarmItem.hour), SortDescriptor(\AlarmItem.minute)]) private var alarms: [AlarmItem]
    @Query private var codes: [WakeCode]

    @State private var editing: AlarmDraft?
    @State private var lockedNotice: String?
    @State private var showDiagnostics = false
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TimelineView(.everyMinute) { timeline in
                        Text(NextAlarm.summary(for: snapshots, now: timeline.date))
                            .font(.sora(.subheadline))
                            .foregroundStyle(Theme.inkSecondary)
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 4)
                    // Diagnostics stays out of the way: hold the "Next alarm" line for a second.
                    .onLongPressGesture(minimumDuration: 1) { showDiagnostics = true }
                    .accessibilityAction(named: "Diagnostics") { showDiagnostics = true }

                    if alarms.isEmpty {
                        EmptyAlarms { editing = newDraft() }
                    } else {
                        GlassEffectContainer(spacing: 6) {
                            VStack(spacing: 12) {
                                ForEach(alarms) { alarm in
                                    AlarmCard(
                                        alarm: alarm,
                                        code: code(for: alarm),
                                        isEditing: isEditing,
                                        lock: AppModel.shared.alarmLocks[alarm.id],
                                        onOpen: { open(alarm) },
                                        onDelete: { delete(alarm) },
                                        onToggle: { reschedule(alarm) }
                                    )
                                    .transition(.blurReplace)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .animation(.spring(duration: 0.4, bounce: 0.15), value: alarms.map(\.id))
                .animation(.spring(duration: 0.35, bounce: 0.15), value: isEditing)
            }
            .background { SkyView(style: .night) }
            .navigationTitle("Alarms")
            .toolbar {
                if !alarms.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Alarm", systemImage: "plus") { editing = newDraft() }
                }
            }
            .sheet(item: $editing) { draft in
                EditAlarmView(draft: draft)
            }
            .navigationDestination(isPresented: $showDiagnostics) { DiagnosticsView() }
            .dismissOnRing {
                editing = nil
                showDiagnostics = false
            }
            .alert("Alarm locked", isPresented: .constant(lockedNotice != nil)) {
                Button("OK") { lockedNotice = nil }
            } message: {
                Text(lockedNotice ?? "")
            }
        }
    }

    private var snapshots: [AlarmSnapshot] {
        alarms.map { $0.snapshot(code: code(for: $0)) }
    }

    private func code(for alarm: AlarmItem) -> WakeCode? {
        codes.first { $0.id == alarm.codeID }
    }

    private func newDraft() -> AlarmDraft {
        AlarmDraft.new(defaultCode: codes.sorted { $0.createdAt < $1.createdAt }.first)
    }

    /// A ringing or silenced alarm opens the proof screen; one about to ring explains why it's locked.
    private func open(_ alarm: AlarmItem) {
        switch RingEngine.shared.lock(for: alarm.id) {
        case .ringing:
            RingEngine.shared.resumeUnfinishedAlarm()
        case .ringsSoon:
            lockedNotice = "It rings in less than \(Int(RingEngine.preRingLock / 60)) minutes, so it can't be changed or switched off until you've proven you're up."
        case nil:
            editing = AlarmDraft(alarm)
        }
    }

    private func delete(_ alarm: AlarmItem) {
        guard !RingEngine.shared.isLocked(alarm.id) else { return }
        RingEngine.shared.forget(alarm.id)
        context.delete(alarm)
        try? context.save()
        if alarms.count <= 1 { isEditing = false }
    }

    private func reschedule(_ alarm: AlarmItem) {
        if !alarm.isEnabled, RingEngine.shared.isLocked(alarm.id) {
            // Switching off is not a way to stop a ringing (or about to ring) alarm.
            alarm.isEnabled = true
            return
        }
        try? context.save()
        let snapshot = alarm.snapshot(code: code(for: alarm))
        Task {
            if snapshot.isEnabled, !(await AlarmService.shared.requestAuthorization()) { return }
            try? await AlarmService.shared.sync(snapshot)
        }
    }
}

private struct EmptyAlarms: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
            Text("No alarms yet")
                .font(.sora(.title2, .semibold))
            Text("Set a time, then pick something you have to get out of bed to scan.")
                .font(.sora(.body))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.inkSecondary)
            Button("Add Alarm", systemImage: "plus", action: add)
                .buttonStyle(.glass)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 72)
    }
}

struct AlarmCard: View {
    @Bindable var alarm: AlarmItem
    let code: WakeCode?
    let isEditing: Bool
    let lock: AlarmLock?
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void

    private var isLocked: Bool { lock != nil }

    var body: some View {
        let parts = Clock.parts(hour: alarm.hour, minute: alarm.minute)
        HStack(spacing: 14) {
            if isEditing && !isLocked {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.sora(.title2))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.error)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(parts.time) alarm")
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(parts.time)
                        .font(Theme.clock(58))
                        .tracking(-1)
                        .minimumScaleFactor(0.5)
                    if let period = parts.period {
                        Text(period).font(.sora(.title3, .medium))
                    }
                }
                .lineLimit(1)
                .foregroundStyle(alarm.isEnabled ? Theme.ink : Theme.inkTertiary)

                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("\(parts.time) \(parts.period ?? "") alarm", isOn: $alarm.isEnabled)
                .labelsHidden()
                .tint(Theme.accent)
                .disabled(isLocked)
                .onChange(of: alarm.isEnabled) { onToggle() }
        }
        .padding(.leading, isEditing ? 12 : 20)
        .padding(.trailing, 18)
        .padding(.vertical, 16)
        .contentShape(.rect(cornerRadius: 28))
        .onTapGesture(perform: onOpen)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
        .contextMenu {
            if lock == .ringing {
                Button("Prove You're Up", systemImage: alarm.method.scanSymbol, action: onOpen)
            } else if lock == nil {
                Button("Edit", systemImage: "pencil", action: onOpen)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
        .accessibilityAction(named: lock == .ringing ? "Prove you're up" : "Edit", onOpen)
    }

    @ViewBuilder
    private var meta: some View {
        switch lock {
        case .ringing:
            Label("Ringing. Tap to prove you're up", systemImage: "lock.fill")
                .font(.sora(.subheadline, .medium))
                .foregroundStyle(Theme.accent)
        case .ringsSoon:
            Label("Rings soon. Locked until you're up", systemImage: "lock.fill")
                .font(.sora(.subheadline, .medium))
                .foregroundStyle(Theme.accent)
        case nil:
            details
        }
    }

    private var details: some View {
        let label = alarm.label.isEmpty ? nil : alarm.label
        let pieces = [label, Weekdays.summary(alarm.weekdays)].compactMap { $0 }.joined(separator: " · ")
        let matched = code?.kind == alarm.method ? code : nil
        return HStack(spacing: 6) {
            Text(matched == nil ? pieces : pieces + " ·")
            if let matched {
                Image(systemName: matched.kind.symbol)
                    .foregroundStyle(alarm.isEnabled ? Theme.accent : Theme.inkTertiary)
                    .accessibilityHidden(true)
                Text(matched.name)
            } else {
                Text("· No code")
                    .foregroundStyle(Theme.accent)
            }
        }
        .font(.sora(.subheadline))
        .lineLimit(2)
        .foregroundStyle(alarm.isEnabled ? Theme.inkSecondary : Theme.inkTertiary)
    }
}
