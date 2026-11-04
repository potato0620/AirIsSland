//
//  MusicManager.swift
//  AirIsland
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//
import AppKit
import Combine
import Defaults
import SwiftUI

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

@MainActor
class MusicManager: ObservableObject {
    // MARK: - Properties
    static let shared = MusicManager()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Published properties for UI
    @Published var songTitle: String = ""
    @Published var artistName: String = ""
    @Published private(set) var albumArtTrackIdentifier = UUID()
    @Published var albumArt: NSImage = defaultImage
    @Published private(set) var albumArtFlipDirection: AlbumArtFlipDirection = .next
    @Published var isPlaying = false
    @Published private(set) var isChangingTrack = false
    var isPlaybackActive: Bool { isPlaying || isChangingTrack }
    @Published var album: String = ""
    @Published var isPlayerIdle: Bool = true
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported: Bool = true
    @Published var usingAppIconForArtwork: Bool = false
    @Published var canFavoriteTrack: Bool = false
    @Published var isFavoriteTrack: Bool = false

    private var artworkData: Data? = nil
    private var artworkTrack = AlbumArtworkTrackTracker()
    private var artworkAwaitingPlayback: UUID?
    private var pendingArtwork: (image: NSImage, trackIdentifier: UUID)?

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil
    private var lastAnnouncedTrackIdentifier: UUID?
    private var requestedArtworkFlip: (direction: AlbumArtFlipDirection, requestedAt: Date)?

    // MARK: - Initialization
    init() {
        // All media uses the system Now Playing source. Old source preferences
        // are intentionally ignored without clearing the user's other settings.
        guard let controller = NowPlayingController() else { return }
        activeController = controller
        canFavoriteTrack = controller.supportsFavorite

        controller.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, self.activeController === controller else { return }
                self.updateFromPlaybackState(state)
            }
            .store(in: &controllerCancellables)

