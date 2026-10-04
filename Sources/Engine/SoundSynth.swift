import Foundation

/// Renders the built-in alarm sounds. No audio assets ship with the app: each sound is generated once
/// on first launch and written to Library/Sounds, where both AlarmKit and the in-app player find it.
enum SoundSynth {
    static let sampleRate = 44_100.0

    static func render(_ id: String) -> Data {
        let samples: [Float]
        switch id {
        case "meadow": samples = meadow()
        case "bells": samples = bells()
        case "glass": samples = glass()
        case "pulse": samples = pulse()
        default: samples = sunrise()
        }
        return wav(normalized(samples))
    }

    // MARK: Voices

    /// A warm major arpeggio that climbs and slowly gets brighter.
    private static func sunrise() -> [Float] {
        var out = buffer(seconds: 12)
        let chord: [Double] = [523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0]
        var t = 0.0
        var cycle = 0
        while t < 11 {
            let level = 0.45 + 0.55 * min(1, Double(cycle) / 5)
            for (i, freq) in chord.enumerated() {
                add(&out, at: t + Double(i) * 0.16, duration: 1.6, amplitude: level * 0.5) { time in
                    let env = exp(-time * 2.6) * min(1, time * 60)
                    return env * (sin(2 * .pi * freq * time) + 0.25 * sin(4 * .pi * freq * time))
                }
            }
            t += 1.8
            cycle += 1
        }
        return out
    }

    /// Bird-like chirps: quick upward sweeps in little phrases.
    private static func meadow() -> [Float] {
        var out = buffer(seconds: 10)
        var random = SeededRandom(seed: 7)
        var t = 0.2
        while t < 9.4 {
            let notes = 2 + Int(random.next() * 4)
            let base = 2_400 + random.next() * 1_400
            for n in 0..<notes {
                let start = t + Double(n) * 0.11
                let length = 0.06 + random.next() * 0.05
                let sweep = 900 + random.next() * 900
                add(&out, at: start, duration: length, amplitude: 0.5) { time in
                    let p = time / length
                    let env = sin(.pi * p)
                    // Frequency rises linearly from base to base + sweep across the chirp.
                    let phase = 2 * .pi * (base * time + sweep * time * time / (2 * length))
                    return env * env * sin(phase) * (0.8 + 0.2 * sin(2 * .pi * 38 * time))
                }
            }
            t += Double(notes) * 0.11 + 0.35 + random.next() * 0.7
        }
        return out
    }

    /// Soft tubular bells with inharmonic partials.
    private static func bells() -> [Float] {
        var out = buffer(seconds: 12)
        let melody: [Double] = [392.0, 587.33, 493.88, 783.99]
        let partials: [(Double, Double)] = [(1, 1), (2.76, 0.45), (5.4, 0.22), (8.93, 0.1)]
        var t = 0.0
        while t < 10.5 {
            for (i, freq) in melody.enumerated() {
                add(&out, at: t + Double(i) * 0.7, duration: 3.2, amplitude: 0.45) { time in
                    var v = 0.0
                    for (ratio, gain) in partials {
                        v += gain * exp(-time * (1.1 + ratio * 0.35)) * sin(2 * .pi * freq * ratio * time)
                    }
                    return v * min(1, time * 200)
                }
            }
            t += 3.4
        }
        return out
    }

    /// Plucked glass harp: a rising pentatonic pattern (Karplus–Strong strings).
    private static func glass() -> [Float] {
        var out = buffer(seconds: 10)
        let scale: [Double] = [587.33, 659.25, 739.99, 880.0, 987.77, 1174.66, 1318.51, 1479.98]
        var random = SeededRandom(seed: 3)
        var t = 0.0
        var step = 0
        while t < 9.2 {
            let freq = scale[(step * 3) % scale.count]
            let pluck = karplusStrong(frequency: freq, seconds: 1.8, random: &random)
            mix(&out, pluck, at: t, gain: 0.55)
            t += step % 4 == 3 ? 0.62 : 0.26
            step += 1
        }
        return out
    }

    /// The classic: four quick beeps, a rest, repeat.
    private static func pulse() -> [Float] {
        var out = buffer(seconds: 8)
        var t = 0.0
        while t < 7.5 {
            for i in 0..<4 {
                add(&out, at: t + Double(i) * 0.14, duration: 0.09, amplitude: 0.5) { time in
                    let env = min(1, time * 400) * min(1, (0.09 - time) * 400)
                    let s = sin(2 * .pi * 1_046.5 * time)
                    return env * (s + 0.3 * sin(2 * .pi * 2_093 * time))
                }
            }
            t += 1.0
        }
        return out
    }

    // MARK: Building blocks

    private static func buffer(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * sampleRate))
    }

    private static func add(_ out: inout [Float], at start: Double, duration: Double, amplitude: Double,
                            _ voice: (Double) -> Double) {
        let first = Int(start * sampleRate)
        let count = Int(duration * sampleRate)
        guard first < out.count else { return }
        for i in 0..<min(count, out.count - first) {
            out[first + i] += Float(amplitude * voice(Double(i) / sampleRate))
        }
    }

    private static func mix(_ out: inout [Float], _ samples: [Float], at start: Double, gain: Float) {
        let first = Int(start * sampleRate)
        guard first < out.count else { return }
        for i in 0..<min(samples.count, out.count - first) {
            out[first + i] += samples[i] * gain
        }
    }

    private static func karplusStrong(frequency: Double, seconds: Double, random: inout SeededRandom) -> [Float] {
        let period = max(2, Int(sampleRate / frequency))
        var ring = (0..<period).map { _ in Float(random.next() * 2 - 1) }
        var out = [Float](repeating: 0, count: Int(seconds * sampleRate))
        var index = 0
        for i in 0..<out.count {
            let next = (index + 1) % period
            let value = 0.4985 * (ring[index] + ring[next])
            out[i] = ring[index]
            ring[index] = value
            index = next
        }
        return out
    }

    private static func normalized(_ samples: [Float]) -> [Float] {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0 else { return samples }
        let gain = 0.85 / peak
        let fade = Int(0.05 * sampleRate)
        return samples.enumerated().map { i, s in
            let edge = min(1, Float(min(i, samples.count - 1 - i)) / Float(fade))
            return s * gain * edge
        }
    }

    /// 16-bit mono PCM WAV.
    private static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        let dataSize = UInt32(samples.count * 2)
        func append32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate) * 2)
        append16(2)
        append16(16)
        data.append(contentsOf: Array("data".utf8))
        append32(dataSize)
        data.reserveCapacity(data.count + samples.count * 2)
        for s in samples {
            append16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32_767)))
        }
        return data
    }
}

/// Deterministic randomness so the generated sounds are identical on every device.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }
}
