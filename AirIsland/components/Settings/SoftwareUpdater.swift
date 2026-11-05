//
//  SoftwareUpdater.swift
//  AirIsland
//
//  Created by Richard Kunkli on 09/08/2024.
//

import Combine
import Sparkle
import SwiftUI

/// App maintenance stays outside the island activity queue. Sparkle owns the
/// update session, download verification, cancellation, installation and relaunch.
@MainActor
final class SoftwareUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = SoftwareUpdateManager()

    @Published private(set) var canCheckForUpdates = true
    @Published var startupError: String?

    private var started = false
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
    )

    func checkForUpdates() {
        do {
            if !started {
                try controller.updater.start()
                started = true
                controller.updater.publisher(for: \.canCheckForUpdates)
                    .assign(to: &$canCheckForUpdates)
            }
            controller.checkForUpdates(nil)
        } catch {
            startupError = error.localizedDescription
        }
    }

    // Existing Sparkle preferences may come from an older installation. Keep
    // them intact, but only permit explicit checks in this manual-update release.
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard updateCheck == .updates else {
            throw NSError(domain: "AirIsland.SoftwareUpdate", code: 1)
        }
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var updates = SoftwareUpdateManager.shared

    var body: some View {
        Button("Check for Updates…") {
            updates.checkForUpdates()
        }
        .disabled(!updates.canCheckForUpdates)
        .alert("Unable to check for updates", isPresented: Binding(
            get: { updates.startupError != nil },
            set: { if !$0 { updates.startupError = nil } }
        )) {
            Button("OK", role: .cancel) { updates.startupError = nil }
        } message: {
            Text(updates.startupError ?? "")
        }
    }
}
