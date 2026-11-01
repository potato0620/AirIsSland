import Foundation

/// Scheduling layer: deterministic arbitration. Time is supplied by the caller.
/// Hidden transient updates keep their original expiry; they never form a replay queue.
struct ActivityScheduler {
    private struct Entry {
        let activity: IslandActivity
        let expiresAt: TimeInterval?
        let sequence: UInt64
    }

    private var entries: [IslandActivityKind: Entry] = [:]
    private var sequence: UInt64 = 0

    mutating func submit(_ activity: IslandActivity, at now: TimeInterval) {
        expire(at: now)
        if activity.kind.isSystemFeedback {
            entries = entries.filter { !$0.key.isSystemFeedback }
        }
        sequence &+= 1
        let duration = Self.duration(for: activity.kind)
        entries[activity.kind] = Entry(
            activity: activity,
            expiresAt: duration.map { now + $0 },
            sequence: sequence
        )
    }

    mutating func end(_ kind: IslandActivityKind) {
        entries[kind] = nil
    }

    mutating func expire(at now: TimeInterval) {
        entries = entries.filter { $0.value.expiresAt.map { $0 > now } ?? true }
    }

    func current(at now: TimeInterval) -> IslandActivity? {
        entries.values.filter { $0.expiresAt.map { $0 > now } ?? true }
            .max {
                let lhs = Self.priority(for: $0.activity.kind)
                let rhs = Self.priority(for: $1.activity.kind)
                return lhs == rhs ? $0.sequence < $1.sequence : lhs < rhs
            }?.activity
    }

    var nextExpiry: TimeInterval? { entries.values.compactMap(\.expiresAt).min() }

    private static func priority(for kind: IslandActivityKind) -> Int {
        switch kind {
        case .power: return 80
        case .musicChange: return 60
        case .music: return 10
        case .volume, .brightness, .backlight, .mic: return 100
        }
    }

    private static func duration(for kind: IslandActivityKind) -> TimeInterval? {
        switch kind {
        case .volume, .brightness, .backlight, .mic: return 1.5
        case .power, .musicChange: return 3
        case .music: return nil
        }
    }
}
