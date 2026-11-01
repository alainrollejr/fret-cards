import AVFoundation
import UIKit

/// Plays notes at sounding pitch (an octave below written pitch).
/// The plucked-string voice is a Karplus-Strong string run through a few body resonances.
final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 4)
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var samples: [String: [Float]] = [:]

    private init() {
        // Set the session up before touching the engine: activating it later changes the
        // hardware format, and iOS then stops the engine under us.
        // .playback keeps sound on when the ring/silent switch is set to silent.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)

        let bands: [(AVAudioUnitEQFilterType, Float, Float, Float)] = [
            (.parametric, 105, 1.0, 6), // body resonance
            (.parametric, 220, 0.9, 3),
            (.parametric, 2600, 1.5, 2.5), // a little bite
            (.lowPass, 6000, 1.0, 0),
        ]
        for (band, spec) in zip(eq.bands, bands) {
            band.filterType = spec.0
            band.frequency = spec.1
            band.bandwidth = spec.2
            band.gain = spec.3
            band.bypass = false
        }
        // The EQ has a single input bus, so the players meet in a mixer first.
        let voices = AVAudioMixerNode()
        engine.attach(voices)
        engine.attach(eq)
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: voices, fromBus: 0, toBus: voices.nextAvailableInputBus, format: format)
            players.append(p)
        }
        engine.connect(voices, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    private func start() -> Bool {
        if engine.isRunning { return true }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        } catch {
            return false
        }
        return engine.isRunning
    }

    func play(writtenMidi: Int, mode: SoundMode) {
        guard mode != .off, start() else { return }
        let key = "\(mode.rawValue)\(writtenMidi)"
        let buffer: AVAudioPCMBuffer
        if let cached = cache[key] {
            buffer = cached
        } else {
            buffer = makeBuffer(note(writtenMidi, mode))
            cache[key] = buffer
        }
        schedule(buffer)
    }

    /// Strums down, up, down and/or plays a low-to-high arpeggio. A new pluck on a string
    /// stops that string's previous note, as on a real guitar.
    func playChord(_ v: Voicing, instrument: Instrument, mode: SoundMode, style: ChordPlayStyle) {
        guard mode != .off, start() else { return }
        let key = "\(mode.rawValue)|\(style.rawValue)|\(v.tab)"
        if let cached = cache[key] {
            players.forEach { $0.stop() }
            return schedule(cached)
        }
        let strings = v.frets.indices.reversed().filter { v.frets[$0] != nil } // low to high
        var hits: [(s: Int, t: Double, level: Float)] = []
        var t = 0.0
        if style != .arp {
            for (i, s) in strings.enumerated() { hits.append((s, t + Double(i) * 0.028, 1)) }
            t += 0.55
            for (i, s) in strings.suffix(4).reversed().enumerated() { hits.append((s, t + Double(i) * 0.022, 0.65)) }
            t += 0.4
            for (i, s) in strings.enumerated() { hits.append((s, t + Double(i) * 0.03, 1)) }
            t += 1.3
        }
        if style != .strum {
            for (i, s) in strings.enumerated() { hits.append((s, t + Double(i) * 0.26, 1.5)) }
        }

        let sr = format.sampleRate
        let gain = 1 / Float(max(3, strings.count)).squareRoot()
        let notes = Dictionary(uniqueKeysWithValues: strings.map { ($0, note(instrument.open[$0] + v.frets[$0]!, mode)) })
        let end = hits.map { Int($0.t * sr) + notes[$0.s]!.count }.max() ?? 0
        var out = [Float](repeating: 0, count: end)
        let fade = Int(sr * 0.015)
        for (i, h) in hits.enumerated() {
            let src = notes[h.s]!
            let start = Int(h.t * sr)
            let cut = hits[(i + 1)...].first { $0.s == h.s }.map { Int($0.t * sr) - start } ?? src.count
            for j in 0..<min(src.count, cut + fade) {
                let ramp: Float = j > cut ? Float(cut + fade - j) / Float(fade) : 1
                out[start + j] += src[j] * h.level * gain * ramp
            }
        }
        let peak = out.map(abs).max() ?? 0
        if peak > 0.9 { out = out.map { $0 * 0.9 / peak } }
        let buffer = makeBuffer(out)
        cache[key] = buffer
        players.forEach { $0.stop() }
        schedule(buffer)
    }

    private func note(_ writtenMidi: Int, _ mode: SoundMode) -> [Float] {
        let key = "\(mode.rawValue)\(writtenMidi)"
        if let cached = samples[key] { return cached }
        let freq = 440 * pow(2, Double(writtenMidi - 12 - 69) / 12)
        let y = mode == .guitar ? pluck(freq) : tone(freq)
        samples[key] = y
        return y
    }

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        // play() raises an uncatchable exception if the engine stopped in the meantime.
        guard engine.isRunning else { return }
        player.play()
    }

    private func makeBuffer(_ y: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(y.count))!
        buffer.frameLength = AVAudioFrameCount(y.count)
        y.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: y.count) }
        return buffer
    }

    private func pluck(_ freq: Double) -> [Float] {
        let sr = format.sampleRate
        let len = Int(sr * 3)
        var y = [Float](repeating: 0, count: len)
        let period = sr / freq
        let n = Int(period - 0.5)
        let d = Float(period - 0.5 - Double(n))
        let c = (1 - d) / (1 + d) // allpass for the fractional delay, keeps it in tune

        // Excitation: softened noise with a notch from plucking near the bridge.
        var exc = [Float](repeating: 0, count: n)
        var s: Float = 0
        for i in 0..<n {
            s += 0.5 * (Float.random(in: -1...1) - s)
            exc[i] = s
        }
        let pp = max(1, Int((Double(n) * 0.13).rounded()))
        var ring = [Float](repeating: 0, count: n)
        for i in 0..<n { ring[i] = exc[i] - (i >= pp ? exc[i - pp] : 0) }
        let mean = ring.reduce(0, +) / Float(n)
        for i in 0..<n { ring[i] -= mean }

        let t60 = 2.6 * pow(110 / freq, 0.4)
        let damp = Float(pow(0.001, 1 / (t60 * freq)))
        var p = 0, last: Float = 0, apx: Float = 0, apy: Float = 0, peak: Float = 0
        for i in 0..<len {
            let v = ring[p]
            y[i] = v
            let lp = 0.5 * (v + last)
            last = v
            let ap = c * lp + apx - c * apy
            apx = lp
            apy = ap
            ring[p] = ap * damp
            p = p + 1 == n ? 0 : p + 1
            peak = max(peak, abs(v))
        }
        let fade = Int(sr * 0.25)
        let norm: Float = peak > 0 ? 0.7 / peak : 1
        for i in 0..<len {
            y[i] *= norm * (i > len - fade ? Float(len - i) / Float(fade) : 1)
        }
        return y
    }

    private func tone(_ freq: Double) -> [Float] {
        let sr = format.sampleRate
        let len = Int(sr * 1.3)
        var y = [Float](repeating: 0, count: len)
        for i in 0..<len {
            let t = Double(i) / sr
            let phase = (t * freq).truncatingRemainder(dividingBy: 1)
            let tri = 4 * abs(phase - 0.5) - 1
            let env = t < 0.01 ? t / 0.01 : exp(-(t - 0.01) * 5.8)
            y[i] = Float(0.35 * tri * env)
        }
        return y
    }
}

enum Haptics {
    static func tap(_ match: Bool) {
        UIImpactFeedbackGenerator(style: match ? .light : .rigid).impactOccurred()
    }

    static func result(_ ok: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(ok ? .success : .error)
    }
}
