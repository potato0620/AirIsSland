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
    var iconColor: NSColor {
        switch self {
        case .general: return .systemGray
        case .activities: return .systemIndigo
        case .presentation: return NSColor(calibratedWhite: 0.18, alpha: 1)
        case .about: return .systemBlue
        }
    }
    // A sidebar treats symbols and shapes as template content when selected.
    // Render the complete badge once so selection keeps its original colors,
    // just like the full-color icons in System Settings.
    @MainActor var icon: Image {
        Image(nsImage: Self.icons[self]!).renderingMode(.original)
    }
    @MainActor private static let icons: [Self: NSImage] = Dictionary(
        uniqueKeysWithValues: allCases.map { page in
            let renderer = ImageRenderer(content:
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(LinearGradient(colors: [
                        Color(nsColor: page.iconColor.blended(withFraction: 0.16, of: .white) ?? page.iconColor),
                        Color(nsColor: page.iconColor)
                    ], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                    })
            renderer.scale = 2
            return (page, renderer.nsImage!)
        })
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

/// Keep the arrow-only button's hit area and title spacing stable.
struct SettingsBackButton: View {
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        Button {
            navigation.activityPage = nil
        } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 12, height: 16)
                .frame(width: 36, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(navigation.activityPage == nil ? .tertiary : .primary)
        .disabled(navigation.activityPage == nil)
        .accessibilityLabel(Text("Back"))
    }
}

struct SettingsNavigationHeader: View {
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        HStack(spacing: 12) {
            SettingsBackButton(navigation: navigation)
            Text(navigation.activityPage?.title ?? navigation.page.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.8))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: SettingsView.headerHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SettingsSidebar: View {
    @ObservedObject var navigation: SettingsNavigation
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        List(SettingsPage.allCases, selection: $navigation.selectedPage) { page in
            Label {
                Text(page.title)
            } icon: {
                page.icon
            }
            .tag(page)
            .foregroundStyle(navigation.selectedPage == page && controlActiveState == .key
                             ? Color.white : Color.primary)
            // Match the lighter blue selection in macOS System Settings.
            .listRowBackground(
                RoundedRectangle(cornerRadius: 5)
                    .fill(navigation.selectedPage == page
                          ? (controlActiveState == .key
                             ? Color(red: 73.0 / 255, green: 153.0 / 255, blue: 1)
                             : Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                          : Color.clear)
                    .padding(.horizontal, 10)
            )
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .onChange(of: navigation.selectedPage) { navigation.activityPage = nil }
    }
}

struct SettingsView: View {
    static let sidebarWidth: CGFloat = 230
    static let headerHeight: CGFloat = 40
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        Group {
            if let activityPage = navigation.activityPage {
                activityPage.destination
            } else {
                navigation.page.destination { navigation.activityPage = $0 }
            }
        }
        .formStyle(.grouped)
        .pickerStyle(.menu)
        // Grouped Form adds 23 points above its first heading on macOS. Match
        // System Settings' 15-point gap while keeping the scroll viewport below
        // the native titlebar (enforced by the hosting controller's container).
        .contentMargins(.top, -8, for: .scrollContent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
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
        font(.callout)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
