import SwiftUI

/// Full-screen flow for a ringing alarm: Ringing → Scan / NFC (→ Emergency unlock) → You're up,
/// plus the Wake Up Check five minutes later.
struct RingFlowView: View {
    @Bindable var session: RingSession

    @State private var vibrationTick = 0

    var body: some View {
        ZStack {
            switch session.phase {
            case .ringing:
                RingingView(session: session)
                    .transition(.opacity)
            case .verify:
                verifyView
                    .transition(.opacity)
            case .fallback:
                FallbackView(session: session)
                    .transition(.opacity)
            case .success:
                SuccessView(session: session)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            case .wakeCheck(let deadline):
                WakeCheckView(session: session, deadline: deadline)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if session.parentID == AlarmSnapshot.testAlarmID && session.completedAt == nil {
                Button("End test") { RingEngine.shared.stopTestAlarms() }
                    .font(.sora(.subheadline, .semibold))
                    .buttonStyle(.glass)
                    .padding(.trailing, 16)
                    .padding(.top, 8)
            }
        }
        .animation(.smooth(duration: 0.5), value: session.phase)
        .font(.sora(.body))
        .environment(\.colorScheme, session.colorScheme)
        // Keep the screen on while an alarm is open: iPhone only reads NFC tags with the screen on, and a
        // locked phone would hide the proof screen.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .statusBarHidden(session.phase == .verify && session.alarm.method != .nfc)
        // While the flow is open and unverified, keep a re-ring booked a little ahead, so leaving
        // the app (or the phone dying in a drawer) still ends in another alarm.
        .task(id: session.completedAt == nil) {
            guard session.completedAt == nil else { return }
            while !Task.isCancelled, session.completedAt == nil {
                await RingEngine.shared.keepAlive(session)
                try? await Task.sleep(for: .seconds(RingEngine.keepAliveInterval))
            }
        }
        .task(id: isVibrating) {
            guard isVibrating else { return }
            while !Task.isCancelled {
                vibrationTick += 1
                try? await Task.sleep(for: .seconds(1.6))
            }
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: vibrationTick)
    }

    private var isVibrating: Bool {
        session.alarm.vibration && session.completedAt == nil && session.phase == .ringing
    }

    @ViewBuilder
    private var verifyView: some View {
        let name = session.alarm.codeName ?? "code"
        switch session.alarm.method {
        case .nfc:
            NFCView(
                tagName: name,
                event: session.tagEvent,
                onClose: { session.phase = .ringing },
                onSuccessFinished: { session.phase = .success },
                onMissing: { session.phase = .fallback }
            )
        case .qr, .barcode:
            ScanView(
                instruction: "Scan the \(name.lowercasingFirstLetter)",
                symbologies: session.alarm.method.symbologies,
                evaluate: { session.alarm.matches($0) },
                onMatched: { _ in session.verify() },
                onFinished: { session.phase = .success },
                onClose: { session.phase = .ringing },
                onMissing: { session.phase = .fallback }
            )
        }
    }
}

/// 03 Ringing (night + dawn): date, huge time, label, one glass Stop capsule.
struct RingingView: View {
    let session: RingSession

    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 136

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(session.startedAt)
            ZStack {
                SkyView(style: .ringing, intensity: min(1, 0.55 + 0.45 * elapsed / 300))

                VStack(spacing: 0) {
                    Text(timeline.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.sora(.title3, .semibold))
                        .foregroundStyle(Theme.ink.opacity(0.8))
                    Text(Clock.parts(timeline.date).time)
                        .font(Theme.clock(min(clockSize, 170)))
                        .tracking(-4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .padding(.top, 6)
                        .accessibilityLabel(Clock.string(timeline.date))
                    Text(session.alarm.displayLabel)
                        .font(.sora(.title2, .medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Theme.labelTint, in: .capsule)
                        .padding(.top, 14)

                    Spacer()

                    GlassCapsuleButton(title: "Stop", systemImage: session.alarm.method.scanSymbol) {
                        session.phase = session.proofPhase
                    }
                    .accessibilityHint(session.alarm.hasCode
                                       ? "Scan or tap your \(session.alarm.method.noun) to turn the alarm off"
                                       : "Opens the emergency unlock")
                }
                .foregroundStyle(Theme.ink)
                .shadow(color: Theme.skyTop.opacity(0.25), radius: 12, y: 1)
                .padding(.top, 72)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

/// 06 Dismissed. Dawn sky by day, night sky at night.
struct SuccessView: View {
    let session: RingSession

    @State private var appeared = false

    var body: some View {
        ZStack {
            SkyView(style: .dawn)

            VStack(spacing: 0) {
                Spacer(minLength: 60)
                Image(systemName: "checkmark")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 140, height: 140)
                    .glassEffect(.regular, in: .circle)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .accessibilityLabel("Alarm dismissed")

                Text("You're up")
                    .font(.sora(.largeTitle, .bold))
                    .padding(.top, 40)
                Text("Alarm off at \(Clock.string(session.completedAt ?? .now))")
                    .font(.sora(.body))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 8)

                if session.alarm.wakeCheck {
                    Label("Wake Up Check in 5 minutes", systemImage: "bell")
                        .font(.sora(.subheadline, .medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 32)
                }

                Spacer()

                AccentButton(title: "Done", height: 60) {
                    AppModel.shared.endSession()
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.2)) { appeared = true }
        }
    }
}

/// 07 Wake Up Check. Dawn sky by day, night sky at night.
struct WakeCheckView: View {
    let session: RingSession
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let remaining = max(0, deadline.timeIntervalSince(timeline.date))
            ZStack {
                SkyView(style: .dawn)

                VStack(spacing: 0) {
                    Text("Wake Up Check")
                        .font(.sora(.subheadline, .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 56)
                    Text("Still up?")
                        .font(.sora(.largeTitle, .bold))
                        .padding(.top, 6)

                    ZStack {
                        Circle()
                            .stroke(Theme.ink.opacity(0.1), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: remaining / RingEngine.wakeCheckWindow)
                            .stroke(Theme.accentStrong, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.5), value: remaining)
                        Text(Duration.seconds(remaining.rounded(.up)), format: .time(pattern: .minuteSecond))
                            .font(.sora(fixed: 64))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                    }
                    .padding(10)
                    .frame(width: 240, height: 240)
                    .glassEffect(.regular, in: .circle)
                    .padding(.top, 36)
                    .accessibilityElement()
                    .accessibilityLabel("\(Int(remaining.rounded(.up))) seconds left")

                    Text("Tap before the timer ends, or the alarm rings again.")
                        .font(.sora(.body))
                        .foregroundStyle(Theme.ink.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.top, 34)
                        .padding(.horizontal, 16)

                    Spacer()

                    AccentButton(title: "I'm up", height: 76) {
                        RingEngine.shared.confirmWakeCheck(parent: session.parentID)
                        AppModel.shared.endSession()
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .task {
            let wait = deadline.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, case .wakeCheck = session.phase else { return }
            RingEngine.shared.wakeCheckMissed(parent: session.parentID)
        }
    }
}
