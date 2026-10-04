import SwiftData
import SwiftUI

/// 02b Stop method (night): how this alarm gets turned off, and which code or tag.
struct StopMethodView: View {
    @Binding var method: StopMethod
    @Binding var codeID: UUID?

    @Query(sort: \WakeCode.createdAt) private var codes: [WakeCode]
    @State private var registering: StopMethod?
    @State private var testing: WakeCode?

    var body: some View {
        Form {
            Section {
                Text("Pick something you have to get out of bed to reach. The alarm only stops when you scan or tap it.")
                    .font(.sora(.body))
                    .foregroundStyle(Theme.inkSecondary)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }
            .listRowBackground(Color.clear)

            Section {
                ForEach(StopMethod.allCases) { option in
                    Button {
                        select(option)
                    } label: {
                        HStack(spacing: 14) {
                            IconTile(systemImage: option.symbol, highlighted: option == method)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).foregroundStyle(Theme.ink)
                                Text(option.subtitle)
                                    .font(.sora(.footnote))
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer(minLength: 8)
                            if option == method {
                                Image(systemName: "checkmark")
                                    .font(.sora(.body, .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == method ? .isSelected : [])
                }
            }
            .skyRowBackground()

            Section {
                ForEach(codesOfKind) { code in
                    Button {
                        codeID = code.id
                    } label: {
                        HStack {
                            Text(code.name).foregroundStyle(Theme.ink)
                            Spacer()
                            if code.id == codeID {
                                Image(systemName: "checkmark")
                                    .font(.sora(.body, .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(code.id == codeID ? .isSelected : [])
                }
                if let selected, method == .nfc {
                    LabeledContent("Status") {
                        TagStatus(isConfirmed: selected.isConfirmed)
                    }
                }
                Button(codesOfKind.isEmpty ? "Register a \(method.noun)" : "Register a different \(method.noun)") {
                    registering = method
                }
                .foregroundStyle(Theme.accent)
            } header: {
                SectionHeader(method == .nfc ? "Your tag" : "Your \(method.noun)")
            } footer: {
                if method == .nfc {
                    SectionFooter("Tags work through a Shortcuts automation. Registering walks you through it.")
                }
            }
            .skyRowBackground()
        }
        .scrollContentBackground(.hidden)
        .background { SkyView(style: .night) }
        .navigationTitle("Stop Method")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let selected {
                AccentButton(title: "Test \(method.noun)") { testing = selected }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .sheet(item: $registering) { kind in
            RegisterCodeView(kind: kind) { code in
                method = kind
                codeID = code.id
            }
        }
        .fullScreenCover(item: $testing) { code in
            CodeTestView(code: code)
        }
        .sensoryFeedback(.selection, trigger: method)
    }

    private var codesOfKind: [WakeCode] { codes.filter { $0.kind == method } }

    private var selected: WakeCode? { codesOfKind.first { $0.id == codeID } }

    private func select(_ option: StopMethod) {
        method = option
        if !codesOfKind.contains(where: { $0.id == codeID }) {
            codeID = codesOfKind.first?.id
        }
    }
}

struct TagStatus: View {
    let isConfirmed: Bool

    var body: some View {
        if isConfirmed {
            Label("Registered", systemImage: "checkmark")
                .foregroundStyle(Theme.success)
        } else {
            Label("Not tested yet", systemImage: "exclamationmark.circle")
                .foregroundStyle(Theme.accent)
        }
    }
}
