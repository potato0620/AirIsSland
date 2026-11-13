import AppKit
import Combine
import Defaults
import Foundation
import OSLog
import SQLite3

private let codexLog = Logger(subsystem: "theboringteam.boringnotch", category: "codex")

/// One row of Codex's own thread index. Read-only mirror; Codex stays the owner.
struct CodexThreadRecord: Equatable {
    let id: String
    let title: String
    let project: String
    let unread: Bool
    let rolloutPath: String
    let updatedAt: Date
}

struct AgentSnapshot {
    let sessions: [AgentSession]
    let available: Bool
}

enum AgentPaths {
    /// Inside the sandbox NSHomeDirectory() is the container, but the agents write
    /// to the account's real home directory.
    static var home: String {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return String(cString: directory)
        }
        return NSHomeDirectory()
    }

    static func url(_ relative: String) -> URL {
        URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(relative, isDirectory: false)
    }
}

enum AgentText {
    static func title(_ raw: String) -> String {
        let firstLine = raw.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? raw
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return String(localized: "Untitled session") }
        return trimmed.count > 80 ? String(trimmed.prefix(80)) : trimmed
    }

    static func project(_ cwd: String) -> String {
        guard !cwd.isEmpty else { return "Agent" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

/// File adapter for Codex desktop data. Runs off the main actor and never writes.
enum CodexStore {
    static var homeDirectory: URL {
        return URL(fileURLWithPath: realHomeDirectory, isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
    }

    /// Inside the sandbox NSHomeDirectory() is the container, but Codex writes to
    /// the account's real home directory.
    private static var realHomeDirectory: String { AgentPaths.home }

    static func snapshot(now: Date = Date(), finishedWindow: TimeInterval = 60 * 60) -> AgentSnapshot {
        guard let threads = loadThreads() else {
            return AgentSnapshot(sessions: [], available: false)
        }

        var sessions: [AgentSession] = []
        for thread in threads.prefix(120) {
            let age = now.timeIntervalSince(thread.updatedAt)
            let recent = age < 24 * 60 * 60
            // Older read receipts are stale for the desktop UI; do not resurrect them.
            let unread = thread.unread && age < 7 * 24 * 60 * 60
            guard recent || unread else { continue }

            // Rollout paths come from the database; never read outside the granted root.
            let readableRollout = thread.rolloutPath.hasPrefix(homeDirectory.path + "/")
            let summary = recent && readableRollout ? rolloutSummary(at: thread.rolloutPath) : CodexRolloutSummary()
            let idle = recent && readableRollout ? max(0, now.timeIntervalSince(modificationDate(of: thread.rolloutPath) ?? thread.updatedAt)) : age
            guard let state = CodexSessionClassifier.state(
                archived: false,
                unread: unread,
                summary: summary,
                idleSeconds: idle,
                finishedWindow: finishedWindow
            ) else { continue }

            sessions.append(AgentSession(
                id: AgentSession.identified(.codex, thread.id),
                agent: .codex,
                title: thread.title,
                project: thread.project,
                state: state,
                updatedAt: thread.updatedAt
            ))
        }

        return AgentSnapshot(sessions: AgentSession.ordered(sessions), available: true)
    }

    private static func loadThreads() -> [CodexThreadRecord]? {
        let path = homeDirectory.appendingPathComponent("state_5.sqlite").path
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        if let records = readThreads(atPath: path, readOnly: true) { return records }

        // The sandbox grants read-only access, but SQLite needs write access to the
        // WAL shared-memory file. Read a private copy instead.
        guard let copy = copyDatabase(from: path) else {
            codexLog.error("agents database unreadable")
            return nil
        }
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        codexLog.debug("codex database read through a temporary copy")
        return readThreads(atPath: copy.path, readOnly: false)
    }

    private static func copyDatabase(from path: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-\(UUID().uuidString)", isDirectory: true)
        let destination = directory.appendingPathComponent("state_5.sqlite")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(atPath: path, toPath: destination.path)
            for suffix in ["-wal", "-shm"] where FileManager.default.fileExists(atPath: path + suffix) {
                try? FileManager.default.copyItem(atPath: path + suffix, toPath: destination.path + suffix)
            }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
    }

    private static func readThreads(atPath path: String, readOnly: Bool) -> [CodexThreadRecord]? {
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK,
              let db = handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT t.id,
               COALESCE(NULLIF(t.name, ''), t.title, '') AS label,
               COALESCE(t.cwd, ''),
               COALESCE(t.updated_at_ms, 0),
               COALESCE(t.updated_at, 0),
               COALESCE(t.rollout_path, ''),
               r.first_unread_turn
        FROM threads t
        LEFT JOIN thread_read_receipts r ON r.thread_id = t.id
        WHERE t.archived = 0
        ORDER BY COALESCE(t.updated_at_ms, t.updated_at * 1000) DESC
        LIMIT 200
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        var records: [CodexThreadRecord] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { return nil }
            guard let identifier = text(statement, 0), !identifier.isEmpty else { continue }
            let label = text(statement, 1) ?? ""
            let cwd = text(statement, 2) ?? ""
            let milliseconds = sqlite3_column_int64(statement, 3)
            let seconds = sqlite3_column_int64(statement, 4)
            let rollout = text(statement, 5) ?? ""
            let unreadTurn = text(statement, 6)

            let stamp = milliseconds > 0 ? Double(milliseconds) / 1000 : Double(seconds)
            records.append(CodexThreadRecord(
                id: identifier,
                title: displayTitle(label),
                project: cwd.isEmpty ? "Codex" : URL(fileURLWithPath: cwd).lastPathComponent,
                unread: !(unreadTurn ?? "").isEmpty,
                rolloutPath: rollout,
                updatedAt: Date(timeIntervalSince1970: stamp)
            ))
        }
        return records
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private static func displayTitle(_ raw: String) -> String {
        let firstLine = raw.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? raw
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return String(localized: "Untitled session") }
        return trimmed.count > 80 ? String(trimmed.prefix(80)) : trimmed
    }

    static func rolloutSummary(at path: String) -> CodexRolloutSummary {
        guard !path.isEmpty,
              let handle = FileHandle(forReadingAtPath: path) else { return CodexRolloutSummary() }
        defer { try? handle.close() }

        let size = handle.seekToEndOfFile()
        let window: UInt64 = 256 * 1024
        let offset = size > window ? size - window : 0
        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else { return CodexRolloutSummary() }

        var lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        // The window can start in the middle of a record.
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        return CodexRolloutParser.summarize(lines: lines)
    }

    private static func modificationDate(of path: String) -> Date? {
        guard !path.isEmpty,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attributes[.modificationDate] as? Date
    }
}


/// Reads DeepSeek Harness's session projection cache (JSON), never the compressed transcript.
enum DSHStore {
    static func snapshot(now: Date = Date(), finishedWindow: TimeInterval = 60 * 60) -> AgentSnapshot {
        let directory = AgentPaths.url(".dsh/storages/session_projcache/sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return AgentSnapshot(sessions: [], available: false) }

        let transcriptDates = transcriptDates()
        var sessions: [AgentSession] = []
        for file in files where file.pathExtension == "json" {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let fileDate = values.contentModificationDate else { continue }
            // The projection cache is rewritten on launch; the transcript mtime is
            // the real last-activity signal.
            let identifier = file.deletingPathExtension().lastPathComponent
            let updated = transcriptDates[identifier] ?? fileDate
            let age = now.timeIntervalSince(updated)
            guard age < 24 * 60 * 60 else { continue }
            guard let data = try? Data(contentsOf: file),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let record = root["record"] as? [String: Any],
                  let rows = record["rows"] as? [String: Any] else { continue }

            let title = (rows["title"] as? [String: Any])?["val"] as? String
            let cwd = (record["identity"] as? [String: Any])?["cwd"] as? String
            let openTurn = ((rows["turnBoundary"] as? [String: Any])?["val"] as? [String: Any])?["openTurnStartSeq"] as? Int

            let state: AgentSessionState?
            if openTurn != nil, age < 30 * 60 { state = .running }
            else if age < finishedWindow { state = .finished }
            else { state = nil }
            guard let state else { continue }

            sessions.append(AgentSession(
                id: AgentSession.identified(.dsh, identifier),
                agent: .dsh,
                title: AgentText.title(title ?? ""),
                project: AgentText.project(cwd ?? ""),
                state: state,
                updatedAt: updated
            ))
        }
        return AgentSnapshot(sessions: sessions, available: true)
    }

    private static func transcriptDates() -> [String: Date] {
        let root = AgentPaths.url(".dsh/sessions")
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var dates: [String: Date] = [:]
        for project in projects {
            guard let sessions = try? FileManager.default.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for session in sessions {
                guard let files = try? FileManager.default.contentsOfDirectory(
                    at: session,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                let newest = files.compactMap {
                    try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                }.max()
                if let newest { dates[session.lastPathComponent] = newest }
            }
        }
        return dates
    }
}

/// Reads Claude Code project transcripts. A turn is open while the last record is a
/// user message or an assistant message that stopped for a tool call.
enum ClaudeStore {
    static func snapshot(now: Date = Date(), finishedWindow: TimeInterval = 60 * 60) -> AgentSnapshot {
        let root = AgentPaths.url(".claude/projects")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return AgentSnapshot(sessions: [], available: false) }

        var sessions: [AgentSession] = []
        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let updated = values.contentModificationDate else { continue }
            let age = now.timeIntervalSince(updated)
            guard age < 60 * 60 else { continue }
            guard let tail = cachedTail(file, modified: updated, size: UInt64(values.fileSize ?? 0)) else { continue }

            let state: AgentSessionState?
            if tail.isOpen, age < 15 * 60 { state = .running }
            else if age < finishedWindow { state = .finished }
            else { state = nil }
            guard let state else { continue }

            sessions.append(AgentSession(
                id: AgentSession.identified(.claude, tail.sessionID ?? file.deletingPathExtension().lastPathComponent),
                agent: .claude,
                title: AgentText.title(tail.title ?? ""),
                project: AgentText.project(tail.cwd ?? ""),
                state: state,
                updatedAt: updated
            ))
        }
        return AgentSnapshot(sessions: sessions, available: true)
    }

    private struct Tail {
        var sessionID: String?
        var title: String?
        var cwd: String?
        var isOpen = false
    }

    private static let cacheLock = NSLock()
    private static var tailCache: [String: (modified: Date, size: UInt64, tail: Tail)] = [:]

    private static func cachedTail(_ file: URL, modified: Date, size: UInt64) -> Tail? {
        cacheLock.lock()
        if let entry = tailCache[file.path], entry.modified == modified, entry.size == size {
            cacheLock.unlock()
            return entry.tail
        }
        cacheLock.unlock()
        guard let parsed = tail(of: file) else { return nil }
        cacheLock.lock()
        if tailCache.count > 400 { tailCache.removeAll(keepingCapacity: true) }
        tailCache[file.path] = (modified, size, parsed)
        cacheLock.unlock()
        return parsed
    }

    private static func tail(of file: URL) -> Tail? {
        guard let handle = FileHandle(forReadingAtPath: file.path) else { return nil }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        let window: UInt64 = 128 * 1024
        let offset = size > window ? size - window : 0
        handle.seek(toFileOffset: offset)
        guard let content = String(data: handle.readDataToEndOfFile(), encoding: .utf8) else { return nil }
        var lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if offset > 0, !lines.isEmpty { lines.removeFirst() }

        var result = Tail()
        var lastKind: String?
        var lastStop: String?
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let type = entry["type"] as? String
            if let sessionID = entry["sessionId"] as? String { result.sessionID = sessionID }
            if let cwd = entry["cwd"] as? String, !cwd.isEmpty { result.cwd = cwd }
            if type == "custom-title", let title = entry["customTitle"] as? String, !title.isEmpty {
                result.title = title
                continue
            }
            guard type == "user" || type == "assistant" else { continue }
            lastKind = type
            if let message = entry["message"] as? [String: Any] {
                lastStop = message["stop_reason"] as? String
                if type == "user", result.title == nil {
                    result.title = firstText(message["content"])
                }
            }
        }
        result.isOpen = lastKind == "user" || (lastKind == "assistant" && lastStop == "tool_use")
        return result
    }

    private static func firstText(_ content: Any?) -> String? {
        if let text = content as? String { return text }
        guard let parts = content as? [[String: Any]] else { return nil }
        for part in parts {
            if let text = part["text"] as? String, !text.isEmpty { return text }
        }
        return nil
    }
}

/// Reads the local OpenCode database. The last message is `idle` when a turn ended.
enum OpenCodeStore {
    static func snapshot(now: Date = Date(), finishedWindow: TimeInterval = 60 * 60) -> AgentSnapshot {
        let path = AgentPaths.url(".local/share/opencode/opencode.db").path
        guard FileManager.default.fileExists(atPath: path) else {
            return AgentSnapshot(sessions: [], available: false)
        }
        guard let rows = readSessions(atPath: path) else {
            return AgentSnapshot(sessions: [], available: true)
        }

        var sessions: [AgentSession] = []
        for row in rows {
            let age = now.timeIntervalSince(row.updatedAt)
            guard age < 24 * 60 * 60 else { continue }
            let state: AgentSessionState?
            if row.lastMessage == "idle" { state = age < finishedWindow ? .finished : nil }
            else { state = age < 15 * 60 ? .running : nil }
            guard let state else { continue }
            sessions.append(AgentSession(
                id: AgentSession.identified(.opencode, row.id),
                agent: .opencode,
                title: AgentText.title(row.title),
                project: AgentText.project(row.directory),
                state: state,
                updatedAt: row.updatedAt
            ))
        }
        return AgentSnapshot(sessions: sessions, available: true)
    }

    private struct Row {
        let id: String
        let title: String
        let directory: String
        let lastMessage: String
        let updatedAt: Date
    }

    private static func readSessions(atPath path: String) -> [Row]? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db = handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT s.id, COALESCE(s.title, ''), COALESCE(s.directory, ''), COALESCE(s.time_updated, 0),
               (SELECT m.type FROM session_message m WHERE m.session_id = s.id ORDER BY m.seq DESC LIMIT 1)
        FROM session_v2 s
        ORDER BY s.time_updated DESC
        LIMIT 20
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        var rows: [Row] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { return nil }
            guard let identifier = text(statement, 0) else { continue }
            rows.append(Row(
                id: identifier,
                title: text(statement, 1) ?? "",
                directory: text(statement, 2) ?? "",
                lastMessage: text(statement, 4) ?? "",
                updatedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 3)) / 1000)
            ))
        }
        return rows
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }
}

