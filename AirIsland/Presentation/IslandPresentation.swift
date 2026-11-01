import Foundation

/// Presentation layer: maps the scheduled activity to a single visual surface.
/// User-driven expanded content (music or shelf) is independent of transient emphasis.
enum IslandPresentation: Equatable {
    case idle
    case music(peek: Bool)
    case feedback(IslandActivity)
    case power

    init(activity: IslandActivity?) {
        guard let activity else { self = .idle; return }
        switch activity.kind {
        case .music: self = .music(peek: false)
        case .musicChange: self = .music(peek: true)
        case .power: self = .power
        case .volume, .brightness, .backlight, .mic: self = .feedback(activity)
        }
    }

    var showsMusic: Bool {
        if case .music = self { return true }
        return false
    }

    var showsMusicPeek: Bool { self == .music(peek: true) }

    var feedback: IslandActivity? {
        if case .feedback(let activity) = self { return activity }
        return nil
    }
}
