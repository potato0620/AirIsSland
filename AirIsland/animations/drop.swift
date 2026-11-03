//
//  drop.swift
//  AirIsland
//
//  Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import SwiftUI

/// Presentation-only motion shared by the island and its interactive controls.
enum IslandAnimations {
    static func pageCommit(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .linear(duration: 0.14) }
    static func pageReturn(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .interactiveSpring(response: 0.25, dampingFraction: 1) }
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .interactiveSpring(response: 0.42, dampingFraction: 1, blendDuration: 0)
    }
}
