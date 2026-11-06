//
//  NotchHomeView.swift
//  AirIsland
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

struct MusicPlayerView: View {
    var active = true
    @EnvironmentObject private var vm: IslandViewModel

    var body: some View {
        let side = MusicPlayerImageSizes.expandedSide(headerHeight: max(24, vm.effectiveClosedNotchHeight))
        HStack {
            Color.clear
                .frame(width: side, height: side)
                .padding(MusicPlayerImageSizes.padding)
            MusicControlsView(active: active).drawingGroup().compositingGroup()
        }
    }
}

/// One interpolation drives the persistent cover's position, size and mask together.
/// Its endpoints use the same dimensions as the transparent slots in both layouts.
struct AlbumArtPresentation: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @State private var appIcon: Image?
    let vm: IslandViewModel
    let expansion: CGFloat
    let closedHeight: CGFloat
    let expandedLeadingInset: CGFloat
    let scalesCorners: Bool
    let isArtworkPaused: Bool

    var body: some View {
        let headerHeight = max(24, closedHeight)
        let closedSide = max(0, closedHeight - 12)
        let openedSide = MusicPlayerImageSizes.expandedSide(headerHeight: headerHeight)
        let side = interpolate(closedSide, openedSide)
        let leading = interpolate(cornerRadiusInsets.closed.bottom, expandedLeadingInset)
        let top = interpolate(6, headerHeight + MusicPlayerImageSizes.sectionSpacing + MusicPlayerImageSizes.padding)
        let closedRadius = MusicPlayerImageSizes.cornerRadiusInset.closed
        let openedRadius = scalesCorners ? MusicPlayerImageSizes.cornerRadiusInset.opened : closedRadius
        let playbackScale = isArtworkPaused ? interpolate(1, 0.85) : 1
        let badgeProgress = min(1, max(0, expansion))
        let badgeSide = 30 * badgeProgress * playbackScale
        let badgeInset = 5 * badgeProgress * playbackScale
        let badgeCenter = CGPoint(x: leading + side / 2 + side * playbackScale / 2 - badgeInset,
                                  y: top + side / 2 + side * playbackScale / 2 - badgeInset)
        GeometryReader { _ in
            AlbumArtView(vm: vm, cornerRadius: interpolate(closedRadius, openedRadius),
                         playbackScale: playbackScale)
                .frame(width: side, height: side)
                .position(x: leading + side / 2, y: top + side / 2)

            if !musicManager.usingAppIconForArtwork, let appIcon {
                appBadge(appIcon, side: badgeSide, center: badgeCenter, opacity: Double(badgeProgress))
            }
        }
        .onChange(of: musicManager.bundleIdentifier, initial: true) { _, bundleIdentifier in
            appIcon = AppIcon(for: bundleIdentifier ?? "com.apple.Music")
        }
    }

    private func interpolate(_ compact: CGFloat, _ expanded: CGFloat) -> CGFloat {
        compact + (expanded - compact) * expansion
    }

    private func appBadge(_ image: Image, side: CGFloat, center: CGPoint, opacity: Double) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
            // The shared expansion already supplies every frame. Do not start
            // another implicit position/size animation for the badge.
            .animation(nil) { badge in
                badge.frame(width: side, height: side).position(center).opacity(opacity)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: IslandViewModel

    let cornerRadius: CGFloat
    let playbackScale: CGFloat

    var body: some View {
        albumArtButton
    }

    private var albumArtButton: some View {
        Button {
            musicManager.openMusicApp()
        } label: {
            albumArtImage
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(playbackScale)
    }

    private var albumArtImage: some View {
        SpringAlbumArtwork(
            image: musicManager.albumArt,
            trackIdentifier: musicManager.albumArtTrackIdentifier,
            direction: musicManager.albumArtFlipDirection,
            cornerRadius: cornerRadius,
            dimming: vm.notchState == .open && !musicManager.isPlaybackActive ? 0.8 : 0
        )
    }

}

/// Reuse the same two faces for each half-turn. Rapid updates keep only the
/// newest pending cover, so a completed animation cannot restore an old track.
struct SpringAlbumArtwork: View {
    let image: NSImage
    let trackIdentifier: UUID
    let direction: AlbumArtFlipDirection
    let cornerRadius: CGFloat
    let dimming: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frontImage: NSImage
    @State private var backImage: NSImage
    @State private var transition: AlbumArtworkTransition<NSImage>
    @State private var angle: Double = 0
    @State private var animationID = UUID()

    init(image: NSImage, trackIdentifier: UUID, direction: AlbumArtFlipDirection, cornerRadius: CGFloat, dimming: Double) {
        self.image = image
        self.trackIdentifier = trackIdentifier
        self.direction = direction
        self.cornerRadius = cornerRadius
        self.dimming = dimming
        _frontImage = State(initialValue: image)
        _backImage = State(initialValue: image)
        _transition = State(initialValue: AlbumArtworkTransition(.init(
            artwork: image, trackIdentifier: trackIdentifier, direction: direction
        )))
    }

    var body: some View {
        ZStack {
            face(frontImage)
                .modifier(AlbumArtworkFlipFace(angle: angle))
            face(backImage)
                .modifier(AlbumArtworkFlipFace(angle: angle - 180))
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: ObjectIdentifier(image)) { _, _ in updateCover() }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { reset() }
        }
        .onAppear { reset() }
        .onDisappear { reset() }
    }

    private func face(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            // Attenuate the image itself over black. A translucent black
            // overlay leaves brighter image samples at antialiased edges.
            .opacity(1 - dimming)
            .background(Color.black)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private func updateCover() {
        guard !reduceMotion else { reset(); return }
        apply(transition.receive(.init(artwork: image, trackIdentifier: trackIdentifier, direction: direction)))
    }

    private func replaceDestination(with image: NSImage) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if Int((angle / 180).rounded()) % 2 == 0 {
                frontImage = image
            } else {
                backImage = image
            }
        }
    }

    private func apply(_ change: AlbumArtworkTransition<NSImage>.Change?) {
        guard let change else { return }
        switch change {
        case .replace(let image):
            replaceDestination(with: image)
        case .flip(let image, let direction):
            let id = UUID()
            animationID = id
            // The opposite face will become visible after this half-turn.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if Int((angle / 180).rounded()) % 2 == 0 {
                    backImage = image
                } else {
                    frontImage = image
                }
            }
            withAnimation(IslandAnimations.animation(reduceMotion: reduceMotion), completionCriteria: .removed) {
                angle += direction.rotation
            } completion: {
                guard animationID == id else { return }
                apply(transition.complete())
            }
        }
    }

    private func reset() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            animationID = UUID()
            frontImage = image
            backImage = image
            transition.reset(.init(artwork: image, trackIdentifier: trackIdentifier, direction: direction))
            angle = 0
        }
    }
}

