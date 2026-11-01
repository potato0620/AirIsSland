import Foundation

/// Activity layer: facts about ongoing work, without views, timers or window operations.
enum IslandActivityKind: String, CaseIterable {
    case music, musicChange, volume, brightness, backlight, mic, power

    var isSystemFeedback: Bool {
        switch self {
        case .volume, .brightness, .backlight, .mic: return true
        case .music, .musicChange, .power: return false
        }
    }
}

struct IslandActivity: Equatable {
    let kind: IslandActivityKind
    var value: Double = 0
    var icon: String = ""
}
