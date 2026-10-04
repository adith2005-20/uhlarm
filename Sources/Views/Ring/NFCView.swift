import SwiftUI

/// 05 NFC (night). Waits for the Shortcuts automation to report the tag, then plays the ~1.2 s
/// success sequence: contact → snap → ripple → morph → settled.
struct NFCView: View {
    let tagName: String
    let event: TagEvent?
    var closeSymbol = "chevron.down"
    var successTitle = "Alarm off"
    var successSubtitle = "You're up"
    let onClose: () -> Void
    let onSuccessFinished: () -> Void
    var onMissing: (() -> Void)?

    private enum Mode { case waiting, success, failed }

    @State private var mode: Mode = .waiting
    @State private var press: CGFloat = 1
    @State private var antenna: Double = 0
    @State private var burst = false
    @State private var showCheck = false
    @State private var calm: Double = 0
    @State private var settled = false
    @State private var successTick = 0
    @State private var failTick = 0
    @State private var showHelp = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SkyView(style: .ringing, intensity: 0.6, calm: calm)

            antennaGlow

            if burst {
                ForEach(0..<3, id: \.self) { index in
                    SnapRing(delay: Double(index) * 0.08, opacity: [0.8, 0.55, 0.35][index])
                }
            }

            VStack(spacing: 0) {
                Spacer(minLength: 120)
                disc
                texts
                    .padding(.top, 48)
                if mode == .failed {
                    GlassCapsuleButton(title: "Try again", systemImage: "arrow.counterclockwise", height: 52,
                                       font: .sora(.headline), tint: Theme.labelTint) {
                        withAnimation(.smooth) { mode = .waiting }
                    }
                    .fixedSize()
                    .padding(.top, 28)
                    .transition(.opacity)
                }
                Spacer(minLength: 24)
                if mode != .success, let onMissing {
                    Button("Tag missing or damaged?", action: onMissing)
                        .font(.sora(.subheadline))
                        .foregroundStyle(Theme.ink.opacity(0.8))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .topLeading) {
            if mode != .success {
                GlassIconButton(systemImage: closeSymbol, label: "Back", size: 52, action: onClose)
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }
        }
        .font(.sora(.body))
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.success, trigger: successTick)
        .sensoryFeedback(.error, trigger: failTick)
        .task(id: mode == .waiting) {
            guard mode == .waiting else { return }
            try? await Task.sleep(for: .seconds(20))
            if !Task.isCancelled, mode == .waiting { withAnimation(.smooth) { showHelp = true } }
        }
        .onChange(of: event) { _, newEvent in
            guard let newEvent, mode != .success else { return }
            if newEvent.matched {
                Task { await playSuccess() }
            } else {
                withAnimation(.smooth) { mode = .failed }
                failTick += 1
                AccessibilityNotification.Announcement("That's not the \(tagName.lowercasingFirstLetter) tag").post()
            }
        }
    }

    // MARK: Pieces

    private var discTint: Color {
        switch mode {
        case .waiting: Theme.accent.opacity(0.2)
        case .success: Theme.star.opacity(0.18)
        case .failed: Theme.error.opacity(0.28)
        }
    }

    private var iconColor: Color {
        switch mode {
        case .waiting: Theme.accent
        case .success: showCheck ? Theme.star : Theme.accent
        case .failed: Theme.error
        }
    }

    private var symbol: String {
        if showCheck { return "checkmark" }
        return mode == .failed ? "exclamationmark" : "wave.3.right"
    }

    private var disc: some View {
        let glowColor = mode == .failed ? Theme.error : Theme.accent
        return Image(systemName: symbol)
            .font(.system(size: 60, weight: showCheck ? .semibold : .regular))
            .foregroundStyle(iconColor)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 168, height: 168)
            .glassEffect(.regular.tint(discTint).interactive(), in: .circle)
            .background {
                if mode == .waiting && !reduceMotion {
                    RippleRings()
                } else if mode == .failed {
                    ZStack {
                        Circle().stroke(Theme.error.opacity(0.2), lineWidth: 1).offset(x: -12)
                        Circle().stroke(Theme.error.opacity(0.14), lineWidth: 1).offset(x: 10)
                    }
                }
            }
            .phaseAnimator(mode == .waiting && !reduceMotion ? [0.0, 1.0] : [0.4]) { content, glow in
                content.shadow(color: glowColor.opacity(0.22 + 0.28 * glow),
                               radius: 22 + 34 * glow)
            } animation: { _ in
                .easeInOut(duration: 1.75)
            }
            .scaleEffect(press)
            .shake(failTick, amplitude: 12)
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch mode {
        case .waiting: "Waiting for the \(tagName) tag"
        case .success: successTitle
        case .failed: "Wrong tag"
        }
    }

    @ViewBuilder
    private var texts: some View {
        VStack(spacing: 8) {
            switch mode {
            case .waiting:
                Text("Tap the top of your iPhone on the tag")
                    .font(.sora(.title2, .semibold))
                Text(tagName)
                    .font(.sora(.body, .medium))
                    .foregroundStyle(Theme.ink.opacity(0.85))
                Text("Keep the screen on and hold still for a second. iPhone reads the tag and turns the alarm off.")
                    .font(.sora(.subheadline))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .padding(.top, 6)
                if showHelp {
                    Text("Nothing happening? In Shortcuts, check the tag's automation is set to Run Immediately and runs Verify Wake Tag with “\(tagName)”.")
                        .font(.sora(.footnote))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 6)
                        .transition(.opacity)
                }
            case .success:
                Text(successTitle)
                    .font(.sora(.title2, .semibold))
                Text(successSubtitle)
                    .font(.sora(.body))
                    .foregroundStyle(Theme.ink.opacity(0.85))
            case .failed:
                Text("That's not the \(tagName.lowercasingFirstLetter) tag")
                    .font(.sora(.title2, .semibold))
                Text("Hold the top edge of your phone flat against it for a second.")
                    .font(.sora(.body))
                    .foregroundStyle(Theme.ink.opacity(0.8))
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.ink)
        .opacity(mode == .success && !settled ? 0 : 1)
        .offset(y: mode == .success && !settled ? 8 : 0)
        .accessibilityElement(children: .combine)
    }

    private var antennaGlow: some View {
        VStack {
            Capsule()
                .fill(mode == .success ? Theme.star : Theme.accent.opacity(0.6))
                .frame(width: 40, height: 4)
                .scaleEffect(x: 1 + 0.6 * antenna, y: 1)
                .shadow(color: (mode == .success ? Theme.star : Theme.accent).opacity(0.7 + 0.3 * antenna), radius: 12)
                .opacity(mode == .success ? antenna : (mode == .waiting ? 1 : 0.4))
                .padding(.top, 10)
            Spacer()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: Success sequence

    private func playSuccess() async {
        mode = .success
        successTick += 1
        AccessibilityNotification.Announcement(successTitle).post()

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.4)) {
                showCheck = true
                calm = 1
                settled = true
            }
            try? await Task.sleep(for: .seconds(1.4))
            onSuccessFinished()
            return
        }

        // Contact (0–80 ms)
        withAnimation(.linear(duration: 0.08)) {
            press = 0.93
            antenna = 1
        }
        try? await Task.sleep(for: .milliseconds(80))
        // Snap (80–300 ms)
        burst = true
        withAnimation(.easeOut(duration: 0.45)) { antenna = 0 }
        try? await Task.sleep(for: .milliseconds(220))
        // Ripple (300–600 ms)
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) { press = 1.06 }
        withAnimation(.easeOut(duration: 0.85)) { calm = 1 }
        try? await Task.sleep(for: .milliseconds(300))
        // Morph (600–900 ms)
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
            press = 1
            showCheck = true
        }
        try? await Task.sleep(for: .milliseconds(300))
        // Settled (1200 ms)
        withAnimation(.easeOut(duration: 0.5)) { settled = true }
        try? await Task.sleep(for: .milliseconds(1300))
        onSuccessFinished()
    }
}

/// Three accent rings drifting outward from the disc on a slow 6 s loop.
private struct RippleRings: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let progress = (t + Double(index) * 2).truncatingRemainder(dividingBy: 6) / 6
                    Circle()
                        .stroke(Theme.accent.opacity(0.55), lineWidth: 1.5)
                        .scaleEffect(1 + 1.4 * progress)
                        .opacity(0.6 * (1 - progress))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A white ring bursting from the antenna at the top edge (scale 0.1 → 7).
private struct SnapRing: View {
    let delay: Double
    let opacity: Double

    @State private var expanded = false

    var body: some View {
        VStack {
            Circle()
                .stroke(Theme.star.opacity(opacity), lineWidth: 2)
                .frame(width: 200, height: 200)
                .scaleEffect(expanded ? 7 : 0.1)
                .opacity(expanded ? 0 : 1)
                .offset(y: -100)
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.9).delay(delay)) { expanded = true }
        }
    }
}