enum AgentSessionStore {
    static func snapshot(now: Date = Date(), finishedWindow: TimeInterval = 60 * 60) -> AgentSnapshot {
        let snapshots = [
            CodexStore.snapshot(now: now, finishedWindow: finishedWindow),
            DSHStore.snapshot(now: now, finishedWindow: finishedWindow),
            ClaudeStore.snapshot(now: now, finishedWindow: finishedWindow),
            OpenCodeStore.snapshot(now: now, finishedWindow: finishedWindow),
        ]
        codexLog.debug("agent rows codex=\(snapshots[0].sessions.count, privacy: .public) dsh=\(snapshots[1].sessions.count, privacy: .public) claude=\(snapshots[2].sessions.count, privacy: .public) opencode=\(snapshots[3].sessions.count, privacy: .public)")
        var seen = Set<String>()
        let sessions = snapshots.flatMap(\.sessions).filter { seen.insert($0.id).inserted }
        return AgentSnapshot(sessions: sessions, available: snapshots.contains { $0.available })
    }
}

/// Activity source. Polls every supported agent's local store; absent agents are hidden.
@MainActor
final class CodexActivityManager: ObservableObject {
    static let shared = CodexActivityManager()

    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var available = true

    private var pollTask: Task<Void, Never>?
    private var generation = UUID()
    private var lastStates: [String: AgentSessionState] = [:]
    private var refreshInFlight = false
    private var observers = Set<AnyCancellable>()
    private let interval: Duration = .seconds(5)

