import Foundation

enum IslandPage: Int, CaseIterable, Identifiable {
    case music, reminders, timer
    var id: Self { self }

    var activityKind: IslandActivityKind {
        switch self {
        case .music: return .music
        case .reminders: return .reminders
        case .timer: return .timer
        }
    }
}

/// Presentation interaction only. It never owns activities, priorities or expiry.
struct IslandPager {
    private(set) var selection: IslandPage = .music
    private(set) var position: Double = 0
    private var origin: Double = 0
    private var anchor = 0
    private var raw: Double = 0
    private var speed: Double = 0
    private var committed = false

    mutating func select(_ page: IslandPage) {
        selection = page
        position = Double(page.rawValue)
        committed = true
    }

    mutating func begin() {
        origin = Double(selection.rawValue)
        anchor = selection.rawValue
        raw = origin
        position = origin
        speed = 0
        committed = false
    }

    /// Returns a page once, at the threshold. Momentum must not be passed here.
    mutating func drag(delta: Double, seconds: Double) -> IslandPage? {
        guard !committed else { return nil }
        let dt = max(0.008, seconds)
        let instantaneous = min(6, abs(delta / dt))
        speed += (instantaneous - speed) * (1 - exp(-dt / 0.045))
        let gain = 0.55 + 0.45 * (1 - exp(-speed / 1.1))
        raw += delta * gain
        let last = IslandPage.allCases.count - 1
        let lower = Double(max(0, anchor - 1)), upper = Double(min(last, anchor + 1))
        func rubber(_ distance: Double) -> Double { 0.55 * distance / (1 + 0.55 * distance) }
        if raw < lower { position = lower == 0 ? lower - rubber(lower - raw) : lower }
        else if raw > upper { position = upper == Double(last) ? upper + rubber(raw - upper) : upper }
        else { position = raw }
        let displacement = position - origin
        guard abs(displacement) >= 0.16,
              let page = IslandPage(rawValue: anchor + (displacement > 0 ? 1 : -1)) else { return nil }
        selection = page
        position = Double(page.rawValue)
        committed = true
        return page
    }

    mutating func end() { position = Double(selection.rawValue) }
}
