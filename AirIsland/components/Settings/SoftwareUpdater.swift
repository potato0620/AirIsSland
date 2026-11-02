//
//  SoftwareUpdater.swift
//  AirIsland
//
//  Created by Richard Kunkli on 09/08/2024.
//

import SwiftUI

struct CheckForUpdatesView: View {
    static let releasesURL = URL(string: "https://github.com/potato0620/AirIsSland/releases/latest")!

    var body: some View {
        Link("Download the latest version", destination: Self.releasesURL)
    }
}
