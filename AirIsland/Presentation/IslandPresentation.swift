import Foundation

/// Presentation layer: maps the scheduled activity to a single visual surface.
/// User-driven expanded music controls is independent of transient emphasis.
enum IslandPresentation: Equatable {
    case idle
    case music(peek: Bool)
    case feedback(IslandActivity)
    case power
    case timer(finished: Bool)

    init(activity: IslandActivity?) {
        guard let activity else { self = .idle; return }
        switch activity.kind {
        case .music: self = .music(peek: false)
        case .musicChange: self = .music(peek: true)
        case .power: self = .power
        case .timer: self = .timer(finished: false)
        case .timerFinished: self = .timer(finished: true)
        case .reminders: self = .idle
        case .volume, .brightness, .backlight, .mic: self = .feedback(activity)
        }
    }

    var showsMusic: Bool {
        if case .music = self { return true }
        return false
    }

    var showsMusicPeek: Bool { self == .music(peek: true) }
    var showsMusicSpectrum: Bool { self == .music(peek: false) }

    /// Pending timer completion uses the existing full panel until acknowledged.
    var requiresExpandedTimer: Bool { self == .timer(finished: true) }

    var feedback: IslandActivity? {
        if case .feedback(let activity) = self { return activity }
        return nil
    }
}
