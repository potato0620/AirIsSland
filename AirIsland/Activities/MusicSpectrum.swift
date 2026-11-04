import Foundation

/// A source lease, not a new activity. Replaced leases reject queued audio frames.
struct MusicSpectrumRequest: Equatable {
    let id: UUID
    let bundleIdentifier: String
    let trackIdentifier: UUID?
}

struct MusicSpectrumState {
    static let barCount = 6
    static let quiet = Array(repeating: 0.12, count: barCount)
    private(set) var request: MusicSpectrumRequest?
    private(set) var levels = quiet

    mutating func update(enabled: Bool, playing: Bool, bundleIdentifier: String?, trackIdentifier: UUID? = nil, visible: Bool) {
        let bundle = bundleIdentifier ?? ""
        guard enabled, playing, visible, !bundle.isEmpty else {
            request = nil
            levels = Self.quiet
            return
        }
        guard request?.bundleIdentifier != bundle || request?.trackIdentifier != trackIdentifier else { return }
        request = MusicSpectrumRequest(id: UUID(), bundleIdentifier: bundle, trackIdentifier: trackIdentifier)
        levels = Self.quiet
    }

    @discardableResult mutating func receive(_ values: [Double], for lease: MusicSpectrumRequest) -> Bool {
        guard request == lease, values.count == Self.barCount else { return false }
        levels = values.map { $0.isFinite ? min(1, max(0.12, $0)) : 0.12 }
        return true
    }
}
