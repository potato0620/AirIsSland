import Foundation

struct NetEaseTrackMetadata: Codable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let artworkURL: URL?
}

/// Reads only the two playback-queue files. No account, cookies, or listening
/// history is needed to reconcile the metadata published during a track switch.
enum NetEaseQueueCatalog {
    static func tracks(in data: Data) -> [NetEaseTrackMetadata] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["list"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            var track = entry["track"] as? [String: Any]
            if track == nil, let json = entry["track"] as? String,
               let bytes = json.data(using: .utf8) {
                track = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
            }
            guard let track,
                  let title = track["name"] as? String, !title.isEmpty,
                  let milliseconds = (track["duration"] ?? track["dt"]) as? NSNumber,
                  milliseconds.doubleValue > 0 else { return nil }
            let artists = (track["artists"] ?? track["ar"]) as? [[String: Any]] ?? []
            let names = artists.compactMap { $0["name"] as? String }
            let album = (track["album"] ?? track["al"]) as? [String: Any] ?? [:]
            var artworkURL: URL?
            if let value = (album["picUrl"] ?? album["cover"]) as? String,
               var components = URLComponents(string: value),
               let host = components.host?.lowercased(),
               host == "music.126.net" || host.hasSuffix(".music.126.net"),
               components.scheme == "http" || components.scheme == "https" {
                components.scheme = "https"
                components.query = "param=300y300"
                artworkURL = components.url
            }
            return NetEaseTrackMetadata(
                id: String(describing: track["id"] ?? ""), title: title,
                artist: names.joined(separator: " / "), album: album["name"] as? String ?? "",
                duration: milliseconds.doubleValue / 1000, artworkURL: artworkURL
            )
        }
    }

    static func match(in tracks: [NetEaseTrackMetadata], title: String, artist: String) -> NetEaseTrackMetadata? {
        let matches = tracks.filter { normalized($0.title) == normalized(title) }
        // Queue files can include the same song more than once.
        let unique = Dictionary(matches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        let exactArtist = unique.filter { normalized($0.artist) == normalized(artist) }
        if exactArtist.count == 1 { return exactArtist.first }
        // The source can briefly retain the previous artist. A unique title is
        // safe to reconcile; ambiguous titles must wait for a matching artist.
        return unique.count == 1 ? unique.first : nil
    }

    private static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
