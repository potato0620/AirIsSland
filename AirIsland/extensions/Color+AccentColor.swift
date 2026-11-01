import SwiftUI

extension Color {
    static var effectiveAccent: Color { .accentColor }
    static var effectiveAccentBackground: Color { .accentColor.opacity(0.25) }
}

extension NSColor {
    static var effectiveAccent: NSColor { .controlAccentColor }
    static var effectiveAccentBackground: NSColor { .controlAccentColor.withAlphaComponent(0.25) }
}
