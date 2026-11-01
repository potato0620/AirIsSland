//
//  drop.swift
//  AirIsland
//
//  Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import SwiftUI

/// Presentation-only motion shared by the island and its interactive controls.
enum IslandAnimations {
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .interactiveSpring(response: 0.42, dampingFraction: 1, blendDuration: 0)
    }
}