private struct AlbumArtworkFlipFace: AnimatableModifier {
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let radians = angle * .pi / 180
        content
            // Cull at the rendered angle, rather than cross-fading mirrored faces.
            .opacity(cos(radians) > 0 ? 1 : 0)
            .brightness(-0.10 * abs(sin(radians)))
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .scaleEffect(1 - 0.045 * abs(sin(radians)))
    }
}

struct MusicControlsView: View {
    var active = true
    @ObservedObject var musicManager = MusicManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            slotToolbar
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: geo.size.width)
                musicSlider
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
    }

    private func songInfo(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                MarqueeText(
                    $musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white,
                    frameWidth: max(0, width - 32))
                MarqueeText(
                    $musicManager.artistName,
                    font: .headline,
                    nsFont: .headline,
                    textColor: Color(nsColor: musicManager.avgColor)
                        .ensureMinimumBrightness(factor: 0.6),
                    frameWidth: max(0, width - 32)
                )
                .fontWeight(.medium)
            }
            AudioSpectrumView(isPlaying: .constant(musicManager.isPlaying && active), maximumHeight: 20)
                .foregroundStyle(Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6))
                .padding(.top, 1)
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: 0.1,
                                paused: !active || !musicManager.isPlaying || musicManager.isChangingTrack || musicManager.playbackRate <= 0)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                estimatedPosition: musicManager.estimatedPlaybackPosition(at: timeline.date),
                timestampDate: musicManager.timestampDate,
                isChangingTrack: musicManager.isChangingTrack
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var slotToolbar: some View {
        HStack(spacing: 18) {
            HoverButton(icon: "backward.fill", scale: .medium) {
                musicManager.previousTrack()
            }
            .help("Previous")
            HoverButton(icon: musicManager.isPlaybackActive ? "pause.fill" : "play.fill", scale: .large) {
                musicManager.togglePlay()
            }
            .help("Play/Pause")
            HoverButton(icon: "forward.fill", scale: .medium) {
                musicManager.nextTrack()
            }
            .help("Next")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    var active = true
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject var coordinator = IslandWindowCoordinator.shared

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        // simplified: use a straightforward opacity transition
        .transition(.opacity)
    }

    private var mainContent: some View {
        Group {
            if musicManager.songTitle.isEmpty {
                VStack(spacing: 8) {
                    Label("Nothing Playing", systemImage: "music.note")
                        .font(.headline)
                    Text("Start playback in a music app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MusicPlayerView(active: active)
            }
        }
    }

}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let estimatedPosition: Double
    let timestampDate: Date
    let isChangingTrack: Bool
    var onValueChange: (Double) -> Void


    var body: some View {
        VStack {
            CustomSlider(
                value: Binding(get: { displayedValue }, set: { sliderValue = $0 }),
                range: 0...duration,
                color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                    : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
                resetsForTrackChange: isChangingTrack,
                onValueChange: onValueChange
            )
            .frame(height: 10, alignment: .center)
            .allowsHitTesting(!isChangingTrack)

            HStack {
                Text(timeString(from: displayedValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundColor(
                Color(nsColor: color).ensureMinimumBrightness(factor: 0.6)
            )
            .font(.caption)
        }
        .onChange(of: isChangingTrack) { _, changing in
            guard changing else { return }
            dragging = false
            lastDragged = .distantPast
            sliderValue = 0
        }
    }

    private var displayedValue: Double {
        guard !isChangingTrack else { return 0 }
        // Local state belongs only to a user's seek. Playback and duration must
        // render from the same update, without waiting for a later timeline tick.
        let holdsSeek = dragging || timestampDate < lastDragged
        return min(max(0, holdsSeek ? sliderValue : estimatedPosition), duration)
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var resetsForTrackChange = false
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?
    @State private var renderedFill: Double = 0
    @State private var latestFill: Double = 0
    @State private var isResetting = false
    @State private var resetGeneration = 0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let fraction = min(max(progress, 0), 1)
            let filledTrackWidth = renderedFill * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation(IslandAnimations.animation(reduceMotion: reduceMotion)) {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: dragging)
            .onChange(of: fraction, initial: true) { previous, current in
                latestFill = current
                guard !isResetting else { return }
                guard resetsForTrackChange, current == 0, previous > 0, !reduceMotion else {
                    cancelReset()
                    return
                }
                resetGeneration += 1
                let generation = resetGeneration
                isResetting = true
                // Retain only a normalized retiring fill. New duration/position
                // packets cannot stretch it or interrupt the short return to zero.
                // Start after parent seek-state cleanup has left this update.
                // Its unanimated transaction must not cancel the fill's return.
                Task { @MainActor in
                    guard generation == resetGeneration, isResetting else { return }
                    withAnimation(IslandAnimations.mediaReset(reduceMotion: reduceMotion)) {
                        renderedFill = 0
                    } completion: {
                        guard generation == resetGeneration else { return }
                        cancelReset()
                    }
                }
            }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced { cancelReset() }
            }
            .onChange(of: dragging) { _, active in
                if active { cancelReset() }
            }
            .onDisappear { cancelReset() }
        }
    }

    private func cancelReset() {
        resetGeneration += 1
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isResetting = false
            renderedFill = latestFill
        }
    }
}
