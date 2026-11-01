import Foundation

enum AlbumArtFlipDirection {
    case next
    case previous

    var rotation: Double { self == .next ? -180 : 180 }
}

/// Metadata can arrive before the cover, and the item ID can arrive after the title.
/// Keep one identity across metadata enrichment and artwork quality upgrades.
struct AlbumArtworkTrackTracker {
    private(set) var identifier = UUID()
    private var bundleIdentifier: String?
    private var title = ""
    private var sourceTrackIdentifier: String?

    mutating func update(bundleIdentifier: String, title: String, sourceTrackIdentifier: String?) -> UUID {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceID = sourceTrackIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        let sameSource = sourceID != nil && sourceID == self.sourceTrackIdentifier
        let changedSource = sourceID != nil && self.sourceTrackIdentifier != nil && !sameSource
        let changedTitle = !title.isEmpty && !self.title.isEmpty && title != self.title
        let changedTrack = self.bundleIdentifier != bundleIdentifier || changedSource || (changedTitle && !sameSource)

        if changedTrack {
            identifier = UUID()
            self.title = title
            self.sourceTrackIdentifier = sourceID
        } else {
            if !title.isEmpty { self.title = title }
            if let sourceID { self.sourceTrackIdentifier = sourceID }
        }
        self.bundleIdentifier = bundleIdentifier
        return identifier
    }
}

/// A refinement replaces the current destination face, including during a flip.
/// While a flip runs, coalesce later tracks to the newest cover and direction.
struct AlbumArtworkTransition<Artwork> {
    struct Update {
        var artwork: Artwork
        var trackIdentifier: UUID
        var direction: AlbumArtFlipDirection
    }

    enum Change {
        case replace(Artwork)
        case flip(Artwork, AlbumArtFlipDirection)
    }

    private(set) var target: Update
    private(set) var isAnimating = false
    private var pending: Update?

    init(_ initial: Update) { target = initial }

    mutating func receive(_ update: Update) -> Change? {
        if update.trackIdentifier == target.trackIdentifier {
            target = update
            pending = nil
            return .replace(update.artwork)
        }
        if isAnimating {
            pending = update
            return nil
        }
        target = update
        isAnimating = true
        return .flip(update.artwork, update.direction)
    }

    mutating func complete() -> Change? {
        isAnimating = false
        guard let latest = pending else { return nil }
        pending = nil
        return receive(latest)
    }

    mutating func reset(_ update: Update) {
        target = update
        pending = nil
        isAnimating = false
    }
}
