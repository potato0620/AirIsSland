import XCTest

final class CodexSessionTests: XCTestCase {
    private func summary(_ event: CodexTaskEvent, pending: Bool = false) -> CodexRolloutSummary {
        CodexRolloutSummary(lastTaskEvent: event, hasPendingToolCall: pending)
    }

    func testOpenTurnIsRunning() {
        XCTAssertEqual(
            CodexSessionClassifier.state(
                archived: false,
                unread: false,
                summary: summary(.started),
                idleSeconds: 2
            ),
            .running
        )
    }

    func testPendingToolCallNeverBecomesAnApprovalGuess() {
        XCTAssertEqual(
            CodexSessionClassifier.state(
                archived: false,
                unread: false,
                summary: summary(.started, pending: true),
                idleSeconds: 600
            ),
            .running
        )
    }

    func testStaleOpenTurnFallsBackToFinishedAndThenDisappears() {
        XCTAssertEqual(
            CodexSessionClassifier.state(
                archived: false,
                unread: false,
                summary: summary(.started, pending: true),
                idleSeconds: CodexSessionClassifier.staleTurnSeconds + 1
            ),
            .finished
        )
        XCTAssertNil(
            CodexSessionClassifier.state(
                archived: false,
                unread: false,
                summary: summary(.started, pending: true),
                idleSeconds: CodexSessionClassifier.recentlyFinishedSeconds + 1
            )
        )
    }

    func testClosedTurnUsesUnreadThenInterruptedThenFinished() {
        XCTAssertEqual(
            CodexSessionClassifier.state(
                archived: false,
                unread: true,
                summary: summary(.aborted),
                idleSeconds: 90
            ),
            .unread
        )
        XCTAssertEqual(
            CodexSessionClassifier.state(
                archived: false,
                unread: false,
                summary: summary(.aborted),
                idleSeconds: 90
            ),
            .aborted
        )
        XCTAssertEqual(
            CodexSessionClassifier.state(
                archived: false,
                unread: false,
                summary: summary(.completed),
                idleSeconds: 90
            ),
            .finished
        )
        XCTAssertNil(
            CodexSessionClassifier.state(
                archived: false,
                unread: false,
                summary: summary(.completed),
                idleSeconds: CodexSessionClassifier.recentlyFinishedSeconds + 1
            )
        )
    }

    func testCustomFinishedWindowShrinksVisibility() {
        let summary = summary(.completed)
        XCTAssertEqual(
            CodexSessionClassifier.state(
                archived: false, unread: false, summary: summary,
                idleSeconds: 200, finishedWindow: 300
            ),
            .finished
        )
        XCTAssertNil(
            CodexSessionClassifier.state(
                archived: false, unread: false, summary: summary,
                idleSeconds: 400, finishedWindow: 300
            )
        )
    }

    func testArchivedThreadIsExcluded() {
        XCTAssertNil(
            CodexSessionClassifier.state(
                archived: true,
                unread: true,
                summary: summary(.started),
                idleSeconds: 1
            )
        )
    }

    func testParserTracksTaskBoundariesAndPendingCalls() {
        let lines = [
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"type":"response_item","payload":{"type":"function_call","call_id":"a"}}"#,
            #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"a"}}"#,
            #"{"type":"response_item","payload":{"type":"custom_tool_call","call_id":"b"}}"#,
        ]
        let parsed = CodexRolloutParser.summarize(lines: lines)
        XCTAssertEqual(parsed.lastTaskEvent, .started)
        XCTAssertTrue(parsed.hasPendingToolCall)

