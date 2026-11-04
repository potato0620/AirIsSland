import Accelerate
import Foundation

/// Reused FFT buffers, confined to the audio queue. No audio is saved or uploaded.
final class MusicSpectrumAnalyzer {
    private let count = 1024
    private let setup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))!
    private var samples = [Float](repeating: 0, count: 1024)
    private var window = [Float](repeating: 0, count: 1024)
    private var work = [Float](repeating: 0, count: 1024)
    private var real = [Float](repeating: 0, count: 512)
    private var imaginary = [Float](repeating: 0, count: 512)
    private var powers = [Float](repeating: 0, count: 512)
    private var filled = 0
    private var lastAnalysis: TimeInterval = -.infinity
    private var levels = MusicSpectrumState.quiet

    init() { vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM)) }
    deinit { vDSP_destroy_fftsetup(setup) }

    func consume(_ input: UnsafeBufferPointer<Float>, channels: Int, sampleRate: Double,
                 now: TimeInterval, emit: ([Double]) -> Void) {
        guard channels > 0, sampleRate.isFinite, sampleRate > 0 else { return }
        for frame in 0..<(input.count / channels) {
            var value: Float = 0
            for channel in 0..<channels { value += input[frame * channels + channel] / Float(channels) }
            samples[filled] = value.isFinite ? min(1, max(-1, value)) : 0
            filled += 1
            if filled == count {
                if now - lastAnalysis >= 1.0 / 30 {
                    let dt = lastAnalysis.isFinite ? min(0.25, max(0.001, now - lastAnalysis)) : 1.0 / 30
                    lastAnalysis = now
                    emit(analyze(sampleRate: sampleRate, elapsed: dt))
                }
                // 50% overlap keeps the analysis responsive without reallocating samples.
                for index in 0..<count / 2 { samples[index] = samples[index + count / 2] }
                filled = count / 2
            }
        }
    }

    private func analyze(sampleRate: Double, elapsed: TimeInterval) -> [Double] {
        vDSP_vmul(samples, 1, window, 1, &work, 1, vDSP_Length(count))
        real.withUnsafeMutableBufferPointer { r in
            imaginary.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                work.withUnsafeBufferPointer { buffer in
                    buffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: count / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(count / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, 10, FFTDirection(FFT_FORWARD))
                split.imagp[0] = 0 // The packed Nyquist component is not the DC amplitude.
                vDSP_zvmags(&split, 1, &powers, 1, vDSP_Length(count / 2))
            }
        }
        let edges: [Double] = [40, 160, 400, 1000, 2500, 6000, 20000]
        for band in 0..<MusicSpectrumState.barCount {
            let lower = max(1, Int(edges[band] * Double(count) / sampleRate))
            let upper = min(count / 2, max(lower + 1, Int(edges[band + 1] * Double(count) / sampleRate)))
            var peak: Float = 0
            if lower < upper { for bin in lower..<upper { peak = max(peak, powers[bin]) } }
            let amplitude = Double(sqrt(peak)) / Double(count)
            let db = 20 * log10(max(1e-8, amplitude))
            let target = max(0.12, min(1, (db + 65) / 55))
            // Audio response is a signal envelope, separate from island geometry springs.
            let tau: Double = target > levels[band] ? 0.035 : 0.18
            levels[band] += (target - levels[band]) * (1 - exp(-elapsed / tau))
        }
        return levels
    }
}
