import SwiftUI

struct About: View {
    @State private var showBuildNumber: Bool = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    if showBuildNumber {
                        Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                            .foregroundStyle(.secondary)
                    }
                    Text(Bundle.main.releaseVersionNumber ?? "unkown")
                        .foregroundStyle(.secondary)
                }
                .onTapGesture {
                    withAnimation {
                        showBuildNumber.toggle()
                    }
                }
            } header: {
                Text("Version info")
            } footer: {
                SettingsActionRow {
                    Link(destination: URL(string: "https://github.com/potato0620/AirIsSland")!) {
                        Text("GitHub")
                    }
                    CheckForUpdatesView()
                }
            }
        }
    }
}
