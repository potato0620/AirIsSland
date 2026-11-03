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
    @ViewBuilder func destination(selectActivity: @escaping (ActivitySettingsPage) -> Void) -> some View {
        switch self {
        case .activities: ActivitySettings(selectPage: selectActivity)
        case .presentation: PresentationSettings()
        case .general: GeneralSettings()
        case .about: About()
        }
    }
}

struct SettingsView: View {
    @State private var selectedPage: SettingsPage? = .general
    @State private var activityPage: ActivitySettingsPage?

    private var page: SettingsPage { selectedPage ?? .general }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 52)
                List(SettingsPage.allCases, selection: $selectedPage) { page in
                    Label(page.title, systemImage: page.symbol)
                        .tag(page)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 190)

            Divider()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        activityPage = nil
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 17, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(activityPage == nil ? .tertiary : .primary)
                    .disabled(activityPage == nil)
                    .accessibilityLabel(Text("Back"))
                    Text(activityPage?.title ?? page.title)
                        .font(.title2.bold())
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .frame(height: 52)

                Divider()

                Group {
                    if let activityPage {
                        activityPage.destination
                    } else {
                        page.destination { activityPage = $0 }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: selectedPage) { activityPage = nil }
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

extension View {
    /// Shared typography for settings descriptions, permission notes and footers.
    func settingsNoteStyle() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
