import Defaults
import SwiftUI

/// Add future approved activities here without adding another top-level settings tab.
private enum ActivitySettingsPage: String, CaseIterable, Identifiable {
    case music, feedback, power
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .music: return "Media"
        case .feedback: return "System Feedback"
        case .power: return "Power Changes"
        }
    }
    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .feedback: return "dial.medium.fill"
        case .power: return "battery.100.bolt"
        }
    }
    var summary: LocalizedStringKey {
        switch self {
        case .music: return "Now playing and essential playback controls."
        case .feedback: return "Brief feedback when adjusting volume and brightness."
        case .power: return "Brief updates when power or charging changes."
        }
    }
    @ViewBuilder var destination: some View {
        switch self {
        case .music: MusicActivitySettings()
        case .feedback: SystemFeedbackSettings()
        case .power: PowerActivitySettings()
        }
    }
}

struct ActivitySettings: View {
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ActivitySettingsPage.allCases) { page in
                        NavigationLink {
                            page.destination
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(page.title)
                                    Text(page.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: page.symbol)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Activities")
        }
    }
}

struct MusicActivitySettings: View {
    @Default(.musicLiveActivityEnabled) private var musicLiveActivityEnabled
    @Default(.waitInterval) var waitInterval
    @Default(.enableSneakPeek) private var enableSneakPeek


    var body: some View {
        Form {
            Section {
                Toggle(
                    "Show music live activity",
                    isOn: $musicLiveActivityEnabled
                )
                Toggle("Show sneak peek on playback changes", isOn: $enableSneakPeek)
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            } header: {
                Text("Media playback live activity")
            }


        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Media")
    }

}

struct SystemFeedbackSettings: View {
    @State private var accessibilityAuthorized = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replace system HUD")
                            .font(.headline)
                        Text("Replaces the standard macOS volume, display brightness, and keyboard brightness HUDs with a custom design.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .hudReplacement)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .disabled(!accessibilityAuthorized)
                }

                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility access is required to replace the system HUD.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Request Accessibility") {
                                XPCHelperClient.shared.requestAccessibilityAuthorization()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 6)
                }
            }

        }
        .accentColor(.effectiveAccent)
        .navigationTitle("System Feedback")
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        }
        .onDisappear {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
            }
        }
    }
}

struct PowerActivitySettings: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBatteryIndicator) {
                    Text("Show battery indicator")
                }
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("Show power status notifications")
                }
            } header: {
                Text("General")
            }
            Section {
                Defaults.Toggle(key: .showBatteryPercentage) {
                    Text("Show battery percentage")
                }
                Defaults.Toggle(key: .showPowerStatusIcons) {
                    Text("Show power status icons")
                }
            } header: {
                Text("Battery Information")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Battery")
    }
}
