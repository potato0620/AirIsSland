import Foundation

/// Activity layer: facts about ongoing work, without views, timers or window operations.
enum IslandActivityKind: String, CaseIterable {
    case music, musicChange, volume, brightness, backlight, mic, power
    case timer, timerFinished, reminders

    var isSystemFeedback: Bool {
        switch self {
        case .volume, .brightness, .backlight, .mic: return true
        case .music, .musicChange, .power, .timer, .timerFinished, .reminders: return false
        }
    }
}

struct IslandActivity: Equatable {
    let kind: IslandActivityKind
    var value: Double = 0
    var icon: String = ""
    var timer: TimerSession?
    var reminders: [ReminderTask] = []
}
