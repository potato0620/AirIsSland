import Defaults
import SwiftUI

/// Add future approved activities here without adding another top-level settings tab.
enum ActivitySettingsPage: String, CaseIterable, Identifiable {
    case music, reminders, timer, feedback
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .music: return "Media"
        case .feedback: return "System Feedback"
        case .reminders: return "Reminders"
        case .timer: return "Timer"
        }
    }
    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .feedback: return "dial.medium.fill"
        case .reminders: return "checklist"
        case .timer: return "timer"
        }
    }
    var summary: LocalizedStringKey {
        switch self {
        case .music: return "Now playing and essential playback controls."
        case .feedback: return "Brief feedback for system adjustments and power changes."
        case .reminders: return "Sync incomplete tasks from Apple Reminders lists."
        case .timer: return "Countdowns with a reminder when time is up."
        }
    }
    @ViewBuilder var destination: some View {
        switch self {
        case .music: MusicActivitySettings()
        case .feedback: SystemFeedbackSettings()
        case .reminders: RemindersActivitySettings()
        case .timer: TimerActivitySettings()
        }
    }
}

struct TimerActivitySettings: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .timerActivityEnabled) { Text("Enable timer") }
            } footer: {
                Text("Turning off the timer cancels the current countdown.")
            }
        }
    }
}

struct RemindersActivitySettings: View {
    @ObservedObject private var source = RemindersActivityManager.shared
    @Default(.remindersActivityEnabled) private var enabled
    @Default(.reminderListIdentifier) private var listIdentifier
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .remindersActivityEnabled) { Text("Sync Apple Reminders") }
                if source.authorized && enabled {
                    Picker("Show list", selection: $listIdentifier) {
                        Text("All tasks").tag("")
                        ForEach(source.lists) { list in Text(list.displayTitle).tag(list.id) }
                        if !listIdentifier.isEmpty && !source.lists.contains(where: { $0.id == listIdentifier }) {
                            Text("Selected list unavailable").tag(listIdentifier)
                        }
                    }
                    if let error = source.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(source.authorized ? LocalizedStringKey("Reminders access granted") : LocalizedStringKey("Reminders access not granted"))
                    .foregroundStyle(.secondary)
                Button(source.accessDenied ? LocalizedStringKey("Open Privacy Settings") : LocalizedStringKey("Connect Reminders")) {
                    if source.accessDenied { source.openPrivacySettings() }
                    else { Task { await source.connect() } }
                }.disabled(source.requesting)
            }
        }
        .task { source.refresh() }
    }
}

struct ActivitySettings: View {
    var selectPage: (ActivitySettingsPage) -> Void

    var body: some View {
        Form {
            Section {
                ForEach(ActivitySettingsPage.allCases) { page in
                    Button {
                        selectPage(page)
                    } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(page.title)
                                    Text(page.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: page.symbol)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
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

            Section {
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("Show power status notifications")
                }
            }

        }
        .accentColor(.effectiveAccent)
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
