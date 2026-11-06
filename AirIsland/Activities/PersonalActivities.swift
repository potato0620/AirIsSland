import Foundation

/// Activity facts. Deadlines survive process restarts and sleep; no UI or scheduling policy.
struct TimerSession: Codable, Equatable, Identifiable {
    enum Phase: String, Codable { case running, paused, finished }
    let id: UUID
    let duration: TimeInterval
    private(set) var phase: Phase
    private(set) var deadline: Date?
    private(set) var pausedRemaining: TimeInterval

    init?(duration: TimeInterval, now: Date = Date()) {
        guard duration.isFinite, (1...86399).contains(duration) else { return nil }
        id = UUID()
        self.duration = duration
        phase = .running
        deadline = now.addingTimeInterval(duration)
        pausedRemaining = duration
    }

    var isValid: Bool {
        duration.isFinite && (1...86399).contains(duration)
            && pausedRemaining.isFinite && (0...duration).contains(pausedRemaining)
            && (phase != .running || deadline != nil)
    }

    func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .running: return min(duration, max(0, deadline?.timeIntervalSince(now) ?? 0))
        case .paused: return pausedRemaining
        case .finished: return 0
        }
    }

    mutating func pause(at now: Date) {
        guard phase == .running else { return }
        if finishIfDue(at: now) { return }
        pausedRemaining = remaining(at: now)
        deadline = nil
        phase = .paused
    }

    mutating func resume(at now: Date) {
        guard phase == .paused else { return }
        deadline = now.addingTimeInterval(pausedRemaining)
        phase = .running
    }

    @discardableResult mutating func finishIfDue(at now: Date) -> Bool {
        guard phase == .running, remaining(at: now) <= 0 else { return false }
        phase = .finished
        deadline = nil
        pausedRemaining = 0
        return true
    }
}

struct ReminderTask: Identifiable, Equatable {
    let id: String
    let title: String
    let dueDate: Date?
    var listIdentifier: String = ""
    var creationDate: Date? = nil

    func renamed(to title: String) -> ReminderTask {
        ReminderTask(id: id, title: title, dueDate: dueDate,
                     listIdentifier: listIdentifier, creationDate: creationDate)
    }
}

struct ReminderList: Identifiable, Equatable {
    let id: String
    let title: String
    let account: String
    let writable: Bool

    var displayTitle: String { account.isEmpty ? title : "\(title) — \(account)" }
}

/// Empty identifier means all lists. Filtering never excludes undated or future tasks.
struct ReminderListSelection: Equatable {
    var identifier: String = ""

    func includes(listIdentifier: String) -> Bool { identifier.isEmpty || identifier == listIdentifier }

    func filter(_ tasks: [ReminderTask]) -> [ReminderTask] {
        tasks.filter { includes(listIdentifier: $0.listIdentifier) }.sorted {
            let lhs = $0.creationDate ?? .distantPast
            let rhs = $1.creationDate ?? .distantPast
            if lhs != rhs { return lhs < rhs }
            return $0.id < $1.id
        }
    }

    func destination(in lists: [ReminderList], defaultIdentifier: String?) -> ReminderList? {
        let target = identifier.isEmpty ? defaultIdentifier : identifier
        return lists.first { $0.id == target && $0.writable }
    }
}

/// A generation gate shared by the EventKit adapter and deterministic tests.
struct ReminderFetchGeneration {
    private(set) var value = UUID()
    mutating func invalidate() -> UUID { value = UUID(); return value }
    func accepts(_ token: UUID) -> Bool { value == token }
}