        let finished = CodexRolloutParser.summarize(lines: lines + [
            #"{"type":"event_msg","payload":{"type":"task_complete"}}"#
        ])
        XCTAssertEqual(finished.lastTaskEvent, .completed)
        XCTAssertFalse(finished.hasPendingToolCall)
    }

    func testCompletedTurnClearsEarlierPendingCall() {
        let parsed = CodexRolloutParser.summarize(lines: [
            #"{"type":"response_item","payload":{"type":"custom_tool_call","call_id":"b"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete"}}"#,
        ])
        XCTAssertEqual(parsed.lastTaskEvent, .completed)
        XCTAssertFalse(parsed.hasPendingToolCall)
    }

    func testTruncatedWindowStartingMidTurnIsStillOpen() {
        let parsed = CodexRolloutParser.summarize(lines: [
            #"{"type":"response_item","payload":{"type":"reasoning"}}"#,
            #"{"type":"event_msg","payload":{"type":"token_count"}}"#,
            #"{"type":"response_item","payload":{"type":"custom_tool_call","call_id":"x"}}"#,
        ])
        XCTAssertEqual(parsed.lastTaskEvent, .started)
        XCTAssertTrue(parsed.hasPendingToolCall)
    }

    func testMalformedLinesAreIgnored() {
        let parsed = CodexRolloutParser.summarize(lines: ["not json", "{}", #"{"type":"event_msg"}"#])
        XCTAssertEqual(parsed, CodexRolloutSummary())
    }

    func testAbortedTurnIsAnExplicitInterruption() {
        let parsed = CodexRolloutParser.summarize(lines: [
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#,
        ])
        XCTAssertEqual(parsed.lastTaskEvent, .aborted)
    }

    func testChangeDetectionPicksTheMostActionableTransition() {
        let now = Date()
        let previous: [String: AgentSessionState] = ["a": .running, "b": .running, "c": .running]
        let sessions = [
            AgentSession(id: "a", agent: .codex, title: "a", project: "p", state: .finished, updatedAt: now),
            AgentSession(id: "b", agent: .codex, title: "b", project: "p", state: .unread, updatedAt: now),
            AgentSession(id: "c", agent: .codex, title: "c", project: "p", state: .running, updatedAt: now),
        ]
        let change = AgentSessionChange.detect(previous: previous, sessions: sessions, at: now)
        XCTAssertEqual(change?.id, "b")
        XCTAssertEqual(change?.from, .running)
        XCTAssertEqual(change?.to, .unread)
    }

    func testChangeDetectionIgnoresUnchangedAndUnknownSessions() {
        let now = Date()
        let previous: [String: AgentSessionState] = ["a": .running]
        XCTAssertNil(AgentSessionChange.detect(previous: previous, sessions: [
            AgentSession(id: "a", agent: .codex, title: "a", project: "p", state: .running, updatedAt: now),
            AgentSession(id: "new", agent: .codex, title: "n", project: "p", state: .unread, updatedAt: now),
        ], at: now))
    }

    func testOrderingPutsActiveWorkFirstThenRecency() {
        let now = Date()
        let sessions = [
            AgentSession(id: "unread", agent: .codex, title: "u", project: "p", state: .unread, updatedAt: now),
            AgentSession(id: "old", agent: .codex, title: "o", project: "p", state: .running, updatedAt: now.addingTimeInterval(-60)),
            AgentSession(id: "aborted", agent: .codex, title: "a", project: "p", state: .aborted, updatedAt: now.addingTimeInterval(-120)),
            AgentSession(id: "new", agent: .codex, title: "n", project: "p", state: .running, updatedAt: now),
            AgentSession(id: "done", agent: .codex, title: "d", project: "p", state: .finished, updatedAt: now),
        ]
        XCTAssertEqual(
            AgentSession.ordered(sessions).map(\.id),
            ["new", "old", "unread", "aborted", "done"]
        )
    }

    func testSectionsOmitAgentsWithoutSessions() {
        let now = Date()
        let sessions = [
            AgentSession(id: "codex:a", agent: .codex, title: "a", project: "p", state: .running, updatedAt: now),
            AgentSession(id: "codex:b", agent: .codex, title: "b", project: "p", state: .finished, updatedAt: now),
        ]
        let sections = AgentSession.sections(sessions)
        XCTAssertEqual(sections.map { $0.agent }, [.codex])
        XCTAssertEqual(sections.first?.sessions.map(\.id), ["codex:a", "codex:b"])
    }

    func testSectionsCapRowsPerAgent() {
        let now = Date()
        let sessions = (0..<7).map { index in
            AgentSession(id: "codex:\(index)", agent: .codex, title: "\(index)", project: "p",
                         state: .running, updatedAt: now)
        }
        let capped = AgentSession.sections(sessions, limitPerAgent: 3)
        XCTAssertEqual(capped.count, 1)
        XCTAssertEqual(capped.first?.sessions.map(\.id), ["codex:0", "codex:1", "codex:2"])
        XCTAssertEqual(AgentSession.sections(sessions).first?.sessions.count, 5)
    }

    func testSectionsFollowAgentKindOrder() {
        let now = Date()
        let sessions = [
            AgentSession(id: "opencode:1", agent: .opencode, title: "o", project: "p", state: .running, updatedAt: now),
            AgentSession(id: "claude:1", agent: .claude, title: "c", project: "p", state: .running, updatedAt: now),
            AgentSession(id: "codex:1", agent: .codex, title: "x", project: "p", state: .running, updatedAt: now),
        ]
        XCTAssertEqual(AgentSession.sections(sessions).map { $0.agent }, [.codex, .claude, .opencode])
    }

    func testSessionIdentifiersAreNamespacedPerAgent() {
        XCTAssertEqual(AgentSession.identified(.claude, "abc"), "claude:abc")
        XCTAssertNotEqual(
            AgentSession.identified(.claude, "abc"),
            AgentSession.identified(.codex, "abc")
        )
    }
}
