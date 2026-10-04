import SwiftUI

/// What the alarm engine did, plus a throwaway test alarm for trying the Stop → re-ring loop.
struct DiagnosticsView: View {
    @State private var entries: [String] = []
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                Button("Ring a test alarm in 10 seconds", systemImage: "alarm") {
                    Task {
                        await RingEngine.shared.ringTestAlarm(in: 10)
                        refresh()
                    }
                }
                .foregroundStyle(Theme.accent)
                Button("Stop test alarms", systemImage: "stop.circle", role: .destructive) {
                    RingEngine.shared.stopTestAlarms()
                    refresh()
                }
            } header: {
                SectionHeader("Test")
            } footer: {
                SectionFooter("Lock your phone, let the test alarm ring and tap Silence \(Int(RingEngine.silenceDuration)) sec. It should ring again \(Int(RingEngine.silenceDuration)) seconds later. Stop test alarms ends the loop.")
            }
            .skyRowBackground()

            Section {
                if entries.isEmpty {
                    Text("Nothing logged yet")
                        .foregroundStyle(Theme.inkSecondary)
                }
                ForEach(Array(entries.enumerated().reversed()), id: \.offset) { _, entry in
                    Text(entry)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            } header: {
                SectionHeader("Log")
            }
            .skyRowBackground()
        }
        .scrollContentBackground(.hidden)
        .background { SkyView(style: .night) }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Copy Log", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = entries.joined(separator: "\n")
                        copied.toggle()
                    }
                    Button("Clear Log", systemImage: "trash", role: .destructive) {
                        DiagnosticsLog.clear()
                        refresh()
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .sensoryFeedback(.success, trigger: copied)
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refresh() {
        entries = DiagnosticsLog.entries
    }
}