    private init() {
        Defaults.publisher(.codexActivityEnabled).sink { [weak self] _ in
            Task { @MainActor in self?.applyPreference() }
        }.store(in: &observers)
        Defaults.publisher(.showFinishedAgentSessions).sink { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }.store(in: &observers)
        Defaults.publisher(.finishedSessionMinutes).sink { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }.store(in: &observers)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification))
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            }
            .store(in: &observers)

        applyPreference()
    }

    func applyPreference() {
        if Defaults[.codexActivityEnabled] {
            startPolling()
        } else {
            stop()
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.interval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        generation = UUID()
        sessions = []
        lastStates = [:]
        ActivityCoordinator.shared.setAgentSessions([])
    }

    /// Opens the thread in Codex through its registered `codex://` scheme.
    @discardableResult
    func open(_ session: AgentSession) -> Bool {
        switch session.agent {
        case .codex:
            guard let nativeID = session.id.split(separator: ":", maxSplits: 1).last,
                  let url = URL(string: "codex://threads/\(nativeID)") else { return false }
            return NSWorkspace.shared.open(url)
        case .dsh:
            // DeepSeek Harness registers only a window-focus link (dsh://open);
            // its desktop app has no per-session URL scheme.
            guard let url = URL(string: "dsh://open") else { return false }
            return NSWorkspace.shared.open(url)
        case .claude, .opencode:
            return false
        }
    }

    func refresh() async {
        guard Defaults[.codexActivityEnabled], !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        let token = UUID()
        generation = token
        let retention = Defaults[.finishedSessionMinutes]
        // Zero means "never expire"; the stores still cap their scans at 24 h.
        let finishedWindow: TimeInterval = retention <= 0 ? .greatestFiniteMagnitude : TimeInterval(max(1, retention) * 60)
        let showFinished = Defaults[.showFinishedAgentSessions]
        let snapshot = await Task.detached(priority: .utility) {
            AgentSessionStore.snapshot(finishedWindow: finishedWindow)
        }.value
        guard generation == token, Defaults[.codexActivityEnabled] else { return }
        available = snapshot.available
        sessions = showFinished ? snapshot.sessions : snapshot.sessions.filter { $0.state != .finished }
        // The first poll establishes a baseline; it is not a transition.
        let change = lastStates.isEmpty
            ? nil
            : AgentSessionChange.detect(previous: lastStates, sessions: sessions, at: Date())
        lastStates = Dictionary(sessions.map { ($0.id, $0.state) }, uniquingKeysWith: { _, new in new })
        codexLog.debug("agents snapshot available=\(snapshot.available, privacy: .public) sessions=\(snapshot.sessions.count, privacy: .public) visible=\(self.sessions.count, privacy: .public) window=\(retention, privacy: .public) change=\(change?.to.rawValue ?? "none", privacy: .public)")
        ActivityCoordinator.shared.setAgentSessions(sessions, change: change)
    }
}
