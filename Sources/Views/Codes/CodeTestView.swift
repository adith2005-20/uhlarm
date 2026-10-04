import SwiftUI

/// Try a registered code or tag without an alarm ringing.
struct CodeTestView: View {
    let code: WakeCode

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if code.kind == .nfc {
            TagTester(tagName: code.name, successSubtitle: "\(code.name) works") {
                dismiss()
            } onClose: {
                dismiss()
            }
        } else {
            ScanView(
                instruction: "Scan \(code.name.lowercasingFirstLetter)",
                symbologies: code.kind.symbologies,
                evaluate: { code.payloadHash == CodeHash.hash($0) },
                onMatched: { _ in },
                onFinished: { dismiss() },
                onClose: { dismiss() }
            )
        }
    }
}

/// The NFC screen fed by the Shortcuts automation, for testing a tag.
struct TagTester: View {
    let tagName: String
    var successSubtitle: String
    let onSuccess: () -> Void
    let onClose: () -> Void

    @State private var event: TagEvent?

    var body: some View {
        NFCView(
            tagName: tagName,
            event: event,
            closeSymbol: "xmark",
            successTitle: "Tag found",
            successSubtitle: successSubtitle,
            onClose: onClose,
            onSuccessFinished: onSuccess
        )
        .onChange(of: AppModel.shared.lastTag) { _, scan in
            guard let scan else { return }
            event = TagEvent(name: scan.name, matched: TagName.matches(tagName, scan.name))
        }
    }
}