        forceUpdate()
    }

    public func destroy() {
        debounceIdleTask?.cancel()
        pendingArtwork = nil
        artworkAwaitingPlayback = nil
        controllerCancellables.removeAll()

        ActivityCoordinator.shared.setMusicActive(false)
        ActivityCoordinator.shared.setMusicSpectrumSource(bundleIdentifier: nil, playing: false)
        // Release active controller
        activeController = nil
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        let wasActive = isPlaying || isChangingTrack
        self.isChangingTrack = state.isChangingTrack
        let previousTrackIdentifier = artworkTrack.identifier
        let trackIdentifier = artworkTrack.update(
            bundleIdentifier: state.bundleIdentifier,
            title: state.title,
            sourceTrackIdentifier: state.sourceTrackIdentifier,
            artist: state.artist,
            album: state.album
        )
        let trackChanged = trackIdentifier != previousTrackIdentifier
        if artworkAwaitingPlayback != trackIdentifier {
            artworkAwaitingPlayback = nil
            pendingArtwork = nil
        }
        if state.isChangingTrack {
            artworkAwaitingPlayback = trackIdentifier
        } else if state.isPlaying {
            artworkAwaitingPlayback = nil
            if let ready = pendingArtwork, ready.trackIdentifier == trackIdentifier {
                pendingArtwork = nil
                usingAppIconForArtwork = false
                updateAlbumArt(newAlbumArt: ready.image, trackIdentifier: trackIdentifier)
            }
        }
        // Check for playback state changes (playing/paused)
        if state.isPlaying != self.isPlaying {
            NSLog("Playback state changed: \(state.isPlaying ? "Playing" : "Paused")")
            withAnimation(.smooth) {
                self.isPlaying = state.isPlaying
            }
        }
        let isActive = state.isPlaying || state.isChangingTrack
        if wasActive != isActive { updateIdleState(state: isActive) }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier
        if trackChanged {
            if let request = requestedArtworkFlip,
               Date().timeIntervalSince(request.requestedAt) < NowPlayingPlaybackSession.trackChangeTimeout {
                albumArtFlipDirection = request.direction
            } else {
                albumArtFlipDirection = .next
                requestedArtworkFlip = nil
            }
            // Title, item identifier and artwork may arrive separately. Retain
            // the command briefly so these updates keep the same direction.
        }

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
        let artworkNeedsTrackBinding = state.artwork != nil && trackIdentifier != albumArtTrackIdentifier
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged || artworkNeedsTrackBinding

        // Handle artwork and visual transitions for changed content
        if hasContentChange {
            if artworkChanged || artworkNeedsTrackBinding, let artwork = state.artwork {
                self.updateArtwork(artwork, trackIdentifier: trackIdentifier)
            } else if state.artwork == nil,
                      bundleChanged || self.usingAppIconForArtwork || self.albumArt === defaultImage {
                // Keep a real cover while the same player's next cover loads.
                // Use the app icon on first load or when the player changes.
                if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    self.usingAppIconForArtwork = true
                    self.updateAlbumArt(newAlbumArt: appIconImage, trackIdentifier: trackIdentifier)
                }
            }
            self.artworkData = state.artwork

            // Tracks can share artwork. Acknowledge metadata changes independently
            // so subsequent progress updates do not repeatedly trigger a transition.
            self.lastArtworkTitle = state.title
            self.lastArtworkArtist = state.artist
            self.lastArtworkAlbum = state.album
            self.lastArtworkBundleIdentifier = state.bundleIdentifier
        }

        // Announce each playable song once. Progress, regenerated item IDs,
        // cover upgrades and seek-related pause/resume are not track changes.
        if state.isPlaying, !state.isChangingTrack,
           !state.title.isEmpty, !state.artist.isEmpty,
           lastAnnouncedTrackIdentifier != trackIdentifier {
            lastAnnouncedTrackIdentifier = trackIdentifier
            self.updateSneakPeek()
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = state.volume != self.volume
        
        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if timeChanged {
            self.elapsedTime = state.currentTime
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
            // Update volume control support from active controller
            self.volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        if state.isFavorite != self.isFavoriteTrack {
            self.isFavoriteTrack = state.isFavorite
        }
        
        if volumeChanged {
            self.volume = state.volume
        }
        
        ActivityCoordinator.shared.setMusicActive(isActive || !isPlayerIdle)
        ActivityCoordinator.shared.setMusicSpectrumSource(bundleIdentifier: state.bundleIdentifier,
                                                         playing: state.isPlaying && !state.isChangingTrack,
                                                         trackIdentifier: trackIdentifier)
        self.timestampDate = state.lastUpdated
    }

    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
        // Toggle based on current state
        setFavorite(!isFavoriteTrack)
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        Task { @MainActor in
            await controller.setFavorite(favorite)
            try? await Task.sleep(for: .milliseconds(150))
            await controller.updatePlaybackInfo()
        }
    }

    private func updateArtwork(_ artworkData: Data, trackIdentifier: UUID) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.artworkData == artworkData,
                          self.artworkTrack.identifier == trackIdentifier else { return }
                    if self.artworkAwaitingPlayback == trackIdentifier {
                        self.pendingArtwork = (artworkImage, trackIdentifier)
                        return
                    }
                    self.usingAppIconForArtwork = false
                    self.updateAlbumArt(newAlbumArt: artworkImage, trackIdentifier: trackIdentifier)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                do { try await Task.sleep(for: .seconds(Defaults[.waitInterval])) }
                catch { return }
                guard !Task.isCancelled else { return }
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                    ActivityCoordinator.shared.setMusicActive(self.isPlaying || !self.isPlayerIdle)
                }
            }
        }
    }

    private func updateAlbumArt(newAlbumArt: NSImage, trackIdentifier: UUID) {
        withAnimation(.smooth) {
            self.albumArtTrackIdentifier = trackIdentifier
            self.albumArt = newAlbumArt
            self.calculateAverageColor()
        }
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    private func calculateAverageColor() {
        let image = albumArt
        let trackIdentifier = albumArtTrackIdentifier
        image.averageColor { [weak self] color in
            DispatchQueue.main.async {
                guard let self, self.albumArt === image,
                      self.albumArtTrackIdentifier == trackIdentifier else { return }
                withAnimation(.smooth) {
                    self.avgColor = color ?? .white
                }
            }
        }
    }

    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] {
            ActivityCoordinator.shared.post(.musicChange)
        }
    }

    // MARK: - Public Methods for controlling playback
    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        Task {
            if isChangingTrack {
                await activeController?.pause()
            } else {
                await activeController?.togglePlay()
            }
        }
    }

    func nextTrack() {
        albumArtFlipDirection = .next
        requestedArtworkFlip = (.next, Date())
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        albumArtFlipDirection = .previous
        requestedArtworkFlip = (.previous, Date())
        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }
    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, elapsedTime + seconds), songDuration)
        seek(to: newPos)
    }
    
    func setVolume(to level: Double) {
        if let controller = activeController {
            Task {
                await controller.setVolume(level)
            }
        }
    }
    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                await self?.activeController?.updatePlaybackInfo()
            }
        }
    }
    
    
    func syncVolumeFromActiveApp() async {
        // Check if bundle identifier is valid and if the app is actually running
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { return }
        
        var script: String?
        if bundleID == "com.apple.Music" {
            script = """
            tell application "Music"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else if bundleID == "com.spotify.client" {
            script = """
            tell application "Spotify"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else {
            // For unsupported apps, don't sync volume
            return
        }
        
        if let volumeScript = script,
           let result = try? await AppleScriptHelper.execute(volumeScript) {
            let volumeValue = result.int32Value
            let currentVolume = Double(volumeValue) / 100.0
            
            await MainActor.run {
                if abs(currentVolume - self.volume) > 0.01 {
                    self.volume = currentVolume
                }
            }
        }
    }
}
