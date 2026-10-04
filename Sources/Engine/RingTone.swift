import AVFoundation

/// Plays the alarm sound inside the app while the user is proving they're awake.
/// The `.playback` category keeps it audible in Silent mode.
@MainActor
final class RingTone {
    static let shared = RingTone()

    private var player: AVAudioPlayer?
    private var preview: AVAudioPlayer?
    private var previewTask: Task<Void, Never>?

    func start(soundID: String, gradual: Bool) {
        guard player == nil else { return }
        stopPreview()
        activateSession()
        guard let next = makePlayer(for: soundID) else { return }
        next.numberOfLoops = -1
        next.volume = gradual ? 0.12 : 1
        next.play()
        if gradual { next.setVolume(1, fadeDuration: 60) }
        player = next
    }

    /// The lost-code fallback keeps ringing, but quieter.
    func soften() {
        player?.setVolume(0.3, fadeDuration: 2)
    }

    func stop() {
        player?.stop()
        player = nil
        deactivateSession()
    }

    /// Plays a few seconds of a sound in the picker.
    func preview(soundID: String) {
        stopPreview()
        guard player == nil else { return }
        activateSession()
        guard let next = makePlayer(for: soundID) else { return }
        next.volume = 0.8
        next.play()
        preview = next
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.preview?.setVolume(0, fadeDuration: 0.6)
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            self?.stopPreview()
        }
    }

    func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        preview?.stop()
        preview = nil
        if player == nil { deactivateSession() }
    }

    private func makePlayer(for soundID: String) -> AVAudioPlayer? {
        var sound = SoundLibrary.sound(id: soundID)
        // The system alarm sound isn't available to apps, so the app plays Pulse in its place.
        if sound.fileName == nil, let pulse = SoundLibrary.builtIns.first(where: { $0.id == "pulse" }) {
            sound = pulse
        }
        if let url = SoundLibrary.url(for: sound), let file = try? AVAudioPlayer(contentsOf: url) {
            return file
        }
        // Sounds not installed yet (first launch still rendering): render in place.
        return try? AVAudioPlayer(data: SoundSynth.render(sound.isCustom ? "sunrise" : sound.id))
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
