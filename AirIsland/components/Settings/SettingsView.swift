import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general, activities, presentation, about
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
    @State private var selectedPage: SettingsPage? = .general

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsPage.allCases, selection: $selectedPage) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            NavigationStack {
                (selectedPage ?? .general).destination
            }
            .id(selectedPage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

struct SettingsActionRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            content
        }
        .font(.body)
        .controlSize(.regular)
        .buttonStyle(.bordered)
        .padding(.top, 8)
    }
}
