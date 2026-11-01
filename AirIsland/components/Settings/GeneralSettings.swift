import Defaults
import SwiftUI

import LaunchAtLogin

struct GeneralSettings: View {
    var body: some View {
        Form {
            Section("System features") {
                LaunchAtLogin.Toggle { Text("Launch at login") }
                Defaults.Toggle("Show menu bar icon", key: .menubarIcon)
            }
            Section("Privacy and Compatibility") {
                Defaults.Toggle("Show notch on lock screen", key: .showOnLockScreen)
                Defaults.Toggle("Hide from screen recording", key: .hideFromScreenRecording)
                Defaults.Toggle("Extend hover area", key: .extendHoverArea)
                Defaults.Toggle("Hide title bar", key: .hideTitleBar)
            }
        }
        .navigationTitle("General")
        .toolbar {
            Button("Quit app") { NSApp.terminate(nil) }
        }
    }
}
