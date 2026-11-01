import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable {
    case activities, presentation, general, about
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .activities: return "Activities"
        case .presentation: return "Display and Interaction"
        case .general: return "General"
        case .about: return "About"
        }
    }
    var symbol: String {
        switch self {
        case .activities: return "waveform.path"
        case .presentation: return "rectangle.topthird.inset.filled"
        case .general: return "gear"
        case .about: return "info.circle"
        }
    }
    @ViewBuilder var destination: some View {
        switch self {
        case .activities: ActivitySettings()
        case .presentation: PresentationSettings()
        case .general: GeneralSettings()
        case .about: About()
        }
    }
}

struct SettingsView: View {
    @State private var selectedPage: SettingsPage? = .activities

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selectedPage) { page in
                NavigationLink(value: page) {
                    Label(page.title, systemImage: page.symbol)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            (selectedPage ?? .activities).destination
                .id(selectedPage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("").frame(width: 0, height: 0).accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 760, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.accentColor)
    }
}
