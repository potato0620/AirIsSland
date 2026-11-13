import Foundation

enum IslandPage: Int, CaseIterable, Identifiable {
    case music, reminders, timer, codex
    var id: Self { self }

    var activityKind: IslandActivityKind {
        switch self {
        case .music: return .music
        case .reminders: return .reminders
        case .timer: return .timer
        case .codex: return .codex
        }
    }

    var identifier: String {
        switch self {
        case .music: return "music"
        case .reminders: return "reminders"
        case .timer: return "timer"
        case .codex: return "codex"
        }
    }

    init?(identifier: String) {
        switch identifier {
        case "music": self = .music
        case "reminders": self = .reminders
        case "timer": self = .timer
        case "codex": self = .codex
        default: return nil
        }
    }

    static let defaultOrder = "music,reminders,timer,codex"

    /// Unknown and duplicate identifiers are dropped; missing pages keep their
    /// default relative order at the end, so an upgrade never hides a page.
    static func ordered(from raw: String) -> [IslandPage] {
        var result: [IslandPage] = []
        for value in raw.split(separator: ",") {
            guard let page = IslandPage(identifier: value.trimmingCharacters(in: .whitespaces)),
                  !result.contains(page) else { continue }
            result.append(page)
        }
        for page in IslandPage.allCases where !result.contains(page) {
            result.append(page)
        }
        return result
    }

    static func moving(_ raw: String, _ page: IslandPage, by offset: Int) -> String {
        var pages = ordered(from: raw)
        guard let index = pages.firstIndex(of: page) else { return raw }
        let target = min(max(0, index + offset), pages.count - 1)
        guard target != index else { return raw }
        pages.swapAt(index, target)
        return pages.map(\.identifier).joined(separator: ",")
    }
}

/// Presentation interaction only. It never owns activities, priorities or expiry.
struct IslandPager {
    private(set) var pages: [IslandPage] = IslandPage.allCases
    private(set) var selection: IslandPage = .music
    private(set) var lastBrowsedPage: IslandPage?
    private(set) var position: Double = 0
    private var origin: Double = 0
    private var anchor = 0
    private var raw: Double = 0
    private var speed: Double = 0
    private var committed = true

    mutating func updatePages(_ pages: [IslandPage]) {
        // Preserve the caller's order: it is the user's page order preference.
        var available: [IslandPage] = []
        for page in pages where !available.contains(page) { available.append(page) }
        let next = available.isEmpty ? [.music] : available
        guard next != self.pages else { return }
        self.pages = next
        if let lastBrowsedPage, !next.contains(lastBrowsedPage) { self.lastBrowsedPage = next[0] }
        select(next.contains(selection) ? selection : next[0])
    }

    mutating func select(_ page: IslandPage, manually: Bool = false) {
        guard let index = pages.firstIndex(of: page) else { return }
        if manually { lastBrowsedPage = page }
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
        lastBrowsedPage = page
        position = Double(index)
        committed = true
        return page
    }

    mutating func end() {
        position = Double(pages.firstIndex(of: selection) ?? 0)
        // Seal the gesture even when it returned without committing a page.
        // Late preparation/changed events cannot resurrect its accumulated distance.
        committed = true
    }
}
