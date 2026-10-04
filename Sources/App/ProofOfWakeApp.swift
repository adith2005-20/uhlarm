import SwiftData
import SwiftUI

@main
struct ProofOfWakeApp: App {
    init() {
        SoraChrome.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(Persistence.container)
    }
}

struct RootView: View {
    @State private var model = AppModel.shared
    @AppStorage("didOnboard") private var didOnboard = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if didOnboard {
                TabView {
                    Tab("Alarms", systemImage: "alarm") {
                        AlarmListView()
                    }
                    Tab("Codes", systemImage: "qrcode") {
                        CodesView()
                    }
                }
                .tint(Theme.accent)
                .transition(.opacity)
            } else {
                OnboardingView {
                    withAnimation(.smooth(duration: 0.6)) { didOnboard = true }
                }
                .transition(.opacity)
            }
        }
        .font(.sora(.body))
        .fullScreenCover(item: $model.session) { session in
            RingFlowView(session: session)
        }
        .task {
            await SoundLibrary.installBuiltIns()
            await RingEngine.shared.resyncAll()
        }
        .task {
            while !Task.isCancelled {
                model.checkPendingWakeChecks()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.checkPendingWakeChecks() }
        }
        .onOpenURL { url in
            // proofofwake://verify?tag=Bathroom%20mirror — for tags that open a URL instead of a shortcut.
            guard url.scheme == "proofofwake", url.host() == "verify",
                  let tag = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "tag" })?.value else { return }
            Task { await RingEngine.shared.tagScanned(named: tag) }
        }
    }
}
