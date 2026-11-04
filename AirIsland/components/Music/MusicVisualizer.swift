// Created by Harsh Vardhan Goswami on 02/08/24.
// Six real audio bands replace the former randomized playback animation.
import SwiftUI

struct AudioSpectrumView: View {
    @Binding var isPlaying: Bool
    var maximumHeight: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var levels = MusicSpectrumState.quiet

    var body: some View {
        HStack(spacing: 1.6) {
            ForEach(0..<MusicSpectrumState.barCount, id: \.self) { index in
                Capsule()
                    .frame(width: 2, height: maximumHeight * (isPlaying && !reduceMotion ? levels[index] : 0.12))
            }
        }
        .frame(width: 20, height: maximumHeight)
        .animation(reduceMotion ? nil : .linear(duration: 1.0 / 30), value: levels)
        .onReceive(ActivityCoordinator.shared.spectrumLevels) {
            let next = isPlaying && !reduceMotion ? $0 : MusicSpectrumState.quiet
            if levels != next { levels = next }
        }
        .accessibilityHidden(true)
    }
}
