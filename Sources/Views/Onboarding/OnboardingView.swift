import SwiftUI

/// A short introduction. The sun rises a little more with every page.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0
    @State private var isRequesting = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbols: ["sunrise.fill"],
            title: "uhlarm",
            body: "An alarm that only goes quiet once you're truly up. Calm screens, a sky that moves, and no way to snooze from under the covers."
        ),
        OnboardingPage(
            symbols: ["qrcode", "barcode", "wave.3.right"],
            title: "Put it out of reach",
            body: "Register a QR code, any barcode, or an NFC sticker somewhere you have to walk to: the kitchen wall, the coffee bag, the bathroom mirror."
        ),
        OnboardingPage(
            symbols: ["hand.tap.fill"],
            title: "Prove you're awake",
            body: "When it rings, tap Prove you're awake, then scan or tap your code. Silencing only buys 15 seconds. Then it rings again."
        ),
        OnboardingPage(
            symbols: ["lifepreserver.fill"],
            title: "Never locked out",
            body: "Lost your code? The emergency unlock always gets you out: wait 90 seconds, type a sentence, hold to finish."
        ),
        OnboardingPage(
            symbols: ["alarm.fill"],
            title: "Ring through Silent",
            body: "Allow alarms so they ring even in Silent mode and Focus, and notifications for the optional Wake Up Check. The camera is only used to scan."
        ),
    ]

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            SkyView(style: .ringing, intensity: Double(page) / Double(pages.count - 1))
                .animation(.easeInOut(duration: 1.2), value: page)

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPageView(page: pages[index], isFirst: index == 0)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                VStack(spacing: 10) {
                    AccentButton(title: isLast ? "Allow & Get Started" : "Continue", height: 60) {
                        if isLast {
                            finish()
                        } else {
                            withAnimation(.smooth) { page += 1 }
                        }
                    }
                    .disabled(isRequesting)

                    Button(isLast ? "Not now" : "Skip") {
                        if isLast { onFinish() } else { withAnimation(.smooth) { page = pages.count - 1 } }
                    }
                    .font(.sora(.subheadline, .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .foregroundStyle(Theme.ink)
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.selection, trigger: page)
    }

    private func finish() {
        isRequesting = true
        Task {
            _ = await AlarmService.shared.requestAuthorization()
            await Notifier.requestAuthorization()
            isRequesting = false
            onFinish()
        }
    }
}

private struct OnboardingPage {
    let symbols: [String]
    let title: String
    let body: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isFirst: Bool

    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 60)

                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 16) {
                        ForEach(page.symbols, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.system(size: page.symbols.count == 1 ? 56 : 32, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Theme.accent)
                                .frame(width: page.symbols.count == 1 ? 132 : 84,
                                       height: page.symbols.count == 1 ? 132 : 84)
                                .glassEffect(.regular.tint(Theme.accent.opacity(0.12)), in: .circle)
                        }
                    }
                }
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)

                VStack(spacing: 14) {
                    Text(page.title)
                        .font(isFirst ? .sora(.largeTitle, .bold) : .sora(.title, .bold))
                    Text(page.body)
                        .font(.sora(.body))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .offset(y: appeared ? 0 : 10)
                .opacity(appeared ? 1 : 0)

                Spacer(minLength: 60)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(0.1)) { appeared = true }
        }
    }
}
