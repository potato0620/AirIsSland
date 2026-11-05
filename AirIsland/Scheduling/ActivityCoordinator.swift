import Combine
import Defaults
import Foundation

/// Runtime owner of scheduling and expiry. Providers submit facts; views observe one winner.
@MainActor
final class ActivityCoordinator: ObservableObject {
    static let shared = ActivityCoordinator()

    @Published private(set) var current: IslandActivity?
    @Published private(set) var timer: TimerSession?
    @Published private(set) var reminders: [ReminderTask] = []
    @Published private(set) var spectrumRequest: MusicSpectrumRequest?
    // A separate payload publisher avoids reevaluating the whole island at audio cadence.
    private let spectrumValues = CurrentValueSubject<[Double], Never>(MusicSpectrumState.quiet)
    var spectrumLevels: AnyPublisher<[Double], Never> { spectrumValues.eraseToAnyPublisher() }
    var spectrumSnapshot: [Double] { spectrum.levels }
    private var spectrum = MusicSpectrumState()
    // The value distinguishes an explicitly visible music page from compact activity content.
    private var spectrumConsumers: [UUID: Bool] = [:]
    private var spectrumBundle: String?
    private var spectrumPlaying = false
    private var spectrumTrack: UUID?
    private var scheduler = ActivityScheduler()
    private var expiryTask: Task<Void, Never>?
    private var preferences = Set<AnyCancellable>()
    private var musicIsActive = false

    private init() {
        Defaults.publisher(.timerActivityEnabled).sink { [weak self] _ in
            Task { @MainActor in if !Defaults[.timerActivityEnabled] { self?.setTimer(nil) } }
        }.store(in: &preferences)
        Defaults.publisher(.remindersActivityEnabled).sink { [weak self] _ in
            Task { @MainActor in if !Defaults[.remindersActivityEnabled] { self?.setReminders([]) } }
        }.store(in: &preferences)
        Defaults.publisher(.musicLiveActivityEnabled).sink { [weak self] _ in
            Task { @MainActor in self?.refreshMusic() }
        }.store(in: &preferences)
        Defaults.publisher(.hudReplacement).sink { [weak self] change in
            guard !change.newValue else { return }
            Task { @MainActor in
                guard let self else { return }
                for kind in IslandActivityKind.allCases where kind.isSystemFeedback {
                    self.scheduler.end(kind)
                }
                self.refresh()
            }
        }.store(in: &preferences)
        Defaults.publisher(.showPowerStatusNotifications).sink { [weak self] change in
            guard !change.newValue else { return }
            Task { @MainActor in self?.end(.power) }
        }.store(in: &preferences)
        Defaults.publisher(.enableSneakPeek).sink { [weak self] change in
            guard !change.newValue else { return }
            Task { @MainActor in self?.end(.musicChange) }
        }.store(in: &preferences)
    }

    func setMusicActive(_ active: Bool) {
        guard musicIsActive != active else { return }
        musicIsActive = active
        refreshMusic()
        if !active { end(.musicChange) }
    }

    func setMusicSpectrumSource(bundleIdentifier: String?, playing: Bool, trackIdentifier: UUID? = nil) {
        spectrumBundle = bundleIdentifier
        spectrumPlaying = playing
        spectrumTrack = trackIdentifier
        refreshSpectrum()
    }

    func setSpectrumVisible(_ visible: Bool, consumer: UUID, expanded: Bool = false) {
        if visible { spectrumConsumers[consumer] = expanded } else { spectrumConsumers.removeValue(forKey: consumer) }
        refreshSpectrum()
    }

    func receiveSpectrum(_ values: [Double], for request: MusicSpectrumRequest) {
        guard spectrum.receive(values, for: request) else { return }
        spectrumValues.send(spectrum.levels)
    }

    private func refreshSpectrum() {
        let expandedMusic = spectrumConsumers.values.contains(true)
        let compactMusic = current?.kind == .music && spectrumConsumers.values.contains(false)
        spectrum.update(enabled: Defaults[.musicLiveActivityEnabled] || expandedMusic,
                        playing: spectrumPlaying && musicIsActive, bundleIdentifier: spectrumBundle, trackIdentifier: spectrumTrack,
                        visible: compactMusic || expandedMusic)
        if spectrumRequest != spectrum.request {
            spectrumRequest = spectrum.request
            spectrumValues.send(MusicSpectrumState.quiet)
        }
    }

    func post(_ kind: IslandActivityKind, value: Double = 0, icon: String = "") {
        if kind.isSystemFeedback && !Defaults[.hudReplacement] { return }
        if kind == .power && !Defaults[.showPowerStatusNotifications] { return }
        scheduler.submit(IslandActivity(kind: kind, value: min(max(value, 0), 1), icon: icon), at: now)
        refresh()
    }

    func end(_ kind: IslandActivityKind) {
        scheduler.end(kind)
        refresh()
    }

    func prefer(_ kind: IslandActivityKind) {
        scheduler.prefer(kind, at: now)
        refresh()
    }

    func setTimer(_ session: TimerSession?) {
        let session = Defaults[.timerActivityEnabled] ? session : nil
        let previous = timer
        timer = session
        if let session {
            if session.phase == .finished {
                // Completion needs acknowledgement; never restore a compact "ended" timer.
                scheduler.end(.timer)
                if previous?.id != session.id || previous?.phase != .finished {
                    scheduler.submit(IslandActivity(kind: .timerFinished, timer: session), at: now)
                }
            } else {
                scheduler.submit(IslandActivity(kind: .timer, timer: session), at: now)
                scheduler.end(.timerFinished)
            }
        } else {
            scheduler.end(.timer)
            scheduler.end(.timerFinished)
        }
        refresh()
    }

    func setReminders(_ tasks: [ReminderTask]) {
        let tasks = Defaults[.remindersActivityEnabled] ? tasks : []
        reminders = tasks
        if tasks.isEmpty { scheduler.end(.reminders) }
        else { scheduler.submit(IslandActivity(kind: .reminders, reminders: tasks), at: now) }
        refresh()
    }

    func updateFeedbackValue(_ value: Double) {
        guard let current, current.kind.isSystemFeedback else { return }
        post(current.kind, value: value, icon: current.icon)
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func refreshMusic() {
        if musicIsActive && Defaults[.musicLiveActivityEnabled] {
            scheduler.submit(IslandActivity(kind: .music), at: now)
        } else {
            scheduler.end(.music)
        }
        refresh()
    }

    private func refresh() {
        let timestamp = now
        scheduler.expire(at: timestamp)
        let selected = scheduler.current(at: timestamp)
        if current != selected { current = selected }
        refreshSpectrum()
        expiryTask?.cancel()
        guard let expiry = scheduler.nextExpiry else { return }
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, expiry - timestamp))) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
