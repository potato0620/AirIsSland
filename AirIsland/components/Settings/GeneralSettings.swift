import Defaults
import SwiftUI

import LaunchAtLogin

struct GeneralSettings: View {
    var body: some View {
        Form {
            Section("System features") {
                LaunchAtLogin.Toggle { Text("Launch at login") }
                Defaults.Toggle(key: .menubarIcon) {
                    Text("Show menu bar icon")
                }
            }
            Section {
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Show notch on lock screen")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("Hide from screen recording")
                }
            } header: {
                Text("Privacy and Compatibility")
            } footer: {
                SettingsActionRow {
                    Button { NSApp.terminate(nil) } label: {
                        Text("Quit app")
                    }
                }
            }
        }
    }
}
