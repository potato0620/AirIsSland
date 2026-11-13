import Foundation
import Darwin

struct NowPlayingUpdate: Decodable {
    let payload: NowPlayingPayload
    let diff: Bool?

    func applying(to previous: PlaybackState, now: Date = Date()) -> PlaybackState {
        var state = previous
        if diff != true {
            state = PlaybackState(bundleIdentifier: "")
            state.title = ""
            state.artist = ""
            state.album = ""
            state.lastUpdated = now
        }

        state.title = payload.resolve(.title, payload.title, keeping: state.title, cleared: "")
        state.artist = payload.resolve(.artist, payload.artist, keeping: state.artist, cleared: "")
        state.album = payload.resolve(.album, payload.album, keeping: state.album, cleared: "")
        state.duration = payload.resolve(.duration, payload.duration, keeping: state.duration, cleared: 0)
        state.isPlaying = payload.resolve(.playing, payload.playing, keeping: state.isPlaying, cleared: false)
        state.playbackRate = payload.resolve(.playbackRate, payload.playbackRate, keeping: state.playbackRate, cleared: 1)
        state.volume = payload.resolve(.volume, payload.volume, keeping: state.volume, cleared: 0.5)
        let bundleID = payload.resolve(.bundleIdentifier, payload.bundleIdentifier, keeping: state.bundleIdentifier, cleared: "")
        state.bundleIdentifier = payload.parentApplicationBundleIdentifier ?? bundleID
        if let identifier = payload.contentItemIdentifier {
            state.sourceTrackIdentifier = identifier
        } else if payload.clearedFields.contains(.contentItemIdentifier) {
            state.sourceTrackIdentifier = nil
        }

        if let mode = payload.shuffleMode {
            state.isShuffled = mode != 1
        } else if payload.clearedFields.contains(.shuffleMode) {
            state.isShuffled = false
        }
        if let mode = payload.repeatMode {
            state.repeatMode = RepeatMode(rawValue: mode) ?? .off
        } else if payload.clearedFields.contains(.repeatMode) {
            state.repeatMode = .off
        }

        // An omitted field in a diff is unchanged; an explicit null removes it.
        if let artwork = payload.artworkData {
            state.artwork = Data(base64Encoded: artwork.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if payload.clearedFields.contains(.artworkData) {
            state.artwork = nil
        }

        let timestamp = payload.timestampEpochMicros.map { Date(timeIntervalSince1970: $0 / 1_000_000) }
            ?? payload.timestamp.flatMap(Self.parseTimestamp)
        if let elapsed = payload.elapsedTime {
            state.currentTime = elapsed
            state.lastUpdated = timestamp ?? now
        } else if payload.clearedFields.contains(.elapsedTime) {
            state.currentTime = 0
            state.lastUpdated = timestamp ?? now
        } else if let timestamp {
            // A diff omits an unchanged elapsed value. A new timestamp is the
            // source's new anchor for that same value, not time to add again.
            state.lastUpdated = timestamp
        } else if diff == true,
                  previous.isPlaying != state.isPlaying || previous.playbackRate != state.playbackRate {
            // Rate and playing can arrive separately. Move the anchor using the
            // previous rate before stopping it, or a rate-only pause rewinds to
            // the last elapsed-time sample. Explicit seek positions above win.
            let delta = max(0, now.timeIntervalSince(previous.lastUpdated))
            let position = previous.currentTime + (previous.isPlaying ? delta * previous.playbackRate : 0)
            state.currentTime = state.duration > 0 ? min(position, state.duration) : position
            state.lastUpdated = now
        } else if previous.isPlaying != state.isPlaying {
            state.lastUpdated = now
        }
        return state
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct NowPlayingPayload: Decodable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let timestampEpochMicros: Double?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
    let volume: Double?
    let contentItemIdentifier: String?
    let clearedFields: Set<CodingKeys>

    enum CodingKeys: String, CodingKey {
        case title, artist, album, duration, elapsedTime, shuffleMode, repeatMode
        case artworkData, timestamp, playbackRate, playing
        case parentApplicationBundleIdentifier, bundleIdentifier, volume
        case contentItemIdentifier
        case durationMicros, elapsedTimeMicros, timestampEpochMicros
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var cleared = Set(try values.allKeys.filter { try values.decodeNil(forKey: $0) })
        if cleared.contains(.durationMicros) { cleared.insert(.duration) }
        if cleared.contains(.elapsedTimeMicros) { cleared.insert(.elapsedTime) }
        clearedFields = cleared
        title = try values.decodeIfPresent(String.self, forKey: .title)
        artist = try values.decodeIfPresent(String.self, forKey: .artist)
        album = try values.decodeIfPresent(String.self, forKey: .album)
        duration = try values.contains(.durationMicros)
            ? values.decodeIfPresent(Double.self, forKey: .durationMicros).map { $0 / 1_000_000 }
            : values.decodeIfPresent(Double.self, forKey: .duration)
        elapsedTime = try values.contains(.elapsedTimeMicros)
            ? values.decodeIfPresent(Double.self, forKey: .elapsedTimeMicros).map { $0 / 1_000_000 }
            : values.decodeIfPresent(Double.self, forKey: .elapsedTime)
        shuffleMode = try values.decodeIfPresent(Int.self, forKey: .shuffleMode)
        repeatMode = try values.decodeIfPresent(Int.self, forKey: .repeatMode)
        artworkData = try values.decodeIfPresent(String.self, forKey: .artworkData)
        timestamp = try values.decodeIfPresent(String.self, forKey: .timestamp)
        timestampEpochMicros = try values.decodeIfPresent(Double.self, forKey: .timestampEpochMicros)
        playbackRate = try values.decodeIfPresent(Double.self, forKey: .playbackRate)
        playing = try values.decodeIfPresent(Bool.self, forKey: .playing)
        parentApplicationBundleIdentifier = try values.decodeIfPresent(String.self, forKey: .parentApplicationBundleIdentifier)
        bundleIdentifier = try values.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        volume = try values.decodeIfPresent(Double.self, forKey: .volume)
        contentItemIdentifier = try values.decodeIfPresent(String.self, forKey: .contentItemIdentifier)
    }

    func resolve<T>(_ key: CodingKeys, _ value: T?, keeping current: T, cleared empty: T) -> T {
        clearedFields.contains(key) ? empty : (value ?? current)
    }
}

/// NetEase can publish a valid track, then a pause diff and an empty snapshot
/// while audio continues. Keep the last valid track through that sequence,
/// without changing playback in the source application.
struct NowPlayingPlaybackSession {
    static let neteaseBundleIdentifier = "com.netease.163music"
    static let trackChangeTimeout: TimeInterval = 8
    private var rawState = Self.emptyState()
    private(set) var state = Self.emptyState()
    private var pendingPause: PlaybackState?
    private var playbackBeforePendingPause: PlaybackState?
    private(set) var pauseDeadline: Date?
    private(set) var trackChangeDeadline: Date?
    private var trackChangeOrigin: (bundle: String, title: String)?

    /// This is command acknowledgement, not a claim that audio is playing.
    /// Bound missing/failed responses and keep the source's actual playback rate.
    mutating func beginTrackChange(now: Date = Date()) -> PlaybackState {
        guard (state.isPlaying || state.isChangingTrack), !state.bundleIdentifier.isEmpty else { return state }
        trackChangeOrigin = (state.bundleIdentifier, state.title)
        trackChangeDeadline = now.addingTimeInterval(Self.trackChangeTimeout)
        state.isChangingTrack = true
        return state
    }

    mutating func cancelTrackChange() -> PlaybackState {
        trackChangeOrigin = nil
        trackChangeDeadline = nil
        state.isChangingTrack = false
        return state
    }

    private mutating func refreshTrackChange(now: Date) -> PlaybackState {
        if let origin = trackChangeOrigin, let deadline = trackChangeDeadline {
            // NetEase emits temporary item IDs and playing=true at rate=0
            // before the destination metadata is ready. Neither acknowledges a load.
            let destinationIsAdvancing = state.title != origin.title
                && rawState.isPlaying && rawState.playbackRate > 0
            if now >= deadline || state.bundleIdentifier != origin.bundle || destinationIsAdvancing {
                _ = cancelTrackChange()
            }
        }
        state.isChangingTrack = trackChangeDeadline != nil
        return state
    }

    mutating func receive(_ update: NowPlayingUpdate, neteaseIsRunning: Bool, now: Date = Date()) -> PlaybackState {
        rawState = update.applying(to: rawState, now: now)
        var next = rawState

        if next.title.isEmpty,
           state.bundleIdentifier == Self.neteaseBundleIdentifier,
           !state.title.isEmpty,
           neteaseIsRunning,
           next.bundleIdentifier.isEmpty || next.bundleIdentifier == Self.neteaseBundleIdentifier {
            // An empty snapshot invalidates NetEase's transient pause. Restore
            // the advancing anchor, including its rate, without losing metadata
            // reconciled while the confirmation was pending.
            if let previous = playbackBeforePendingPause {
                state.currentTime = previous.currentTime
                state.lastUpdated = previous.lastUpdated
                state.playbackRate = previous.playbackRate
            }
            cancelPendingPause()
            // A completed track should stop at its end even if the player never
            // sends another valid snapshot. Retain its metadata like a paused track.
            if state.duration > 0, position(of: state, at: now) >= state.duration {
                state.currentTime = state.duration
                state.isPlaying = false
                state.playbackRate = 0
                state.lastUpdated = now
            }
            return refreshTrackChange(now: now)
        }

        if next.bundleIdentifier == Self.neteaseBundleIdentifier {
            if state.bundleIdentifier == Self.neteaseBundleIdentifier,
               !state.title.isEmpty, next.title != state.title {
                // During a switch NetEase can also attach the preceding track's
                // elapsed time and timestamp to the new title. Establish a fresh
                // anchor; later position/seek updates for this track remain valid.
                next.currentTime = 0
                next.lastUpdated = now
                // A title-only diff still carries the old raw cover. Wait for
                // artwork explicitly supplied for this destination instead.
                if update.payload.artworkData == nil { next.artwork = nil }
            }
            // NetEase regenerates Now Playing item UUIDs during one load.
            // Preserve the established identity while its track metadata agrees.
            if sameTrack(next, state) { next.sourceTrackIdentifier = state.sourceTrackIdentifier }
            if sameTrack(next, state), next.artwork == nil,
               !update.payload.clearedFields.contains(.artworkData) {
                next.artwork = state.artwork
            }
            // A playing-only resume may omit the new rate. An explicit zero
            // rate is a real stop and must not be turned back into progress.
            // Requested loads still require the source's positive rate.
            if update.payload.playing == true, update.payload.playbackRate == nil,
               !update.payload.clearedFields.contains(.playbackRate),
               next.playbackRate <= 0, trackChangeDeadline == nil {
                next.playbackRate = 1
            }
            rawState = next

            if update.diff == true, !next.isPlaying,
               state.isPlaying, sameTrack(next, state) {
                if pendingPause == nil { playbackBeforePendingPause = state }
                pendingPause = next
                if pauseDeadline == nil { pauseDeadline = now.addingTimeInterval(0.3) }
                // Keep the playback-state debounce, but stop extrapolating at
                // the pause position now. Confirmation must not rewind the bar
                // by the time spent waiting for this deadline.
                state.currentTime = next.currentTime
                state.lastUpdated = next.lastUpdated
                state.playbackRate = 0
                return refreshTrackChange(now: now)
            }
        }

        cancelPendingPause()
        state = next
        return refreshTrackChange(now: now)
    }

    mutating func confirmPendingPause(now: Date = Date()) -> PlaybackState {
        if let deadline = pauseDeadline, now >= deadline, let pause = pendingPause {
            state = pause
            cancelPendingPause()
        }
        return refreshTrackChange(now: now)
    }

    mutating func sourceDidTerminate(bundleIdentifier: String) -> PlaybackState {
        if state.bundleIdentifier == bundleIdentifier {
            rawState = Self.emptyState()
            state = rawState
            cancelPendingPause()
            _ = cancelTrackChange()
        }
        return state
    }

    mutating func reconcile(_ metadata: NetEaseTrackMetadata, artwork: Data? = nil) -> PlaybackState {
        guard state.bundleIdentifier == Self.neteaseBundleIdentifier,
              state.title == metadata.title else { return state }
        state.artist = metadata.artist
        state.album = metadata.album
        state.duration = metadata.duration
        if let artwork { state.artwork = artwork }
        if rawState.bundleIdentifier == state.bundleIdentifier, rawState.title == state.title {
            rawState.artist = state.artist
            rawState.album = state.album
            rawState.duration = state.duration
            if let artwork { rawState.artwork = artwork }
        }
        if var pause = pendingPause, pause.title == state.title {
            pause.artist = state.artist
            pause.album = state.album
            pause.duration = state.duration
            if let artwork { pause.artwork = artwork }
            pendingPause = pause
        }
        return state
    }

    private mutating func cancelPendingPause() {
        pendingPause = nil
        playbackBeforePendingPause = nil
        pauseDeadline = nil
    }

    private func sameTrack(_ lhs: PlaybackState, _ rhs: PlaybackState) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.title == rhs.title
            && lhs.artist == rhs.artist && lhs.album == rhs.album
    }

    private func position(of state: PlaybackState, at date: Date) -> Double {
        state.currentTime + (state.isPlaying ? max(0, date.timeIntervalSince(state.lastUpdated)) * state.playbackRate : 0)
    }

    private static func emptyState() -> PlaybackState {
        var state = PlaybackState(bundleIdentifier: "")
        state.title = ""
        state.artist = ""
        state.album = ""
        return state
    }
}

/// Keep bytes until a complete JSON line arrives. Pipe reads can split a UTF-8 character.
struct JSONLineBuffer {
    private var bytes = Data()

    mutating func append(_ data: Data) -> [Data] {
        bytes.append(data)
        var lines: [Data] = []
        while let newline = bytes.firstIndex(of: 0x0A) {
            let line = Data(bytes[..<newline])
            bytes.removeSubrange(...newline)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    mutating func finish() -> Data? {
        defer { bytes.removeAll() }
        return bytes.isEmpty ? nil : bytes
    }
}

actor JSONLinesPipeHandler {
    private let pipe: Pipe
    private var continuation: AsyncStream<Data>.Continuation?
    private var isClosed = false

    init(pipe: Pipe = Pipe()) {
        self.pipe = pipe
    }

    func getPipe() -> Pipe { pipe }

    func closeWritingEnd() throws {
        // The child owns a duplicate after launch. Keeping our writer open hides EOF.
        try pipe.fileHandleForWriting.close()
    }

    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async throws {
        guard !isClosed else { return }
        let handle = pipe.fileHandleForReading
        let descriptor = handle.fileDescriptor
        let stream = AsyncStream<Data> { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak handle] _ in
                handle?.readabilityHandler = nil
            }
            handle.readabilityHandler = { _ in
                // FileHandle.read(upToCount:) can wait for the requested length
                // on a live pipe. A single POSIX read returns the bytes available
                // now, so small snapshots do not wait for more updates or EOF.
                var data = Data(count: 65_536)
                var count: Int
                repeat {
                    count = data.withUnsafeMutableBytes { bytes in
                        Darwin.read(descriptor, bytes.baseAddress, bytes.count)
                    }
                } while count < 0 && errno == EINTR

                if count > 0 {
                    data.count = count
                    continuation.yield(data)
                } else if count == 0 || (errno != EAGAIN && errno != EWOULDBLOCK) {
                    continuation.finish()
                }
            }
        }
        defer {
            handle.readabilityHandler = nil
            continuation?.finish()
            continuation = nil
        }

        var buffer = JSONLineBuffer()
        let decoder = JSONDecoder()
        for await data in stream {
            try Task.checkCancellation()
            for line in buffer.append(data) {
                try Task.checkCancellation()
                try await onLine(decoder.decode(type, from: line))
            }
        }
        try Task.checkCancellation()
        if let lastLine = buffer.finish() {
            try await onLine(decoder.decode(type, from: lastLine))
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        pipe.fileHandleForReading.readabilityHandler = nil
        continuation?.finish()
        continuation = nil
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
    }
}
