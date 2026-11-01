//
//  Color+AccentColor.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-24.
//

import SwiftUI
import Defaults

private extension NSColor {
    /// The user's custom accent color, or nil when the system accent should be used.
    static var customAccent: NSColor? {
        guard Defaults[.useCustomAccentColor],
              let colorData = Defaults[.customAccentColorData]
        else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData)
    }
}

extension Color {
    static var effectiveAccent: Color {
        NSColor.customAccent.map { Color(nsColor: $0) } ?? .accentColor
    }

    /// Returns a darker version of the accent color suitable for backgrounds
    static var effectiveAccentBackground: Color {
        NSColor.customAccent
            .map { Color(nsColor: $0.withSystemEffect(.disabled)) }
            ?? Color.effectiveAccent.opacity(0.25)
    }
}

extension NSColor {
    static var effectiveAccent: NSColor {
        customAccent ?? .controlAccentColor
    }

    /// Returns a darker version of the accent color as NSColor suitable for backgrounds
    static var effectiveAccentBackground: NSColor {
        customAccent?.withSystemEffect(.disabled)
            ?? NSColor.controlAccentColor.withAlphaComponent(0.25)
    }
}
