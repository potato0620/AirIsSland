//
//  sizeMatters.swift
//  AirIsland
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let shadowPadding: CGFloat = 20
let expandedNotchHeight: CGFloat = 190
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
    static let padding: CGFloat = 5
    static let sectionSpacing: CGFloat = 8
    static let panelPadding: CGFloat = 12
    static func compactPadding(height: CGFloat) -> CGFloat {
        6 * min(1, max(0, height) / 32)
    }

    static func compactCornerScale(height: CGFloat) -> CGFloat {
        // Keep the top and bottom curves from overlapping on shallow islands.
        min(1, max(0, height) / (cornerRadiusInsets.closed.top + cornerRadiusInsets.closed.bottom))
    }

    static func compactOuterInset(height: CGFloat) -> CGFloat {
        // The shape's straight sides start inside its bounding rectangle.
        cornerRadiusInsets.closed.top * compactCornerScale(height: height) + compactPadding(height: height)
    }

    static func compactSide(height: CGFloat) -> CGFloat {
        max(0, height - 2 * compactPadding(height: height))
    }

    static func expandedSide(headerHeight: CGFloat) -> CGFloat {
        max(0, expandedNotchHeight - headerHeight - sectionSpacing - panelPadding - 2 * padding)
    }
}

enum NonNotchWidth {
    static let percentageRange: ClosedRange<CGFloat> = 5...10
    static let defaultPercentage: CGFloat = 10
    static let widthRange: ClosedRange<CGFloat> = 120...320

    static func resolve(screenWidth: CGFloat, percentage: CGFloat) -> CGFloat {
        let value = percentage.isFinite ? percentage : defaultPercentage
        let fraction = min(percentageRange.upperBound, max(percentageRange.lowerBound, value)) / 100
        return min(widthRange.upperBound, max(widthRange.lowerBound, screenWidth * fraction))
    }
}

enum ExpandedNotchWidth {
    static let multiplier: CGFloat = 2.5
    static let widthRange: ClosedRange<CGFloat> = 400...960

    static func resolve(baseWidth: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let available = max(0, screenWidth - 2 * shadowPadding)
        return min(available, min(widthRange.upperBound, max(widthRange.lowerBound, baseWidth * multiplier)))
    }
}

@MainActor func getExpandedNotchSize(baseWidth: CGFloat, screenUUID: String?) -> CGSize {
    let screen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
    if let screen, screen.safeAreaInsets.top > 0 {
        return CGSize(width: 480, height: expandedNotchHeight)
    }
    return CGSize(width: ExpandedNotchWidth.resolve(baseWidth: baseWidth,
        screenWidth: screen?.frame.width ?? ExpandedNotchWidth.widthRange.upperBound + 2 * shadowPadding), height: expandedNotchHeight)
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        if screen.safeAreaInsets.top == 0 {
            notchWidth = NonNotchWidth.resolve(
                screenWidth: screen.frame.width, percentage: Defaults[.nonNotchWidthPercentage])
        }
        // Calculate and set the exact width of the notch
        else if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
