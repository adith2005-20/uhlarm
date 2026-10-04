import SwiftUI

/// 08 Lost-code fallback (night): wait 90 s, type a sentence (no pasting), hold 3 s.
struct FallbackView: View {
    let session: RingSession

    static let waitDuration: TimeInterval = 90

    @State private var typed = ""
    @State private var holdProgress: CGFloat = 0
    @State private var unlockTick = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let waited = timeline.date.timeIntervalSince(session.fallbackStartedAt ?? timeline.date)
            let waitDone = waited >= Self.waitDuration
            let matches = Self.normalize(typed) == Self.normalize(sentence)
            let step = !waitDone ? 0 : (matches ? 2 : 1)

            ZStack {
                SkyView(style: .fallback)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        StepBar(step: step)
                        card(waitDone: waitDone, remaining: max(0, Self.waitDuration - waited))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom) {
                holdButton(enabled: waitDone && matches)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
            .foregroundStyle(Theme.ink)
        }
        .onAppear {
            if session.fallbackStartedAt == nil { session.fallbackStartedAt = .now }
            RingTone.shared.soften()
        }
        .sensoryFeedback(.success, trigger: unlockTick)
    }

    private var sentence: String {
        guard let name = session.alarm.codeName else { return "I am out of bed, and I am staying up." }
        var thing = name.lowercasingFirstLetter
        if session.alarm.method == .nfc, !thing.lowercased().hasSuffix("tag") { thing += " tag" }
        return "I am out of bed, and I will replace the \(thing) today."
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private var header: some View {
        HStack {
            GlassIconButton(systemImage: "chevron.left", label: "Back") {
                session.phase = session.alarm.hasCode ? .verify : .ringing
            }
            Spacer()
            Text("Emergency unlock")
                .font(.headline)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private func card(waitDone: Bool, remaining: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if waitDone {
                Text("Type this sentence")
                    .font(.title.bold())
                Text(sentence)
                    .font(.title3)
                    .foregroundStyle(Theme.ink.opacity(0.92))
                    .padding(.top, 14)
                    .accessibilityLabel("Sentence: \(sentence)")
                Text("Your typing")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 20)
                TextField("Start typing", text: $typed, axis: .vertical)
                    .font(.title3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($fieldFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(minHeight: 56)
                    .background(Theme.chipFill, in: .rect(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Theme.accent.opacity(fieldFocused ? 0.8 : 0.5), lineWidth: 1.5)
                    }
                    .padding(.top, 8)
                    // Paste is off: any jump of more than one character is undone.
                    .onChange(of: typed) { old, new in
                        if new.count > old.count + 1 { typed = old }
                    }
                Text("Paste is off. The alarm keeps ringing, quieter, until you finish.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 14)
            } else {
                Text("Take a breath")
                    .font(.title.bold())
                Text("Without your \(session.alarm.method.noun), you can still turn the alarm off. It just takes a little longer, on purpose.")
                    .font(.title3)
                    .foregroundStyle(Theme.ink.opacity(0.92))
                    .padding(.top, 14)
                Text(Duration.seconds(remaining.rounded(.up)), format: .time(pattern: .minuteSecond))
                    .font(Theme.clock(64))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .accessibilityLabel("\(Int(remaining.rounded(.up))) seconds until you can type")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
    }

    private func holdButton(enabled: Bool) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: enabled ? "lock.open.fill" : "lock.fill")
                Text("Hold to turn off")
            }
            .font(.title2.weight(.semibold))
            .foregroundStyle(enabled ? Theme.ink : Theme.ink.opacity(0.5))
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(alignment: .leading) {
                GeometryReader { geo in
                    Theme.accent.opacity(0.4)
                        .frame(width: geo.size.width * holdProgress)
                }
            }
            .clipShape(.capsule)
            .contentShape(.capsule)
            .glassEffect(.regular.tint(Theme.labelTint).interactive(enabled), in: .capsule)
            .contrastBorder(Capsule())
            .onLongPressGesture(minimumDuration: 3, maximumDistance: 40) {
                guard enabled else { return }
                unlock()
            } onPressingChanged: { pressing in
                guard enabled else { return }
                withAnimation(pressing ? .linear(duration: 3) : .easeOut(duration: 0.25)) {
                    holdProgress = pressing ? 1 : 0
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Hold to turn off")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(enabled ? "Touch and hold for three seconds" : "Unlocks once the sentence matches")
            .accessibilityAction {
                if enabled { unlock() }
            }

            Text(enabled ? "Keep holding for 3 seconds" : "Unlocks once the sentence matches")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func unlock() {
        unlockTick += 1
        fieldFocused = false
        session.verify()
        session.phase = .success
    }
}

/// Glass step bar: Wait 90 s · Type · Hold 3 s.
private struct StepBar: View {
    let step: Int

    private let titles = ["Wait 90 s", "Type", "Hold 3 s"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(titles.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    if index < step {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.success)
                    }
                    Text(titles[index])
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(index == step ? Theme.accent : Theme.ink.opacity(index < step ? 0.72 : 0.55))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(index == step ? Theme.accent.opacity(0.22) : .clear, in: .capsule)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(index == step ? .isSelected : [])
            }
        }
        .padding(6)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .animation(.smooth, value: step)
    }
}
