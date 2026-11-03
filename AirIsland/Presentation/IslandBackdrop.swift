import SwiftUI

/// Music-page background. The page owns its clipping, movement and expansion.
struct IslandBackdrop: View {
    let color: NSColor
    let topClearance: CGFloat
    let showsArtwork: Bool

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 0) {
                Color.clear.frame(height: max(0, topClearance))
                LinearGradient(colors: [.clear, Color(nsColor: color).opacity(0.32)],
                               startPoint: .top, endPoint: .bottom)
            }
            .opacity(showsArtwork ? 1 : 0)
        }
        .clipped()
    }
}
