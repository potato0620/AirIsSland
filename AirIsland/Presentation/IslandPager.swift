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
    private(set) var pages: [IslandPage] = IslandPage.allCases
    private(set) var selection: IslandPage = .music
    private(set) var position: Double = 0
    private var origin: Double = 0
    private var anchor = 0
    private var raw: Double = 0
    private var speed: Double = 0
    private var committed = false

    mutating func updatePages(_ pages: [IslandPage]) {
        let available = IslandPage.allCases.filter { pages.contains($0) }
        let next = available.isEmpty ? [.music] : available
        guard next != self.pages else { return }
        self.pages = next
        select(next.contains(selection) ? selection : next[0])
    }

    mutating func select(_ page: IslandPage) {
        guard let index = pages.firstIndex(of: page) else { return }
        selection = page
        position = Double(index)
        committed = true
    }

    mutating func begin() {
        anchor = pages.firstIndex(of: selection) ?? 0
        origin = Double(anchor)
        raw = origin
        position = origin
        speed = 0
        committed = false
    }

    /// Returns a page once, at the threshold. Momentum must not be passed here.
    mutating func drag(delta: Double, seconds: Double) -> IslandPage? {
        guard !committed, pages.count > 1 else { return nil }
        let dt = max(0.008, seconds)
        let instantaneous = min(6, abs(delta / dt))
        speed += (instantaneous - speed) * (1 - exp(-dt / 0.045))
        let gain = 0.55 + 0.45 * (1 - exp(-speed / 1.1))
        raw += delta * gain
        let last = pages.count - 1
        let lower = Double(max(0, anchor - 1)), upper = Double(min(last, anchor + 1))
        func rubber(_ distance: Double) -> Double { 0.55 * distance / (1 + 0.55 * distance) }
        if raw < lower { position = lower == 0 ? lower - rubber(lower - raw) : lower }
        else if raw > upper { position = upper == Double(last) ? upper + rubber(raw - upper) : upper }
        else { position = raw }
        let displacement = position - origin
        let index = anchor + (displacement > 0 ? 1 : -1)
        guard abs(displacement) >= 0.16, pages.indices.contains(index) else { return nil }
        let page = pages[index]
        selection = page
        position = Double(index)
        committed = true
        return page
    }

    mutating func end() { position = Double(pages.firstIndex(of: selection) ?? 0) }
}
