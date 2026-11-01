//
//  SoftwareUpdater.swift
//  boringNotch
//
//  Created by Richard Kunkli on 09/08/2024.
//

import SwiftUI

struct CheckForUpdatesView: View {
    private let releasesURL = URL(string: "https://github.com/potato0620/AirIsSland/releases/latest")!

    var body: some View {
        Link("Download the latest version", destination: releasesURL)
    }
}

struct UpdaterSettingsView: View {
    var body: some View {
        Section {
            CheckForUpdatesView()
            Text("Download updates from this project’s GitHub Releases.")
                .foregroundStyle(.secondary)
        } header: {
            Text("Software updates")
        }
    }
}
