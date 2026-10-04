import SwiftData
import SwiftUI

@main
struct UhlarmApp: App {
    init() {
        SoraChrome.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
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
            Group {
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
            .accessibilityHidden(model.session != nil)

            // A ringing alarm covers everything. It's a layer rather than a presented screen, so it shows
            // even when another sheet was open (those close themselves, see `dismissOnRing`).
            if let session = model.session {
                RingFlowView(session: session)
                    .id(session.id)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.smooth(duration: 0.4), value: model.session?.id)
        .font(.sora(.body))
        // Night for the setup screens; a ringing alarm picks night or dawn for itself.
        .preferredColorScheme(model.session?.colorScheme ?? .dark)
        .task {
            await SoundLibrary.installBuiltIns()
            await RingEngine.shared.resyncAll()
            RingEngine.shared.resumeUnfinishedAlarm()
        }
        .task {
            await AlarmService.watchAlerts { alerting in
                await RingEngine.shared.alertsChanged(alerting)
            }
        }
        .task {
            while !Task.isCancelled {
                RingEngine.shared.refreshLocks()
                model.checkPendingWakeChecks()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.checkPendingWakeChecks()
                RingEngine.shared.resumeUnfinishedAlarm()
            }
        }
        .onOpenURL { url in
            // uhlarm://verify?tag=Bathroom%20mirror — for tags that open a URL instead of a shortcut.
            guard url.scheme == "uhlarm", url.host() == "verify",
                  let tag = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "tag" })?.value else { return }
            Task { await RingEngine.shared.tagScanned(named: tag) }
        }
    }
}
