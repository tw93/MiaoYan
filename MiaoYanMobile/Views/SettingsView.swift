import SwiftUI

/// App settings and about. Presented as a sheet so it stays layout-agnostic
/// — the same view works whether it is launched from the iPhone library
/// header or, later, an iPad sidebar entry.
struct SettingsView: View {
    /// Invokes the host's folder-picker flow (same one the library header
    /// uses) so folder selection, bookmarking and error handling stay in
    /// one place rather than being re-implemented here.
    let onChooseFolder: () -> Void

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var syncManager = CloudSyncManager.shared
    @Environment(\.dismiss) private var dismiss

    /// Reuses the exact key the reader / editor already bind to, so the
    /// picker here and the in-reader font menu stay in sync automatically.
    @AppStorage("MiaoYanMobile.FontSize") private var fontSizeRaw = ReaderFontSize.medium.rawValue

    private static let repoURL = URL(string: "https://github.com/tw93/MiaoYan")
    private static let issuesURL = URL(string: "https://github.com/tw93/MiaoYan/issues/new")

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                librarySection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(MobileTheme.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.tap()
                        dismiss()
                    }
                    .foregroundStyle(MobileTheme.accent)
                }
            }
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section {
            Picker("Reading font size", selection: $fontSizeRaw) {
                ForEach(ReaderFontSize.allCases, id: \.rawValue) { size in
                    Text(size.label).tag(size.rawValue)
                }
            }
        } header: {
            Text("Appearance")
        }
    }

    private var librarySection: some View {
        Section {
            settingRow(label: "iCloud", value: syncStatusLabel)
            settingRow(
                label: "Folder",
                value: appState.rootURL?.lastPathComponent ?? "Not set")
            Button {
                Haptics.tap()
                onChooseFolder()
            } label: {
                Text("Choose Folder…")
                    .foregroundStyle(MobileTheme.accent)
            }
        } header: {
            Text("Library")
        } footer: {
            Text("MiaoYan reads Markdown notes from this folder. Pick an iCloud Drive folder to keep notes synced with Mac.")
        }
    }

    private var aboutSection: some View {
        Section {
            settingRow(label: "Version", value: versionString)
            if let url = Self.repoURL {
                Link(destination: url) {
                    linkRow("Project on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            if let url = Self.issuesURL {
                Link(destination: url) {
                    linkRow("Report an Issue", systemImage: "exclamationmark.bubble")
                }
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Row builders

    private func settingRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(MobileTheme.ink)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(MobileTheme.secondaryInk)
                .lineLimit(1)
        }
    }

    private func linkRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(MobileTheme.accent)
    }

    // MARK: - Values

    private var syncStatusLabel: String {
        switch syncManager.status {
        case .syncing: return "Syncing"
        case .synced: return "Synced"
        case .offline: return "Offline"
        case .error: return "Sync issue"
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return short == build ? short : "\(short) (\(build))"
    }
}
