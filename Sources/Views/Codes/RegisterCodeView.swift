import SwiftData
import SwiftUI

/// Registers a QR code, a barcode, or an NFC tag (via a Shortcuts automation).
struct RegisterCodeView: View {
    let kind: StopMethod
    var onSaved: (WakeCode) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var codes: [WakeCode]

    @State private var name = ""
    @State private var captured: ScannedCode?
    @State private var isScanning = false
    @State private var isTestingTag = false
    @State private var tagConfirmed = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(intro)
                        .foregroundStyle(Theme.inkSecondary)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }
                .listRowBackground(Color.clear)

                Section("Name") {
                    TextField(placeholder, text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                    if let nameProblem {
                        Text(nameProblem)
                            .font(.footnote)
                            .foregroundStyle(Theme.error)
                    }
                }
                .skyRowBackground()

                if kind == .nfc {
                    tagSections
                } else {
                    scanSection
                }
            }
            .scrollContentBackground(.hidden)
            .background { SkyView(style: .night) }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { save() }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.accentInk)
                        .disabled(!canSave)
                }
            }
            .fullScreenCover(isPresented: $isScanning) {
                ScanView(
                    instruction: "Point at your \(kind.noun)",
                    symbologies: kind.symbologies,
                    evaluate: { _ in true },
                    onMatched: { code in captured = code },
                    onFinished: { isScanning = false },
                    onClose: { isScanning = false }
                )
            }
            .fullScreenCover(isPresented: $isTestingTag) {
                TagTester(tagName: trimmedName, successSubtitle: "Your tag works") {
                    tagConfirmed = true
                    isTestingTag = false
                } onClose: {
                    isTestingTag = false
                }
            }
        }
        .tint(Theme.accent)
    }

    // MARK: QR / barcode

    private var scanSection: some View {
        Section {
            if let captured {
                LabeledContent {
                    Label("Captured", systemImage: "checkmark")
                        .foregroundStyle(Theme.success)
                } label: {
                    Label(kind == .qr ? "QR code" : readableSymbology(captured.symbology), systemImage: kind.symbol)
                        .labelStyle(AccentIconLabelStyle())
                }
                if let duplicate {
                    Text("This is already registered as “\(duplicate.name)”.")
                        .font(.footnote)
                        .foregroundStyle(Theme.error)
                }
                Button("Scan again", systemImage: "arrow.counterclockwise") { isScanning = true }
                    .foregroundStyle(Theme.accent)
            } else {
                Button {
                    isScanning = true
                } label: {
                    Label(kind == .qr ? "Scan the QR code" : "Scan the barcode", systemImage: kind.scanSymbol)
                }
                .foregroundStyle(Theme.accent)
            }
        } header: {
            Text(kind == .qr ? "Code" : "Barcode")
        } footer: {
            Text("Only a fingerprint of the code is stored, never what it says.")
        }
        .skyRowBackground()
    }

    // MARK: NFC

    @ViewBuilder
    private var tagSections: some View {
        Section {
            StepRow(number: 1, text: "Open Shortcuts and go to Automation. Tap New Automation, then NFC.")
            StepRow(number: 2, text: "Tap Scan and hold the top of your iPhone to the tag. Name it “\(displayName)”.")
            StepRow(number: 3, text: "Choose Run Immediately. Add the action Verify Wake Tag from Proof of Wake.")
            StepRow(number: 4, text: "Set Tag Name to “\(displayName)” and tap Done.")
            Button {
                if let url = URL(string: "shortcuts://") { openURL(url) }
            } label: {
                Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
            }
            .foregroundStyle(Theme.accent)
        } header: {
            Text("Set up the automation")
        } footer: {
            Text("iPhone reads the tag and tells the alarm, so it works without any special permissions. It can also open proofofwake://verify?tag=\(displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") if you write that to the tag instead.")
        }
        .skyRowBackground()

        Section("Status") {
            LabeledContent("Tag") {
                TagStatus(isConfirmed: tagConfirmed)
            }
            Button("Test tag", systemImage: "wave.3.right") { isTestingTag = true }
                .foregroundStyle(Theme.accent)
                .disabled(trimmedName.isEmpty)
        }
        .skyRowBackground()
    }

    // MARK: Logic

    private var title: String {
        switch kind {
        case .qr: "New QR Code"
        case .barcode: "New Barcode"
        case .nfc: "New NFC Tag"
        }
    }

    private var intro: String {
        switch kind {
        case .qr: "Use a QR code you can stick somewhere away from your bed. Any QR works: print one, or use one already on the wall."
        case .barcode: "Pick something that lives far from your bed, like the coffee bag in the kitchen or the toothpaste by the sink."
        case .nfc: "NFC stickers cost very little. Put one on the bathroom mirror or the kettle, then teach your iPhone what it is."
        }
    }

    private var placeholder: String {
        switch kind {
        case .qr: "Kitchen QR"
        case .barcode: "Coffee bag barcode"
        case .nfc: "Bathroom mirror"
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var displayName: String { trimmedName.isEmpty ? placeholder : trimmedName }

    private var nameProblem: String? {
        guard kind == .nfc, !trimmedName.isEmpty else { return nil }
        let taken = codes.contains { $0.kind == .nfc && TagName.matches($0.name, trimmedName) }
        return taken ? "Another tag already has this name. Tags are told apart by name." : nil
    }

    private var duplicate: WakeCode? {
        guard let captured else { return nil }
        let hash = CodeHash.hash(captured)
        return codes.first { $0.payloadHash == hash }
    }

    private var canSave: Bool {
        guard !trimmedName.isEmpty, nameProblem == nil else { return false }
        return kind == .nfc || (captured != nil && duplicate == nil)
    }

    private func save() {
        let code = WakeCode(
            name: trimmedName,
            kind: kind,
            payloadHash: captured.map(CodeHash.hash),
            symbology: captured?.symbology,
            isConfirmed: kind == .nfc ? tagConfirmed : true
        )
        context.insert(code)
        try? context.save()
        onSaved(code)
        dismiss()
    }

    private func readableSymbology(_ raw: String) -> String {
        let name = raw.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
        return name.isEmpty ? "Barcode" : name.uppercased()
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accentInk)
                .frame(width: 26, height: 26)
                .background(Theme.accent, in: .circle)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
    }
}
