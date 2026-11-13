import Foundation

/// Agents whose local sessions the island can read without an SDK.
enum AgentKind: String, CaseIterable, Identifiable {
    case codex
    case dsh
    case claude
    case opencode

    var id: Self { self }

}

/// Activity-layer facts for agent sessions on this Mac.
/// Foundation only: no file access, no window or view work, no timers.
enum AgentSessionState: String, CaseIterable, Equatable {
    case running
    case unread
    /// turn_aborted is an explicit rollout event, unlike the old approval guess.
    case aborted
    /// Recently completed work stays visible for a while instead of vanishing.
    case finished
}

struct AgentSession: Identifiable, Equatable {
    /// Namespaced with the agent so equal native ids never collide.
    let id: String
    let agent: AgentKind
    let title: String
    let project: String
    let state: AgentSessionState
    let updatedAt: Date

    var isPending: Bool { state != .finished }

    static func identified(_ agent: AgentKind, _ nativeID: String) -> String {
        "\(agent.rawValue):\(nativeID)"
    }

    /// One section per agent that has sessions; empty agents are omitted.
    static func sections(_ sessions: [AgentSession], limitPerAgent: Int = 5) -> [(agent: AgentKind, sessions: [AgentSession])] {
        AgentKind.allCases.compactMap { agent in
            let rows = ordered(sessions.filter { $0.agent == agent }, limit: limitPerAgent)
            return rows.isEmpty ? nil : (agent, rows)
        }
    }

    /// Waiting-on-the-user first, then active turns, then unread results.
    static func ordered(_ sessions: [AgentSession], limit: Int = 8) -> [AgentSession] {
        let rank: (AgentSessionState) -> Int = { state in
            switch state {
            case .running: return 0
            case .unread: return 1
            case .aborted: return 2
            case .finished: return 3
            }
        }
        return sessions
            .sorted {
                let lhs = rank($0.state), rhs = rank($1.state)
                if lhs != rhs { return lhs < rhs }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id < $1.id
            }
            .prefix(limit)
            .map { $0 }
    }
}

/// One observed state transition. The island expands to explain what changed.
struct AgentSessionChange: Equatable {
    let id: String
    let title: String
    let from: AgentSessionState?
    let to: AgentSessionState
    let at: Date

    /// Picks the most actionable transition when a poll sees several at once.
    static func detect(
        previous: [String: AgentSessionState],
        sessions: [AgentSession],
        at: Date
    ) -> AgentSessionChange? {
        func rank(_ state: AgentSessionState) -> Int {
            switch state {
            case .unread: return 4
            case .running: return 3
            case .aborted: return 2
            case .finished: return 1
            }
        }
        var best: AgentSessionChange?
        for session in sessions {
            guard let old = previous[session.id], old != session.state else { continue }
            let candidate = AgentSessionChange(
                id: session.id, title: session.title, from: old, to: session.state, at: at
            )
            if let current = best, rank(current.to) >= rank(candidate.to) { continue }
            best = candidate
        }
        return best
    }
}

enum CodexTaskEvent: Equatable {
    case started
    case completed
    case aborted
    case unknown
}

/// Last task boundary plus tool calls that never received an output.
struct CodexRolloutSummary: Equatable {
    var lastTaskEvent: CodexTaskEvent = .unknown
    var hasPendingToolCall = false
}

/// Parses Codex rollout lines. Callers supply a bounded tail, never the whole file.
enum CodexRolloutParser {
    static func summarize(lines: [String]) -> CodexRolloutSummary {
        var summary = CodexRolloutSummary()
        var pendingCalls = Set<String>()
        var sawTurnActivity = false

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any] else { continue }

            switch type {
            case "event_msg":
                switch payload["type"] as? String {
                case "task_started":
                    summary.lastTaskEvent = .started
                case "task_complete":
                    summary.lastTaskEvent = .completed
                    pendingCalls.removeAll()
                case "turn_aborted":
                    summary.lastTaskEvent = .aborted
                    pendingCalls.removeAll()
                case "item_completed", "token_count":
                    sawTurnActivity = true
                default:
                    break
                }
            case "response_item":
                sawTurnActivity = true
                switch payload["type"] as? String {
                case "function_call", "custom_tool_call":
                    if let identifier = payload["call_id"] as? String ?? payload["id"] as? String {
                        pendingCalls.insert(identifier)
                    }
                case "function_call_output", "custom_tool_call_output":
                    if let identifier = payload["call_id"] as? String ?? payload["id"] as? String {
                        pendingCalls.remove(identifier)
                    }
                default:
                    break
                }
            default:
                break
            }
        }

        // A bounded tail can start mid-turn; activity without a boundary means the
        // turn is still open. A completed turn writes its boundary before retiring.
        if summary.lastTaskEvent == .unknown, sawTurnActivity {
            summary.lastTaskEvent = .started
        }
        summary.hasPendingToolCall = !pendingCalls.isEmpty
            && summary.lastTaskEvent == .started
        return summary
    }
}

/// Deterministic state rules shared by the file adapter and tests.
enum CodexSessionClassifier {
    /// An open turn survives restarts, so silence alone cannot keep it open forever.
    static let staleTurnSeconds: TimeInterval = 30 * 60
    /// A completed session lingers this long so the page does not empty out.
    static let recentlyFinishedSeconds: TimeInterval = 60 * 60

    static func isTurnOpen(_ summary: CodexRolloutSummary, idleSeconds: TimeInterval) -> Bool {
        summary.lastTaskEvent == .started && idleSeconds < staleTurnSeconds
    }

    static func state(
        archived: Bool,
        unread: Bool,
        summary: CodexRolloutSummary,
        idleSeconds: TimeInterval,
        finishedWindow: TimeInterval = recentlyFinishedSeconds
    ) -> AgentSessionState? {
        guard !archived else { return nil }
        if isTurnOpen(summary, idleSeconds: idleSeconds) { return .running }
        if unread { return .unread }
        guard idleSeconds <= finishedWindow else { return nil }
        return summary.lastTaskEvent == .aborted ? .aborted : .finished
    }
}
