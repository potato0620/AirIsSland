import AppKit
import Combine
import Defaults
import Foundation

/// Activity source: one real countdown, persisted independently of windows/screens.
@MainActor
final class TimerActivityManager {
    static let shared = TimerActivityManager()
    private let storageKey = "AirIsland.timerSession.v1"
    private var session: TimerSession?
    private var deadlineTask: Task<Void, Never>?
    private var observers = Set<AnyCancellable>()

    private init() {
        if Defaults[.timerActivityEnabled], let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(TimerSession.self, from: data), saved.isValid {
            session = saved
        }
        synchronize()
        Defaults.publisher(.timerActivityEnabled).sink { [weak self] change in
            Task { @MainActor in if !change.newValue && !Defaults[.timerActivityEnabled] { self?.cancel() } }
        }.store(in: &observers)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemClockDidChange))
            .sink { [weak self] _ in Task { @MainActor in self?.synchronize() } }
            .store(in: &observers)
    }

    func start(duration: TimeInterval) {
        guard Defaults[.timerActivityEnabled], let next = TimerSession(duration: duration) else { return }
        session = next
        synchronize()
    }

    func togglePause() {
        guard var session else { return }
        switch session.phase {
        case .running: session.pause(at: Date())
        case .paused: session.resume(at: Date())
        case .finished: return
        }
        self.session = session
        synchronize()
    }

    func cancel() {
        session = nil
        synchronize()
    }

    func stop() { deadlineTask?.cancel(); deadlineTask = nil }

    private func synchronize() {
        deadlineTask?.cancel()
        deadlineTask = nil
        if var current = session {
            current.finishIfDue(at: Date())
            session = current
            if let data = try? JSONEncoder().encode(current) { UserDefaults.standard.set(data, forKey: storageKey) }
        } else { UserDefaults.standard.removeObject(forKey: storageKey) }
        ActivityCoordinator.shared.setTimer(session)
        guard let current = session, current.phase == .running else { return }
        let id = current.id
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(current.remaining(at: Date()))) }
            catch { return }
            guard !Task.isCancelled, self?.session?.id == id else { return }
            self?.synchronize()
        }
    }
}
