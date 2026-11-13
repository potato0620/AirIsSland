//
//  NowPlayingController.swift
//  AirIsland
//
//  Created by Alexander on 2025-03-29.
//

import AppKit
import Combine
import Foundation

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    func updatePlaybackInfo() async {
        await fetchFavoriteStateIfSupported()
    }

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.apple.Music"
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music" || bundleID == "com.spotify.client"
    }

    var supportsFavorite: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music"
    }

    func setFavorite(_ favorite: Bool) async {
        let bundleID = playbackState.bundleIdentifier
        
        if bundleID == "com.apple.Music" {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            if !runningApps.isEmpty {
                let script = """
                tell application "Music"
                    try
                        set favorited of current track to \(favorite ? "true" : "false")
                    end try
                end tell
                """
                try? await AppleScriptHelper.executeVoid(script)
            }
        }
        
        // Update the favorite state locally and fetch updated info
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var playbackConfirmationTask: Task<Void, Never>?
    private var playbackSession = NowPlayingPlaybackSession()
    private var terminationObserver: AnyCancellable?
    private var metadataTask: Task<Void, Never>?
    private var metadataLookupKey: String?
    private var reconciledMetadataKey: String?
    private var reconciledMetadata: NetEaseTrackMetadata?
    private var reconciledArtwork: Data?
    private var artworkCache: [URL: Data] = [:]

    // MARK: - Initialization
    init?() {
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
            let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSendCommand" as CFString),
            let MRMediaRemoteSetElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetElapsedTime" as CFString),
            let MRMediaRemoteSetShuffleModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetShuffleMode" as CFString),
            let MRMediaRemoteSetRepeatModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetRepeatMode" as CFString)
            
        else { return nil }

        mediaRemoteBundle = bundle
        MRMediaRemoteSendCommandFunction = unsafeBitCast(
            MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(
            MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        MRMediaRemoteSetShuffleModeFunction = unsafeBitCast(
            MRMediaRemoteSetShuffleModePointer, to: (@convention(c) (Int) -> Void).self)
        MRMediaRemoteSetRepeatModeFunction = unsafeBitCast(
            MRMediaRemoteSetRepeatModePointer, to: (@convention(c) (Int) -> Void).self)

        terminationObserver = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleIdentifier = app.bundleIdentifier else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.publish(self.playbackSession.sourceDidTerminate(bundleIdentifier: bundleIdentifier))
                    self.schedulePlaybackConfirmation()
                }
            }
        Task { await setupNowPlayingObserver() }
    }

    deinit {
        streamTask?.cancel()
        restartTask?.cancel()
        playbackConfirmationTask?.cancel()
        metadataTask?.cancel()
        
        if let pipeHandler = self.pipeHandler {
            Task { await pipeHandler.close()
            }
        }
        
        if let process = self.process {
            if process.isRunning {
                process.terminate()
            }
        }

        self.process = nil
        self.pipeHandler = nil
    }

    // MARK: - Protocol Implementation
    @MainActor func play() async {
        cancelTrackChange()
        MRMediaRemoteSendCommandFunction(0, nil)
    }

    @MainActor func pause() async {
        cancelTrackChange()
        MRMediaRemoteSendCommandFunction(1, nil)
    }

    @MainActor func togglePlay() async {
        cancelTrackChange()
        MRMediaRemoteSendCommandFunction(2, nil)
    }

    @MainActor func nextTrack() async {
        publish(playbackSession.beginTrackChange())
        schedulePlaybackConfirmation()
        MRMediaRemoteSendCommandFunction(4, nil)
    }

    @MainActor func previousTrack() async {
        publish(playbackSession.beginTrackChange())
        schedulePlaybackConfirmation()
        MRMediaRemoteSendCommandFunction(5, nil)
    }

    func seek(to time: Double) async {
        MRMediaRemoteSetElapsedTimeFunction(time)
    }

    func isActive() -> Bool {
        return true
    }
    
    func toggleShuffle() async {
        // MRMediaRemoteSendCommandFunction(6, nil)
        MRMediaRemoteSetShuffleModeFunction(playbackState.isShuffled ? 1 : 3)
        playbackState.isShuffled.toggle()
    }
    
    func toggleRepeat() async {
        // MRMediaRemoteSendCommandFunction(7, nil)
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
    }
    
    func setVolume(_ level: Double) async {
        // MediaRemote framework doesn't provide direct volume control for the active audio session
        // As a workaround, try to control the currently active music app directly
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        
        let bundleID = playbackState.bundleIdentifier
        if !bundleID.isEmpty {
            if bundleID == "com.apple.Music" {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                if !runningApps.isEmpty {
                    let script = "tell application \"Music\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            } else if bundleID == "com.spotify.client" {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
                if !runningApps.isEmpty {
                    let script = "tell application \"Spotify\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            }
        }
        
        playbackState.volume = clampedLevel
    }
    
    // MARK: - Setup Methods
    private func setupNowPlayingObserver() async {
        guard process?.isRunning != true else { return }
        let process = Process()
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
        else {
            assertionFailure("Could not find mediaremote-adapter.pl script or framework path")
            return
        }
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // Preserve even short-lived valid snapshots before NetEase clears its
        // media session. Coalescing these can erase the new track entirely.
        // The default ISO timestamp truncates fractional seconds while elapsed
        // time retains them. Use the adapter's precise paired time fields.
        process.arguments = [scriptURL.path, frameworkPath, "stream", "--micros"]
        
        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = await pipeHandler.getPipe()
        
        self.process = process
        self.pipeHandler = pipeHandler

        do {
            try process.run()
            try await pipeHandler.closeWritingEnd()
            // Hold the pipe, not the controller, while waiting for the next update.
            // Otherwise the controller never deinitializes when the source changes.
            streamTask = Task { [weak self, pipeHandler] in
                do {
                    try await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
                        await self?.handleAdapterUpdate(update)
                    }
                } catch {
                    if !Task.isCancelled {
                        print("Now Playing stream interrupted: \(error)")
                    }
                }
                guard !Task.isCancelled else { return }
                await self?.scheduleObserverRestart()
            }
        } catch {
            print("Failed to launch mediaremote-adapter.pl: \(error)")
            await scheduleObserverRestart()
        }
    }

    @MainActor
    private func handleAdapterUpdate(_ update: NowPlayingUpdate) {
        let now = Date()
        let neteaseIsRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: NowPlayingPlaybackSession.neteaseBundleIdentifier
        ).isEmpty
        publish(playbackSession.receive(update, neteaseIsRunning: neteaseIsRunning, now: now))
        reconcileNetEaseMetadata()
        schedulePlaybackConfirmation()
    }

    @MainActor
    private func cancelTrackChange() {
        publish(playbackSession.cancelTrackChange())
        schedulePlaybackConfirmation()
    }

    @MainActor
    private func schedulePlaybackConfirmation() {
        playbackConfirmationTask?.cancel()
        playbackConfirmationTask = nil
        if let deadline = [playbackSession.pauseDeadline, playbackSession.trackChangeDeadline].compactMap({ $0 }).min() {
            playbackConfirmationTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                    try Task.checkCancellation()
                    guard let self else { return }
                    self.publish(self.playbackSession.confirmPendingPause())
                    self.schedulePlaybackConfirmation()
                } catch { }
            }
        }
    }

    @MainActor
    private func reconcileNetEaseMetadata() {
        let state = playbackSession.state
        guard state.bundleIdentifier == NowPlayingPlaybackSession.neteaseBundleIdentifier,
              !state.title.isEmpty else {
            metadataTask?.cancel()
            metadataLookupKey = nil
            return
        }
        let key = "\(state.sourceTrackIdentifier ?? state.artist)\u{0}\(state.title)"
        if reconciledMetadataKey == key, let metadata = reconciledMetadata {
            publish(playbackSession.reconcile(metadata, artwork: reconciledArtwork))
            return
        }
        guard metadataLookupKey != key else { return }
        metadataLookupKey = key
        metadataTask?.cancel()
        metadataTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(50))
                guard let metadata = await XPCHelperClient.shared.neteaseTrackMetadata(title: state.title, artist: state.artist),
                      !Task.isCancelled, let self, self.metadataLookupKey == key else { return }
                self.reconciledMetadata = metadata
                self.reconciledMetadataKey = key
                self.reconciledArtwork = nil
                self.publish(self.playbackSession.reconcile(metadata))
                guard let url = metadata.artworkURL else { return }
                let artwork: Data
                if let cached = self.artworkCache[url] {
                    artwork = cached
                } else {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 5
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let response = response as? HTTPURLResponse,
                          response.statusCode == 200, data.count <= 5_000_000,
                          NSImage(data: data) != nil else { return }
                    artwork = data
                    if self.artworkCache.count >= 32 { self.artworkCache.removeAll() }
                    self.artworkCache[url] = data
                }
                guard !Task.isCancelled, self.metadataLookupKey == key else { return }
                self.reconciledArtwork = artwork
                self.publish(self.playbackSession.reconcile(metadata, artwork: artwork))
            } catch { }
        }
    }

    @MainActor
    private func publish(_ state: PlaybackState) {
        if state != playbackState || state.lastUpdated != playbackState.lastUpdated
            || state.playbackRate != playbackState.playbackRate
            || state.volume != playbackState.volume {
            playbackState = state
        }
    }

    private func scheduleObserverRestart() async {
        await pipeHandler?.close()
        if let process, process.isRunning { process.terminate() }
        process = nil
        pipeHandler = nil
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
                await self?.setupNowPlayingObserver()
            } catch { }
        }
    }

     private func fetchFavoriteStateIfSupported() async {
         let bundleID = playbackState.bundleIdentifier
        
         if bundleID == "com.apple.Music" {
             let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
             guard !runningApps.isEmpty else { return }
             
             let script = """
             tell application "Music"
                 try
                     return favorited of current track
                 on error
                     return false
                 end try
             end tell
             """
             if let result = try? await AppleScriptHelper.execute(script) {
                 var updated = self.playbackState
                 updated.isFavorite = result.booleanValue
                 self.playbackState = updated
             }
         }
     }
    
}
