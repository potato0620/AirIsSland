// Created by Harsh Vardhan Goswami on 02/08/24.
// Six real audio bands replace the former randomized playback animation.
import SwiftUI

struct AudioSpectrumView: View {
    @Binding var isPlaying: Bool
    var maximumHeight: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var levels = MusicSpectrumState.quiet

    var body: some View {
        // Fractional physical-pixel gaps rasterize unevenly (1.6 pt is 3.2 px
        // on Retina). Keep the shared 20 pt slot and snap the bars to one grid.
        let scale = max(1, displayScale)
        let spacing = floor(1.6 * scale) / scale
        let contentWidth = CGFloat(MusicSpectrumState.barCount) * 2
            + CGFloat(MusicSpectrumState.barCount - 1) * spacing
        let leadingInset = floor((20 - contentWidth) * scale / 2) / scale
        HStack(spacing: spacing) {
            ForEach(0..<MusicSpectrumState.barCount, id: \.self) { index in
                Capsule()
                    .frame(width: 2, height: maximumHeight * (isPlaying && !reduceMotion ? levels[index] : 0.12))
            }
        }
        .padding(.leading, leadingInset)
        .frame(width: 20, height: maximumHeight, alignment: .leading)
        .animation(reduceMotion ? nil : .linear(duration: 1.0 / 30), value: levels)
        .onReceive(ActivityCoordinator.shared.spectrumLevels) {
            let next = isPlaying && !reduceMotion ? $0 : MusicSpectrumState.quiet
            if levels != next { levels = next }
        }
        .accessibilityHidden(true)
    }
}
