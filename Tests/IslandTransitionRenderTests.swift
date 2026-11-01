import AppKit
import SwiftUI

@MainActor private final class TransitionState: ObservableObject {
    @Published var expanded = true
    @Published var artwork = NSImage(size: NSSize(width: 220, height: 220), flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        return true
    }
}

/// A geometry fixture around the production backdrop, shape and motion policy.
/// It isolates mask/animation transactions from media sources and user preferences.
private struct TransitionFixture: View {
    @ObservedObject var state: TransitionState
    let closedHeight: CGFloat
    let reduceMotion: Bool

    var body: some View {
        Color.clear
            .frame(width: state.expanded ? 480 : 260, height: state.expanded ? 190 : closedHeight)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: state.expanded ? 13 : 4)
                    .fill(.red)
                    .frame(width: state.expanded ? 100 : closedHeight - 12,
                           height: state.expanded ? 100 : closedHeight - 12)
                    .offset(x: state.expanded ? 36 : 20, y: state.expanded ? 50 : 6)
            }
            .background {
                IslandBackdrop(artwork: state.artwork, topClearance: closedHeight, showsArtwork: state.expanded)
            }
            .clipShape(NotchShape(topCornerRadius: state.expanded ? 19 : 6,
                                  bottomCornerRadius: state.expanded ? 24 : 14))
            .animation(IslandAnimations.animation(reduceMotion: reduceMotion), value: state.expanded)
            .frame(width: 640, height: 210, alignment: .top)
            .transaction { if reduceMotion { $0.disablesAnimations = true } }
    }
}

@main private struct IslandTransitionRenderTests {
    @MainActor static func main() {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let output = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil
            if let output { try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
            for height: CGFloat in [25, 32, 38] {
                await verify(closedHeight: height, reduceMotion: false, output: output)
            }
            await verify(closedHeight: 32, reduceMotion: true, output: output)
            print("PASS: rendered corner continuity, artwork containment, reversal, content updates and reduced motion")
            exit(0)
        }
        NSApplication.shared.run()
    }

    @MainActor private static func verify(closedHeight: CGFloat, reduceMotion: Bool, output: URL?) async {
        let state = TransitionState()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 640, height: 210),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        let host = NSHostingView(rootView: TransitionFixture(state: state, closedHeight: closedHeight, reduceMotion: reduceMotion))
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(150))

        var count = 0
        func sample(_ phase: String) -> Int {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let width = rep.pixelsWide, height = rep.pixelsHigh
            let scale = CGFloat(width) / host.bounds.width
            func color(_ x: Int, _ y: Int) -> NSColor {
                rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            }
            let bottom = (0..<height).last { color(width / 2, $0).alphaComponent > 0.99 }!
            let side = (0..<width / 2).first { color($0, max(2, bottom / 2)).alphaComponent > 0.99 }!
            let corner = (0..<width / 2).first { color($0, max(0, bottom - 1)).alphaComponent > 0.99 }!
            // Actual pixels must retain curved lower corners throughout the transition.
            precondition(CGFloat(corner - side) > 2 * scale, "Rectangular corner in \(phase), frame \(count)")
            // High-contrast cover pixels may not extend below the opaque island surface.
            if bottom + 2 < height {
                for y in (bottom + 2)..<height {
                    for x in stride(from: side, to: width / 2, by: 2) {
                        let pixel = color(x, y)
                        precondition(!(pixel.alphaComponent > 0.15 && pixel.redComponent > 0.5
                                       && pixel.redComponent > pixel.greenComponent * 2
                                       && pixel.redComponent > pixel.blueComponent * 2),
                                     "Artwork escaped the island in \(phase), frame \(count)")
                    }
                }
            }
            let top = color(width / 2, Int(8 * scale))
            precondition(max(top.redComponent, top.greenComponent, top.blueComponent) < 0.005, "Header light leak")
            let renderedHeight = CGFloat(bottom + 1) / scale
            precondition(renderedHeight >= closedHeight - 1 && renderedHeight <= 191,
                         "Island geometry overshot its endpoints in \(phase)")
            if let output {
                let name = "h\(Int(closedHeight))-reduced\(reduceMotion)-\(phase)-\(count).png"
                try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
            }
            count += 1
            return Int((CGFloat(bottom + 1) / scale).rounded())
        }

        for expanded in [false, true] {
            state.expanded = expanded
            var heights: [Int] = []
            for _ in 0..<18 {
                try? await Task.sleep(for: .milliseconds(16))
                heights.append(sample(expanded ? "expand" : "collapse"))
            }
            try? await Task.sleep(for: .milliseconds(250))
            let target = expanded ? 190 : Int(closedHeight)
            precondition(abs(sample("settled") - target) <= 1, "Transition missed its target")
            let middle = heights.filter { $0 > Int(closedHeight) + 2 && $0 < 188 }
            precondition(reduceMotion ? middle.isEmpty : Set(middle).count > 2, "Unexpected transition continuity")
        }
        if !reduceMotion {
            for _ in 0..<4 {
                state.expanded.toggle()
                for _ in 0..<3 {
                    try? await Task.sleep(for: .milliseconds(16))
                    _ = sample("reverse")
                }
                // Updating background content cannot replace the active geometry transaction.
                state.artwork = NSImage(size: NSSize(width: 220, height: 220), flipped: false) { rect in
                    NSColor.blue.setFill(); rect.fill(); return true
                }
            }
            state.expanded = false
            for _ in 0..<18 {
                try? await Task.sleep(for: .milliseconds(16))
                _ = sample("finish")
            }
        }
        print("PASS: height \(closedHeight), reduced motion \(reduceMotion), \(count) rendered frames")
    }
}
