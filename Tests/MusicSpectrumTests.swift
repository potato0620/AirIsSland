import Foundation

@main struct MusicSpectrumTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
    static func main() {
        var state = MusicSpectrumState()
        let song = UUID()
        state.update(enabled: false, playing: true, bundleIdentifier: "player.a", visible: true)
        check(state.request == nil, "Disabled spectrum created a capture lease")
        state.update(enabled: true, playing: true, bundleIdentifier: "player.a", trackIdentifier: song, visible: false)
        check(state.request == nil, "Hidden spectrum created a capture lease")
        state.update(enabled: true, playing: true, bundleIdentifier: "player.a", trackIdentifier: song, visible: true)
        let first = state.request!
        state.update(enabled: true, playing: true, bundleIdentifier: "player.a", trackIdentifier: song, visible: true)
        check(state.request == first, "Repeated playback updates restarted capture")
        check(state.receive([1, 0.8, 0.6, 0.4, 0.2, 0.12], for: first), "Current frame rejected")
        state.update(enabled: true, playing: true, bundleIdentifier: "player.b", trackIdentifier: song, visible: true)
        check(state.request != first && state.levels == MusicSpectrumState.quiet, "Switching players retained old levels")
        check(!state.receive(Array(repeating: 1, count: 6), for: first), "Old player overwrote current spectrum")
        let second = state.request!
        state.update(enabled: true, playing: true, bundleIdentifier: "player.b", trackIdentifier: UUID(), visible: true)
        check(!state.receive(Array(repeating: 1, count: 6), for: second), "Queued old-song frame overwrote new song")
        let third = state.request!
        check(!state.receive([1], for: third), "Malformed band count accepted")
        check(state.receive([.nan, .infinity, -1, 2, 0.5, 0.12], for: third), "Current sanitized frame rejected")
        check(state.levels == [0.12, 0.12, 0.12, 1, 0.5, 0.12], "Invalid levels escaped normalization")
        state.update(enabled: true, playing: false, bundleIdentifier: "player.b", visible: true)
        check(state.request == nil && state.levels == MusicSpectrumState.quiet, "Pause did not withdraw capture")
        check(!state.receive(Array(repeating: 1, count: 6), for: third), "Stopped lease remained writable")
        state.update(enabled: true, playing: true, bundleIdentifier: "", visible: true)
        check(state.request == nil, "Unknown source enabled global capture")

        for rate in [44100.0, 48000.0] {
            for (band, frequency) in [80.0, 250, 700, 1700, 4000, 10000].enumerated() {
                let analyzer = MusicSpectrumAnalyzer()
                var latest = MusicSpectrumState.quiet
                var frames = 0
                for block in 0..<120 {
                    let samples = (0..<256).map { Float(0.1 * sin(2 * .pi * frequency * Double(block * 256 + $0) / rate)) }
                    samples.withUnsafeBufferPointer {
                        analyzer.consume($0, channels: 1, sampleRate: rate, now: Double(block * 256) / rate) { latest = $0; frames += 1 }
                    }
                }
                check(latest.indices.max(by: { latest[$0] < latest[$1] }) == band, "Sine \(frequency) Hz mapped to wrong band: \(latest)")
                check(latest[band] > 0.5 && latest.allSatisfy { $0.isFinite && (0.12...1).contains($0) }, "Invalid spectrum amplitude")
                check(frames > 10 && Double(frames) <= 30 * (120 * 256 / rate) + 1, "Frame output was unbounded")
                let loud = latest[band]
                let silence = [Float](repeating: 0, count: 256)
                for block in 120..<300 {
                    silence.withUnsafeBufferPointer {
                        analyzer.consume($0, channels: 1, sampleRate: rate, now: Double(block * 256) / rate) { latest = $0 }
                    }
                }
                check(latest[band] < loud && latest.allSatisfy { $0 < 0.14 }, "Silence froze a loud spectrum frame")
            }
        }
        print("PASS: six FFT bands at 44.1/48 kHz, signal/silence envelope, bounded frame cadence, source/song identity, enable/visibility/pause/unknown-source policy and invalid-frame rejection")
    }
}
