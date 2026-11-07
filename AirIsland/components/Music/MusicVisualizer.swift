// Created by Harsh Vardhan Goswami on 02/08/24.
// Six real audio bands replace the former randomized playback animation.
import SwiftUI

private struct MusicSpectrumVisibilityKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var musicSpectrumVisible: Bool {
        get { self[MusicSpectrumVisibilityKey.self] }
        set { self[MusicSpectrumVisibilityKey.self] = newValue }
    }
}

struct AudioSpectrumView: View {
    @Binding var isPlaying: Bool
    var maximumHeight: CGFloat = 12
    var alignsTrailing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.musicSpectrumVisible) private var visible
    @State private var levels = MusicSpectrumState.quiet

    private var followsAudio: Bool { isPlaying && visible && !reduceMotion }

    var body: some View {
        AudioSpectrumBars(levels: levels, maximumHeight: maximumHeight, alignsTrailing: alignsTrailing)
            .onReceive(ActivityCoordinator.shared.spectrumLevels) { update(followsAudio ? $0 : MusicSpectrumState.quiet) }
            .onChange(of: followsAudio, initial: true) { _, active in
                update(active ? ActivityCoordinator.shared.spectrumSnapshot : MusicSpectrumState.quiet)
            }
            .accessibilityHidden(true)
    }

    private func update(_ next: [Double]) {
        guard levels != next else { return }
        // Only a reset/pause settles over time. Normal analyzer frames already
        // have an envelope, so they retain the direct, inexpensive drawing path.
        let settles = visible && !reduceMotion && next == MusicSpectrumState.quiet
        withAnimation(settles ? IslandAnimations.mediaReset(reduceMotion: reduceMotion) : nil) { levels = next }
    }
}

private struct AudioSpectrumBars: View, Animatable {
    var levels: [Double]
    let maximumHeight: CGFloat
    let alignsTrailing: Bool
    @Environment(\.displayScale) private var displayScale

    typealias Pair = AnimatablePair<Double, Double>
    var animatableData: AnimatablePair<Pair, AnimatablePair<Pair, Pair>> {
        get { .init(.init(levels[0], levels[1]), .init(.init(levels[2], levels[3]), .init(levels[4], levels[5]))) }
        set {
            levels = [newValue.first.first, newValue.first.second,
                      newValue.second.first.first, newValue.second.first.second,
                      newValue.second.second.first, newValue.second.second.second]
        }
    }

    var body: some View {
        // Fractional physical-pixel gaps rasterize unevenly (1.6 pt is 3.2 px
        // on Retina). Keep the shared 20 pt slot and snap the bars to one grid.
        let scale = max(1, displayScale)
        let spacing = floor(1.6 * scale) / scale
        let contentWidth = CGFloat(MusicSpectrumState.barCount) * 2
            + CGFloat(MusicSpectrumState.barCount - 1) * spacing
        let remainingWidth = 20 - contentWidth
        let leadingInset = alignsTrailing ? remainingWidth : floor(remainingWidth * scale / 2) / scale
        Canvas { context, size in
            for index in 0..<MusicSpectrumState.barCount {
                let height = maximumHeight * levels[index]
                let rect = CGRect(x: leadingInset + CGFloat(index) * (2 + spacing),
                                  y: (size.height - height) / 2, width: 2, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: min(1, height / 2)), with: .foreground)
            }
        }
        .frame(width: 20, height: maximumHeight)
    }
}
