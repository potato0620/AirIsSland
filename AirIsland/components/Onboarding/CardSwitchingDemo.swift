import AVFoundation
import SwiftUI

/// A local illustration in the welcome window; it never creates real island activities.
struct CardSwitchingDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var visible = false

    var body: some View {
        ZStack {
            Image("CardSwitchingGuidePoster")
                .resizable()
                .scaledToFit()
            if !reduceMotion,
               let url = Bundle.main.url(forResource: colorScheme == .dark ? "CardSwitchingGuideDark" : "CardSwitchingGuide", withExtension: "mp4") {
                CardSwitchingMovie(url: url, shouldPlay: visible)
                    .id(url)
            }
        }
        .aspectRatio(12 / 7, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}

private struct CardSwitchingMovie: NSViewRepresentable {
    let url: URL
    let shouldPlay: Bool

    func makeNSView(context: Context) -> CardSwitchingMovieView {
        CardSwitchingMovieView(url: url)
    }

    func updateNSView(_ view: CardSwitchingMovieView, context: Context) {
        view.setPlaybackRequested(shouldPlay)
    }

    static func dismantleNSView(_ view: CardSwitchingMovieView, coordinator: ()) {
        view.stop()
    }
}

final class CardSwitchingMovieView: NSView {
    private let player = AVQueuePlayer()
    private let movieLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?
    private var readiness: NSKeyValueObservation?
    private var windowObservers: [NSObjectProtocol] = []
    private var playbackRequested = false

    init(url: URL) {
        super.init(frame: .zero)
        wantsLayer = true
        movieLayer.player = player
        movieLayer.videoGravity = .resizeAspect
        movieLayer.isHidden = true
        layer?.addSublayer(movieLayer)
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        readiness = movieLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.movieLayer.isHidden = !self.movieLayer.isReadyForDisplay
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        movieLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeWindowObservers()
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    let closing = note.name == NSWindow.willCloseNotification
                    Task { @MainActor [weak self] in
                        if closing { self?.stop() }
                        else { self?.updatePlayback() }
                    }
                })
            }
            for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.updatePlayback() }
                })
            }
        }
        updatePlayback()
    }

    func setPlaybackRequested(_ requested: Bool) {
        playbackRequested = requested
        updatePlayback()
    }

    private func updatePlayback() {
        if playbackRequested, NSApp.isActive, let window, window.isVisible, window.occlusionState.contains(.visible) {
            player.play()
        } else {
            player.pause()
        }
    }

    func stop() {
        playbackRequested = false
        player.pause()
        readiness?.invalidate()
        readiness = nil
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        movieLayer.player = nil
        removeWindowObservers()
    }

    private func removeWindowObservers() {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
    }

    deinit {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }
}
