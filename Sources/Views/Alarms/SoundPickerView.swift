import SwiftUI
import UniformTypeIdentifiers

/// Built-in sounds, the system alarm, and the user's own imported sounds. Tapping a row previews it.
struct SoundPickerView: View {
    @Binding var selection: String

    @State private var customs: [AlarmSound] = []
    @State private var isImporting = false
    @State private var isConverting = false
    @State private var importError: String?

    var body: some View {
        Form {
            Section("Sounds") {
                ForEach(SoundLibrary.builtIns) { sound in row(sound) }
            }
            .skyRowBackground()

            Section {
                ForEach(customs) { sound in row(sound) }
                    .onDelete(perform: deleteCustoms)
                Button {
                    isImporting = true
                } label: {
                    HStack {
                        Label("Import from Files", systemImage: "square.and.arrow.down")
                        if isConverting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .foregroundStyle(Theme.accent)
                .disabled(isConverting)
            } header: {
                Text("Your sounds")
            } footer: {
                Text("Any song or recording works. Alarms play the first 30 seconds, on repeat.")
            }
            .skyRowBackground()
        }
        .scrollContentBackground(.hidden)
        .background { SkyView(style: .night) }
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { importSound(url) }
        }
        .alert("Couldn't import", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .onAppear { customs = SoundLibrary.customs() }
        .onDisappear { RingTone.shared.stopPreview() }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func row(_ sound: AlarmSound) -> some View {
        Button {
            selection = sound.id
            RingTone.shared.preview(soundID: sound.id)
        } label: {
            HStack(spacing: 14) {
                IconTile(systemImage: sound.symbol, highlighted: sound.id == selection, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sound.name).foregroundStyle(Theme.ink)
                    Text(sound.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 8)
                if sound.id == selection {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(sound.id == selection ? .isSelected : [])
        .accessibilityHint("Plays a preview")
    }

    private func importSound(_ url: URL) {
        isConverting = true
        Task {
            do {
                let sound = try await SoundLibrary.importSound(from: url)
                customs = SoundLibrary.customs()
                selection = sound.id
            } catch {
                importError = error.localizedDescription
            }
            isConverting = false
        }
    }

    private func deleteCustoms(at offsets: IndexSet) {
        for index in offsets {
            let sound = customs[index]
            if selection == sound.id { selection = SoundLibrary.defaultSoundID }
            SoundLibrary.delete(sound)
        }
        customs = SoundLibrary.customs()
    }
}
