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
    private var preferredKind: IslandActivityKind?

    /// Manual page selection only changes the resident activity, never transient arbitration.
    mutating func prefer(_ kind: IslandActivityKind, at now: TimeInterval) {
        expire(at: now)
        guard Self.isPersistent(kind), entries[kind] != nil else { return }
        preferredKind = kind
    }

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
        if preferredKind == kind { preferredKind = nil }
    }

    mutating func expire(at now: TimeInterval) {
        entries = entries.filter { $0.value.expiresAt.map { $0 > now } ?? true }
    }

    func current(at now: TimeInterval) -> IslandActivity? {
        let automatic = entries.values.filter {
            ($0.expiresAt.map { $0 > now } ?? true) && Self.priority(for: $0.activity.kind) != nil
        }
            .max {
                let lhs = Self.priority(for: $0.activity.kind) ?? Int.min
                let rhs = Self.priority(for: $1.activity.kind) ?? Int.min
                return lhs == rhs ? $0.sequence < $1.sequence : lhs < rhs
            }?.activity
        guard let automatic, Self.isPersistent(automatic.kind),
              let preferredKind, let preferred = activity(preferredKind, at: now) else { return automatic }
        return preferred
    }

    var nextExpiry: TimeInterval? { entries.values.compactMap(\.expiresAt).min() }

    func activity(_ kind: IslandActivityKind, at now: TimeInterval) -> IslandActivity? {
        guard let entry = entries[kind], entry.expiresAt.map({ $0 > now }) ?? true else { return nil }
        return entry.activity
    }

    /// Nil keeps source data available to expanded panels without entering arbitration.
    private static func priority(for kind: IslandActivityKind) -> Int? {
        switch kind {
        case .timerFinished: return 110
        case .timer: return 30
        case .reminders, .codex: return nil
        case .power: return 80
        case .agentChange: return 105
        case .musicChange: return 100
        case .music: return 10
        case .volume, .brightness, .backlight, .mic: return 100
        }
    }

    private static func isPersistent(_ kind: IslandActivityKind) -> Bool {
        switch kind {
        case .music, .timer: return true
        case .reminders, .codex, .agentChange, .timerFinished, .power, .musicChange, .volume, .brightness, .backlight, .mic: return false
        }
    }

    private static func duration(for kind: IslandActivityKind) -> TimeInterval? {
        switch kind {
        case .volume, .brightness, .backlight, .mic: return 1.5
        case .power, .musicChange: return 3
        case .agentChange: return 5
        case .music, .timer, .timerFinished, .reminders, .codex: return nil
        }
    }
}
