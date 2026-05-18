import SwiftUI

/// One row in the iPad sidebar. Carries only stable, Hashable data so the
/// `List(selection:)` binding keeps its identity across content reloads
/// (a folder's note count changes, its URL does not).
enum SidebarItem: Hashable {
    case recent
    case allNotes
    case folder(url: URL)
    case trash
}

/// The regular-width (iPad) shell: a three-column NavigationSplitView over
/// folders / notes / note detail. iPhone keeps the tab-based MobilePhoneShell.
/// Both reuse the same leaf views (`NoteCard`, `NoteDetailView`).
struct MobilePadShell: View {
    let root: URL
    let openPicker: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var sidebarSelection: SidebarItem? = .recent
    @State private var selectedNote: NoteFile?
    @State private var showSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PadSidebarView(
                root: root,
                selection: $sidebarSelection,
                openPicker: openPicker,
                openSettings: {
                    Haptics.tap()
                    showSettings = true
                }
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 320)
        } content: {
            PadContentColumn(
                root: root,
                sidebarSelection: sidebarSelection ?? .recent,
                selectedNote: $selectedNote
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 460)
        } detail: {
            if let note = selectedNote {
                // .id forces NoteDetailView to rebuild per note so its
                // onAppear→loadContent / onDisappear→flushSave lifecycle
                // runs cleanly for each selection.
                NoteDetailView(note: note)
                    .id(note.id)
            } else {
                PadDetailPlaceholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(MobileTheme.accent)
        .sheet(isPresented: $showSettings) {
            SettingsView(onChooseFolder: openPicker)
                .environmentObject(appState)
        }
    }
}
