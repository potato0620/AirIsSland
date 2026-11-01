import SwiftUI

/// Keep the entire header black; album ambience must not outline a real or simulated notch.
struct IslandBackdrop: View {
    let artwork: NSImage
    let topClearance: CGFloat
    let showsArtwork: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 220, height: 220)
                .blur(radius: 45)
                .mask {
                    RadialGradient(colors: [.black, .clear], center: .center, startRadius: 40, endRadius: 110)
                }
                .offset(x: -20, y: 10)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .mask {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: max(24, topClearance) + 8)
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 36)
                        Color.black
                    }
                }
                .opacity(showsArtwork ? 0.3 : 0)
        }
        .clipped()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showsArtwork)
    }
}
