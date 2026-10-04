import AVFoundation
import SwiftUI
import Vision

/// 04 Scan: full-bleed camera, four thin brackets, one glass row at the bottom.
struct ScanView: View {
    let instruction: String
    let symbologies: [VNBarcodeSymbology]
    let evaluate: (ScannedCode) -> Bool
    /// Called the moment a code matches.
    let onMatched: (ScannedCode) -> Void
    /// Called 0.6 s later, once the match animation has played.
    let onFinished: () -> Void
    let onClose: () -> Void
    var onMissing: (() -> Void)?

    private enum ScanState { case looking, matched, wrong }

    @State private var state: ScanState = .looking
    @State private var matchCount = 0
    @State private var wrongCount = 0
    @State private var torchOn = false
    @State private var showMissing = false
    @State private var lastWrong: (payload: String, date: Date)?
    @State private var cameraAvailable = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.camera.ignoresSafeArea()

            if cameraAvailable {
                CodeScanner(symbologies: symbologies, isActive: state != .matched, onScan: handle)
                    .ignoresSafeArea()
            } else {
                unavailable
            }

            brackets

            if state == .matched {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.success, in: .circle)
                    .shadow(color: Theme.success.opacity(0.45), radius: 16)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .accessibilityLabel("Code matched")
            }
        }
        .overlay(alignment: .topLeading) {
            GlassIconButton(systemImage: "xmark", label: "Back to alarm", action: onClose)
                .padding(.leading, 16)
                .padding(.top, 8)
        }
        .overlay(alignment: .bottom) { bottomBar }
        .font(.sora(.body))
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.success, trigger: matchCount)
        .sensoryFeedback(.error, trigger: wrongCount)
        .onAppear { cameraAvailable = CodeScanner.isAvailable || AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined }
        .task {
            try? await Task.sleep(for: .seconds(60))
            withAnimation(.smooth) { showMissing = true }
        }
        .onDisappear { Torch.set(false) }
    }

    private var bracketColor: Color {
        switch state {
        case .looking: .white
        case .matched: Theme.success
        case .wrong: Theme.error
        }
    }

    private var brackets: some View {
        CornerBrackets()
            .stroke(bracketColor, style: StrokeStyle(lineWidth: state == .matched ? 4 : 3, lineCap: .round))
            .frame(width: 240, height: 240)
            .phaseAnimator(state == .looking && !reduceMotion ? [1.0, 1.025] : [1.0]) { content, scale in
                content.scaleEffect(scale)
            } animation: { _ in
                .easeInOut(duration: 1.75)
            }
            .scaleEffect(state == .matched ? 0.62 : 1)
            .shake(wrongCount)
            .accessibilityHidden(true)
    }

    private var pillText: String {
        switch state {
        case .looking: instruction
        case .matched: "Matched"
        case .wrong: "Not that one"
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            if showMissing, let onMissing, state != .matched {
                Button("Code missing?", action: onMissing)
                    .font(.sora(.subheadline))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Text(pillText)
                        .font(.sora(.headline))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .glassEffect(.regular, in: .capsule)
                        .contentTransition(.opacity)
                        .accessibilityAddTraits(.updatesFrequently)

                    if state != .matched {
                        Button {
                            torchOn.toggle()
                            Torch.set(torchOn)
                        } label: {
                            Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.sora(.title3))
                                .foregroundStyle(torchOn ? Theme.accent : Theme.ink)
                                .frame(width: 56, height: 56)
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel("Flashlight")
                        .accessibilityValue(torchOn ? "On" : "Off")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: state)
        .animation(.smooth, value: showMissing)
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.sora(.largeTitle))
            Text("Camera unavailable")
                .font(.sora(.title3, .semibold))
            Text("Allow camera access for Proof of Wake in Settings to scan codes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.inkSecondary)
        }
        .foregroundStyle(Theme.ink)
        .padding(32)
    }

    private func handle(_ code: ScannedCode) {
        guard state != .matched else { return }
        if evaluate(code) {
            withAnimation(.spring(duration: 0.35, bounce: 0.2)) { state = .matched }
            matchCount += 1
            torchOn = false
            Torch.set(false)
            AccessibilityNotification.Announcement("Matched").post()
            onMatched(code)
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                onFinished()
            }
        } else {
            if let lastWrong, lastWrong.payload == code.payload, Date().timeIntervalSince(lastWrong.date) < 2.5 { return }
            lastWrong = (code.payload, Date())
            withAnimation(.snappy) {
                state = .wrong
                showMissing = true
            }
            wrongCount += 1
            AccessibilityNotification.Announcement("Not that one").post()
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                if state == .wrong { withAnimation(.smooth) { state = .looking } }
            }
        }
    }
}
