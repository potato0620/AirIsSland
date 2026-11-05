import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
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
    @ViewBuilder func destination(selectActivity: @escaping (ActivitySettingsPage) -> Void) -> some View {
        switch self {
        case .activities: ActivitySettings(selectPage: selectActivity)
        case .presentation: PresentationSettings()
        case .general: GeneralSettings()
        case .about: About()
        }
    }
}

final class SettingsNavigation: ObservableObject {
    @Published var selectedPage: SettingsPage? = .general
    @Published var activityPage: ActivitySettingsPage?

    var page: SettingsPage { selectedPage ?? .general }
}

/// Hosted in AppKit's titlebar so native window chrome cannot cover navigation.
struct SettingsNavigationHeader: View {
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        HStack(spacing: 12) {
            Button {
                navigation.activityPage = nil
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(navigation.activityPage == nil ? .tertiary : .primary)
            .disabled(navigation.activityPage == nil)
            .accessibilityLabel(Text("Back"))
            Text(navigation.activityPage?.title ?? navigation.page.title)
                .font(.title2.bold())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsView: View {
    static let sidebarWidth: CGFloat = 190
    static let headerHeight: CGFloat = 52
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsPage.allCases, selection: $navigation.selectedPage) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .frame(width: Self.sidebarWidth)
            .background(.bar, ignoresSafeAreaEdges: .top)

            Divider()

            Group {
                if let activityPage = navigation.activityPage {
                    activityPage.destination
                } else {
                    navigation.page.destination { navigation.activityPage = $0 }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: navigation.selectedPage) { navigation.activityPage = nil }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor).ignoresSafeArea(.container, edges: .top))
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

extension View {
    /// Shared typography for settings descriptions, permission notes and footers.
    func settingsNoteStyle() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
