import AVFoundation
import Foundation

struct AlarmSound: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
    /// File name inside Library/Sounds, or nil for the system alarm sound.
    let fileName: String?
    var isCustom: Bool { id.hasPrefix(SoundLibrary.customPrefix) }
}

/// Built-in and imported alarm sounds. AlarmKit plays sounds by file name from Library/Sounds,
/// and the in-app ringing player uses the same files.
@MainActor
enum SoundLibrary {
    nonisolated static let defaultSoundID = "sunrise"
    nonisolated static let systemSoundID = "system"
    nonisolated static let customPrefix = "custom-"
    /// AlarmKit, like notification sounds, plays at most 30 seconds.
    nonisolated static let maxImportSeconds = 30.0

    private static let customNamesKey = "sounds.customNames"
    private static let builtInVersion = 1

    static let builtIns: [AlarmSound] = [
        AlarmSound(id: "sunrise", name: "Sunrise", detail: "A warm chord that climbs", symbol: "sunrise", fileName: "pow-sunrise-v1.wav"),
        AlarmSound(id: "meadow", name: "Meadow", detail: "Birdsong at first light", symbol: "bird", fileName: "pow-meadow-v1.wav"),
        AlarmSound(id: "bells", name: "Bells", detail: "Soft tubular bells", symbol: "bell", fileName: "pow-bells-v1.wav"),
        AlarmSound(id: "glass", name: "Glass Harp", detail: "Plucked, bright and clear", symbol: "music.note", fileName: "pow-glass-v1.wav"),
        AlarmSound(id: "pulse", name: "Pulse", detail: "The classic beep, beep", symbol: "waveform", fileName: "pow-pulse-v1.wav"),
        AlarmSound(id: systemSoundID, name: "System Alarm", detail: "The standard iOS alarm", symbol: "iphone", fileName: nil),
    ]

    static var soundsDirectory: URL {
        URL.libraryDirectory.appending(path: "Sounds", directoryHint: .isDirectory)
    }

    static func url(for sound: AlarmSound) -> URL? {
        sound.fileName.map { soundsDirectory.appending(path: $0) }
    }

    static func all() -> [AlarmSound] { builtIns + customs() }

    static func sound(id: String) -> AlarmSound {
        all().first { $0.id == id } ?? builtIns[0]
    }

    // MARK: Built-ins

    /// Writes any missing built-in sounds. Rendering happens off the main actor.
    static func installBuiltIns() async {
        let directory = soundsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for sound in builtIns {
            guard let fileName = sound.fileName else { continue }
            let url = directory.appending(path: fileName)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { continue }
            let id = sound.id
            let data = await Task.detached(priority: .utility) { SoundSynth.render(id) }.value
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: Imported sounds

    static func customs() -> [AlarmSound] {
        let names = UserDefaults.standard.dictionary(forKey: customNamesKey) as? [String: String] ?? [:]
        return names
            .filter { FileManager.default.fileExists(atPath: soundsDirectory.appending(path: $0.key).path(percentEncoded: false)) }
            .sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
            .map { fileName, name in
                AlarmSound(id: customPrefix + fileName, name: name, detail: "Imported", symbol: "music.note.list", fileName: fileName)
            }
    }

    /// Copies an audio file into Library/Sounds as 16-bit PCM CAF, trimmed to 30 seconds with a short fade.
    static func importSound(from source: URL) async throws -> AlarmSound {
        let name = source.deletingPathExtension().lastPathComponent
        let fileName = "\(customPrefix)\(UUID().uuidString).caf"
        let destination = soundsDirectory.appending(path: fileName)
        try? FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
        try await Task.detached(priority: .userInitiated) {
            try AudioImporter.convert(source, to: destination, maxSeconds: maxImportSeconds)
        }.value
        var names = UserDefaults.standard.dictionary(forKey: customNamesKey) as? [String: String] ?? [:]
        names[fileName] = name
        UserDefaults.standard.set(names, forKey: customNamesKey)
        return AlarmSound(id: customPrefix + fileName, name: name, detail: "Imported", symbol: "music.note.list", fileName: fileName)
    }

    static func delete(_ sound: AlarmSound) {
        guard sound.isCustom, let fileName = sound.fileName else { return }
        try? FileManager.default.removeItem(at: soundsDirectory.appending(path: fileName))
        var names = UserDefaults.standard.dictionary(forKey: customNamesKey) as? [String: String] ?? [:]
        names[fileName] = nil
        UserDefaults.standard.set(names, forKey: customNamesKey)
    }
}

enum AudioImporter {
    enum ImportError: LocalizedError {
        case unreadable
        var errorDescription: String? { "That file couldn't be read as audio." }
    }

    static func convert(_ source: URL, to destination: URL, maxSeconds: Double) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let frames = AVAudioFrameCount(min(Double(input.length), maxSeconds * format.sampleRate))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw ImportError.unreadable
        }
        try input.read(into: buffer, frameCount: frames)

        // Fade the last half second so a trimmed song doesn't cut off with a click.
        if let channels = buffer.floatChannelData {
            let length = Int(buffer.frameLength)
            let fade = min(length, Int(0.5 * format.sampleRate))
            for channel in 0..<Int(format.channelCount) {
                for i in 0..<fade {
                    channels[channel][length - fade + i] *= Float(fade - i) / Float(fade)
                }
            }
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let output = try AVAudioFile(forWriting: destination, settings: settings,
                                     commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        try output.write(from: buffer)
    }
}
