import SwiftUI
import AlarmKit
import AppIntents
import ActivityKit

struct TestMetadata: AlarmMetadata {}

// Runs when the user taps Stop on the lock screen / Dynamic Island.
// If "Last Stop" updates in the app, the intent ran, so you can gate dismissal on your own logic.
struct StopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop alarm"
    init() {}
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(Date().formatted(date: .omitted, time: .standard), forKey: "lastStop")
        return .result()
    }
}

// Secondary button that opens the app (this is how a "Scan to dismiss" button would work).
struct OpenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open app"
    static let openAppWhenRun = true
    init() {}
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(Date().formatted(date: .omitted, time: .standard), forKey: "lastOpen")
        return .result()
    }
}

@main
struct AlarmKitTestApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var log: [String] = []
    @State private var delay: Double = 60
    @AppStorage("lastStop") private var lastStop = "never"
    @AppStorage("lastOpen") private var lastOpen = "never"

    var body: some View {
        VStack(spacing: 20) {
            Text("AlarmKit Test").font(.largeTitle.bold())
            Stepper("Delay: \(Int(delay)) s", value: $delay, in: 15...600, step: 15)
            Button("Schedule alarm") { Task { await schedule() } }
                .buttonStyle(.borderedProminent)
            Button("Cancel all alarms") { cancelAll() }
            Text("Last Stop intent: \(lastStop)")
            Text("Last Open intent: \(lastOpen)")
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(log.indices, id: \.self) { Text(log[$0]).font(.footnote.monospaced()) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    func schedule() async {
        do {
            let manager = AlarmManager.shared
            let auth = try await manager.requestAuthorization()
            guard auth == .authorized else { log.append("Auth: \(auth)"); return }

            let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
            let open = AlarmButton(text: "Scan", textColor: .white, systemImageName: "qrcode.viewfinder")
            let alert = AlarmPresentation.Alert(
                title: "Wake up",
                stopButton: stop,
                secondaryButton: open,
                secondaryButtonBehavior: .custom
            )
            let attributes = AlarmAttributes(
                presentation: AlarmPresentation(alert: alert),
                metadata: TestMetadata(),
                tintColor: .orange
            )
            let fire = Date().addingTimeInterval(delay)
            let config = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(fire),
                attributes: attributes,
                stopIntent: StopIntent(),
                secondaryIntent: OpenIntent()
            )
            let id = UUID()
            _ = try await manager.schedule(id: id, configuration: config)
            log.append("Scheduled \(id.uuidString.prefix(8)) for \(fire.formatted(date: .omitted, time: .standard))")
        } catch {
            log.append("Error: \(error)")
        }
    }

    func cancelAll() {
        do {
            for alarm in try AlarmManager.shared.alarms { try AlarmManager.shared.cancel(id: alarm.id) }
            log.append("Cancelled all")
        } catch { log.append("Error: \(error)") }
    }
}
