import SwiftData
import SwiftUI

/// Everything registered to turn alarms off.
struct CodesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WakeCode.createdAt) private var codes: [WakeCode]
    @Query private var alarms: [AlarmItem]

    @State private var registering: StopMethod?
    @State private var testing: WakeCode?
    @State private var deleting: WakeCode?
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("The things that turn your alarms off. Keep them where you have to get out of bed to reach them.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.horizontal, 4)

                    if codes.isEmpty {
                        emptyState
                    } else {
                        GlassEffectContainer(spacing: 6) {
                            VStack(spacing: 12) {
                                ForEach(codes) { code in
                                    CodeCard(code: code, usage: usage(of: code))
                                        .onTapGesture { testing = code }
                                        .contextMenu {
                                            Button("Test", systemImage: "checkmark.circle") { testing = code }
                                            Button("Delete", systemImage: "trash", role: .destructive) { askDelete(code) }
                                        }
                                        .accessibilityAction(named: "Test") { testing = code }
                                        .accessibilityAction(named: "Delete") { askDelete(code) }
                                        .transition(.blurReplace)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .animation(.spring(duration: 0.4, bounce: 0.15), value: codes.map(\.id))
            }
            .background { SkyView(style: .night) }
            .navigationTitle("Codes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { addMenu }
            }
            .sheet(item: $registering) { kind in
                RegisterCodeView(kind: kind)
            }
            .fullScreenCover(item: $testing) { code in
                CodeTestView(code: code)
            }
            .confirmationDialog(
                "Delete \(deleting?.name ?? "")?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible,
                presenting: deleting
            ) { code in
                Button("Delete", role: .destructive) { delete(code) }
            } message: { code in
                let count = usage(of: code)
                Text(count == 0 ? "No alarms use it." : "\(count) alarm\(count == 1 ? "" : "s") will need a new code. Until then they fall back to the emergency unlock.")
            }
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(StopMethod.allCases) { kind in
                Button(kind.title, systemImage: kind.symbol) { registering = kind }
            }
        } label: {
            Label("Add Code", systemImage: "plus")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                ForEach(StopMethod.allCases) { kind in
                    Image(systemName: kind.symbol)
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular, in: .circle)
                }
            }
            Text("Nothing registered yet")
                .font(.title2.weight(.semibold))
            Text("Scan a QR code on the kitchen wall, the barcode on your coffee, or set up an NFC sticker on the bathroom mirror.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.inkSecondary)
            Menu {
                ForEach(StopMethod.allCases) { kind in
                    Button(kind.title, systemImage: kind.symbol) { registering = kind }
                }
            } label: {
                Label("Add Code", systemImage: "plus")
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func askDelete(_ code: WakeCode) {
        deleting = code
        isConfirmingDelete = true
    }

    private func usage(of code: WakeCode) -> Int {
        alarms.filter { $0.codeID == code.id }.count
    }

    private func delete(_ code: WakeCode) {
        let affected = alarms.filter { $0.codeID == code.id }
        for alarm in affected { alarm.codeID = nil }
        context.delete(code)
        try? context.save()
        deleting = nil
    }
}

private struct CodeCard: View {
    let code: WakeCode
    let usage: Int

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: code.kind.symbol, highlighted: true, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(code.name)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                if code.kind == .nfc {
                    TagStatus(isConfirmed: code.isConfirmed)
                        .font(.subheadline)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkTertiary)
                .accessibilityHidden(true)
        }
        .padding(18)
        .contentShape(.rect(cornerRadius: 28))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens a test")
    }

    private var detail: String {
        let uses = usage == 0 ? "Not used yet" : "Used by \(usage) alarm\(usage == 1 ? "" : "s")"
        return "\(code.kind.title) · \(uses)"
    }
}
