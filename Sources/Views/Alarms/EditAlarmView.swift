import SwiftData
import SwiftUI

struct AlarmDraft: Identifiable {
    var id: UUID
    var isNew: Bool
    var hour: Int
    var minute: Int
    var label: String
    var weekdays: Set<Int>
    var gradualVolume: Bool
    var vibration: Bool
    var method: StopMethod
    var codeID: UUID?
    var soundID: String

    var time: Date {
        get { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now }
        set {
            let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = c.hour ?? 0
            minute = c.minute ?? 0
        }
    }

    static func new(defaultCode: WakeCode?) -> AlarmDraft {
        AlarmDraft(id: UUID(), isNew: true, hour: 7, minute: 0, label: "Wake up", weekdays: [2, 3, 4, 5, 6],
                   gradualVolume: true, vibration: true, method: defaultCode?.kind ?? .qr,
                   codeID: defaultCode?.id, soundID: SoundLibrary.defaultSoundID)
    }

    init(id: UUID, isNew: Bool, hour: Int, minute: Int, label: String, weekdays: Set<Int>, gradualVolume: Bool,
         vibration: Bool, method: StopMethod, codeID: UUID?, soundID: String) {
        self.id = id
        self.isNew = isNew
        self.hour = hour
        self.minute = minute
        self.label = label
        self.weekdays = weekdays
        self.gradualVolume = gradualVolume
        self.vibration = vibration
        self.method = method
        self.codeID = codeID
        self.soundID = soundID
    }

    init(_ item: AlarmItem) {
        self.init(id: item.id, isNew: false, hour: item.hour, minute: item.minute, label: item.label,
                  weekdays: Set(item.weekdays), gradualVolume: item.gradualVolume, vibration: item.vibration,
                  method: item.method, codeID: item.codeID, soundID: item.soundID)
    }
}

/// 02 Create / Edit (night). A sheet with the sky showing through; sections are plain tinted fills.
struct EditAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var codes: [WakeCode]

    @State private var draft: AlarmDraft
    @State private var isSaving = false
    @State private var showDenied = false
    @State private var confirmDelete = false
    @State private var showLocked = false

    init(draft: AlarmDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $draft.time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)

                Section {
                    DayPicker(selection: $draft.weekdays)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                } header: {
                    SectionHeader("Repeat")
                }
                .listRowBackground(Color.clear)

                Section {
                    LabeledContent("Label") {
                        TextField("Alarm", text: $draft.label)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Theme.inkSecondary)
                            .submitLabel(.done)
                    }
                    NavigationLink {
                        SoundPickerView(selection: $draft.soundID)
                    } label: {
                        LabeledContent {
                            Text(SoundLibrary.sound(id: draft.soundID).name)
                        } label: {
                            Label("Sound", systemImage: "music.note")
                                .labelStyle(AccentIconLabelStyle())
                        }
                    }
                }
                .skyRowBackground()

                Section {
                    Toggle(isOn: $draft.gradualVolume) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Gradual volume")
                                Text("Rises over 60 seconds in the app")
                                    .font(.sora(.footnote))
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        } icon: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .labelStyle(AccentIconLabelStyle())
                    }
                    Toggle(isOn: $draft.vibration) {
                        Label("Vibration", systemImage: "iphone.radiowaves.left.and.right")
                            .labelStyle(AccentIconLabelStyle())
                    }
                } header: {
                    SectionHeader("Gentle wake")
                }
                .skyRowBackground()

                Section {
                    NavigationLink {
                        StopMethodView(method: $draft.method, codeID: $draft.codeID)
                    } label: {
                        turnOffRow
                    }
                } header: {
                    SectionHeader("Turn off by")
                }
                .skyRowBackground()

                if !draft.isNew {
                    Section {
                        Button("Delete Alarm", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                    .skyRowBackground()
                }
            }
            .scrollContentBackground(.hidden)
            .background { SkyView(style: .night) }
            .navigationTitle(draft.isNew ? "Add Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { save() }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.accentInk)
                        .disabled(isSaving)
                }
            }
            .alert("Alarms are turned off", isPresented: $showDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    dismiss()
                }
                Button("Not Now", role: .cancel) { dismiss() }
            } message: {
                Text("Your alarm is saved, but it can't ring until you allow uhlarm to schedule alarms in Settings.")
            }
            .alert("Alarm locked", isPresented: $showLocked) {
                Button("OK") { dismiss() }
            } message: {
                Text("This alarm is ringing or rings in less than \(Int(RingEngine.preRingLock / 60)) minutes. It can't be changed until you've proven you're up.")
            }
            .confirmationDialog("Delete this alarm?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Alarm", role: .destructive) { delete() }
            }
        }
        .tint(Theme.accent)
        .font(.sora(.body))
        .sensoryFeedback(.selection, trigger: draft.weekdays)
    }

    private var selectedCode: WakeCode? {
        codes.first { $0.id == draft.codeID && $0.kind == draft.method }
    }

    private var turnOffRow: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: draft.method.symbol, highlighted: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCode?.name ?? "Choose a \(draft.method.noun)")
                    .foregroundStyle(selectedCode == nil ? Theme.accent : Theme.ink)
                Text(draft.method.title)
                    .font(.sora(.footnote))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func save() {
        guard !RingEngine.shared.isLocked(draft.id) else {
            showLocked = true
            return
        }
        isSaving = true
        let item = Library.alarm(draft.id) ?? {
            let created = AlarmItem(id: draft.id, hour: draft.hour, minute: draft.minute)
            context.insert(created)
            return created
        }()
        item.hour = draft.hour
        item.minute = draft.minute
        item.label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        item.weekdays = draft.weekdays.sorted()
        item.gradualVolume = draft.gradualVolume
        item.vibration = draft.vibration
        item.method = draft.method
        item.codeID = selectedCode?.id
        item.soundID = draft.soundID
        item.isEnabled = true
        try? context.save()

        let snapshot = item.snapshot(code: selectedCode)
        Task {
            let allowed = await AlarmService.shared.requestAuthorization()
            await Notifier.requestAuthorization()
            if allowed {
                try? await AlarmService.shared.sync(snapshot)
                dismiss()
            } else {
                isSaving = false
                showDenied = true
            }
        }
    }

    private func delete() {
        guard !RingEngine.shared.isLocked(draft.id) else {
            showLocked = true
            return
        }
        if let item = Library.alarm(draft.id) {
            AlarmService.shared.cancel(item.id)
            context.delete(item)
            try? context.save()
        }
        dismiss()
    }
}

/// Seven 44 pt day circles; selected days are accent-filled with an ink letter.
struct DayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Weekdays.ordered, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(Weekdays.letter(day))
                        .font(.sora(.body, .semibold))
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(isOn ? Theme.accentInk : Theme.inkSecondary)
                        .frame(width: 44, height: 44)
                        .background(isOn ? Theme.accent : Theme.chipFill, in: .circle)
                        .overlay {
                            if !isOn { Circle().strokeBorder(Theme.ink.opacity(0.24), lineWidth: 1) }
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Weekdays.name(day))
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.spring(duration: 0.25, bounce: 0.15), value: selection)
    }
}

/// Row icons in the warm accent, as in the design.
struct AccentIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            configuration.title
        }
    }
}
