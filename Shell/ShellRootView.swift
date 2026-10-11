import AppKit
import SwiftUI

// MARK: - Style

/// The shell's tokens, read once per render so appearance changes carry over.
@available(macOS 14, *)
@MainActor
enum ShellStyle {
    /// The band the traffic lights sit in; every column puts its controls
    /// on the same centre line.
    static let headerHeight: CGFloat = 52
    /// Room the traffic lights take at the leading edge of whichever column
    /// is leftmost.
    static let trafficLightsInset: CGFloat = 78
    /// Where the editor's and the preview's text starts inside the note
    /// column (24pt margin plus the text container's line padding); the note
    /// title lines up with it.
    static let noteTextInset: CGFloat = 29

    static var background: SwiftUI.Color { SwiftUI.Color(nsColor: ShellPalette.background) }
    static var text: SwiftUI.Color { SwiftUI.Color(nsColor: ShellPalette.text) }
    static var secondaryText: SwiftUI.Color { SwiftUI.Color(nsColor: ShellPalette.secondaryText) }
    static var tertiaryText: SwiftUI.Color { SwiftUI.Color(nsColor: ShellPalette.tertiaryText) }
    static var accent: SwiftUI.Color { SwiftUI.Color(nsColor: ShellPalette.accent) }
    static var icon: SwiftUI.Color { SwiftUI.Color(nsColor: ShellPalette.icon) }
    static var selection: SwiftUI.Color { SwiftUI.Color(nsColor: ShellPalette.listSelection) }
    static var hairline: SwiftUI.Color { SwiftUI.Color(nsColor: ShellPalette.hairline) }
    static var field: SwiftUI.Color { SwiftUI.Color(nsColor: ShellPalette.field) }
    static var sidebarSelection: SwiftUI.Color { SwiftUI.Color(nsColor: ShellPalette.sidebarSelection) }

    /// Titles: Kami keeps this face to 400 and 500, never a synthesised bold.
    static let titleWeight = SwiftUI.Font.Weight.medium

    static func interface(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
        SwiftUI.Font(FontConfiguration.interfaceFont(size: size)).weight(weight)
    }

    static func tracking(_ size: CGFloat) -> CGFloat {
        size * UserDefaultsManagement.letterSpacingEm
    }

    /// The brand wordmark, Charter Bold Italic as in the storyboard window's
    /// sidebar, falling back to the interface face set bold.
    static func brandWordmark(_ size: CGFloat) -> SwiftUI.Font {
        if let charter = NSFont(name: "Charter-BoldItalic", size: size) { return SwiftUI.Font(charter) }
        return interface(size, weight: .semibold)
    }

    /// Spacing that sets multi-line text at 1.45em. `lineSpacing` adds to the
    /// face's own line height, which is 1.23em for TsangerJinKai02 and 1.38em
    /// for PingFang, so a fixed figure reads tight in one and loose in the other.
    static func lineSpacing(_ size: CGFloat) -> CGFloat {
        let font = FontConfiguration.interfaceFont(size: size)
        return max(0, size * 1.45 - NSLayoutManager().defaultLineHeight(for: font))
    }

    /// Whether the interface face has a bold of its own. TsangerJinKai02 ships
    /// W04 alone, and `.weight` or `.bold()` leave it at W04.
    static var interfaceHasBold: Bool {
        let font = FontConfiguration.interfaceFont(size: 13)
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask).fontName != font.fontName
    }
}

/// Bold for the brand row and the section headings. A face with a bold uses
/// it; one without is drawn twice a device pixel apart with each advance a
/// pixel wider, which is how WebKit synthesises weight 600 and what the
/// preview already shows.
@available(macOS 14, *)
private struct ShellBoldText: View {
    let string: String
    let size: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if ShellStyle.interfaceHasBold {
            Text(string)
                .font(ShellStyle.interface(size, weight: .semibold))
                .kerning(ShellStyle.tracking(size))
        } else {
            let pixel = 1 / displayScale
            let text = Text(string)
                .font(ShellStyle.interface(size))
                .kerning(ShellStyle.tracking(size) + pixel)
            text.overlay(alignment: .leading) { text.offset(x: pixel) }
        }
    }
}

/// A toolbar glyph: an asset template or an SF Symbol, drawn light and
/// turning the accent colour when its mode is on.
@available(macOS 14, *)
private struct ChromeButton: View {
    var image: String?
    var symbol: String?
    let help: String
    var isActive = false
    var tint = ShellStyle.icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(isActive ? ShellStyle.accent : tint)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(I18n.str(help))
    }

    @ViewBuilder private var glyph: some View {
        if let symbol {
            SwiftUI.Image(systemName: symbol).font(.system(size: 14, weight: .regular))
        } else {
            SwiftUI.Image(nsImage: NSImage(named: image ?? "") ?? NSImage())
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        }
    }
}

// MARK: - Sidebar

@available(macOS 14, *)
struct ShellSidebar: View {
    @Bindable var model: ShellModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Spacer()
                ChromeButton(image: "addProject", help: "New Folder") { model.promptNewFolder() }
                ChromeButton(image: "icon_sidebar_left", help: "Toggle Note List") { model.cycleLayout() }
            }
            .padding(.horizontal, 10)
            .frame(height: ShellStyle.headerHeight)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(model.sidebarRows) { row in
                        ShellSidebarRow(model: model, row: row, isSelected: model.scope == row.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.scope = row.id
                                focused = true
                            }
                        if row.kind == .All {
                            SwiftUI.Color.clear.frame(height: 6)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
            .scrollContentBackground(.hidden)
        }
        .id(model.interfaceRevision)
        .background(ShellStyle.background.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.upArrow) {
            model.selectNextScope(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            model.selectNextScope(1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            model.setChosenFolderExpanded(true)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            model.setChosenFolderExpanded(false)
            return .handled
        }
    }
}

@available(macOS 14, *)
private struct ShellSidebarRow: View {
    @Bindable var model: ShellModel
    let row: ShellModel.SidebarRow
    let isSelected: Bool
    @State private var draft = ""
    @State private var isDropTarget = false
    @FocusState private var renaming: Bool

    private var folder: Project? {
        guard case .project(let url) = row.id else { return nil }
        return AppEnvironment.current.storage.getProjects().first { $0.url == url }
    }

    private var isBrand: Bool { row.kind == .All }
    private var fontSize: CGFloat { CGFloat(UserDefaultsManagement.nameFontSize) + (isBrand ? 1 : 0) }

    var body: some View {
        HStack(spacing: isBrand ? 6 : 9) {
            SwiftUI.Image(nsImage: icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: isBrand ? 24 : 15, height: isBrand ? 24 : 15)
                .foregroundStyle(isBrand ? brandTint : ShellStyle.icon)
            if let folder, model.renamingFolderURL == folder.url {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(ShellStyle.interface(fontSize))
                    .focused($renaming)
                    .onSubmit { model.renameFolder(folder, to: draft) }
                    .onExitCommand { model.renamingFolderURL = nil }
                    .onAppear {
                        draft = folder.url.lastPathComponent
                        renaming = true
                    }
                    .onChange(of: renaming) { _, focused in
                        if !focused, model.renamingFolderURL == folder.url { model.renameFolder(folder, to: draft) }
                    }
            } else {
                Group {
                    if isBrand {
                        Text(row.title).font(ShellStyle.brandWordmark(fontSize + 2))
                    } else {
                        Text(row.title)
                            .font(ShellStyle.interface(fontSize))
                            .kerning(ShellStyle.tracking(fontSize))
                    }
                }
                .foregroundStyle(isBrand ? brandTint : ShellStyle.text)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if row.hasChildren, let folder {
                SwiftUI.Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ShellStyle.icon)
                    .rotationEffect(.degrees(model.expandedFolders.contains(folder.url) ? 90 : 0))
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) { model.toggleExpanded(folder.url) }
                    }
            }
        }
        .padding(.leading, (isBrand ? 8 : 11) + CGFloat(row.depth) * 16)
        .padding(.trailing, 8)
        .frame(height: isBrand ? 36 : 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill((isSelected && !isBrand) || isDropTarget ? ShellStyle.sidebarSelection : .clear)
        )
        .contextMenu {
            if let folder {
                Button(I18n.str("New Folder")) { model.promptNewFolder() }
                Button(I18n.str("New Subfolder")) { model.promptNewFolder(parent: folder) }
                Button(I18n.str("Rename Folder")) {
                    model.scope = row.id
                    model.renamingFolderURL = folder.url
                }
                Button(I18n.str("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
                Button(I18n.str("Open in Terminal")) {
                    model.scope = row.id
                    NSApp.sendAction(#selector(ShellWindowController.openInTerminal(_:)), to: nil, from: nil)
                }
                if !folder.isDefault && !folder.isRoot {
                    Divider()
                    Button(I18n.str("Delete Folder")) { model.confirmDeleteFolder(folder) }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder else { return false }
            let storage = AppEnvironment.current.storage
            let notes = urls.compactMap { storage.getBy(url: $0) }
            guard !notes.isEmpty else { return false }
            model.move(notes, to: folder)
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted && folder != nil
        }
    }

    /// The brand row stands for all notes but is a logo, not a list item: it
    /// never takes the selection plate, and shows it is chosen by turning
    /// green, falling back to grey while a folder is open.
    private var brandTint: SwiftUI.Color {
        isSelected ? ShellStyle.accent : ShellStyle.icon
    }

    private var icon: NSImage {
        let name: String
        switch row.kind {
        case .All: name = "home"
        case .Trash: name = "deleteNote"
        case .Category: name = "project"
        }
        return NSImage(named: name) ?? NSImage()
    }
}

// MARK: - Note list

@available(macOS 14, *)
struct ShellNoteList: View {
    @Bindable var model: ShellModel
    @FocusState private var listFocused: Bool
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .frame(height: ShellStyle.headerHeight)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.sections) { section in
                            if let title = section.title {
                                ShellSectionHeader(title: title)
                            }
                            ForEach(section.notes, id: \.url) { note in
                                ShellNoteRow(
                                    note: note,
                                    snippet: model.snippet(for: note),
                                    date: ShellModel.rowDate(for: note),
                                    isSelected: model.selectedNoteURL == note.url
                                )
                                .id(note.url)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.selectedNoteURL = note.url
                                    listFocused = true
                                }
                                .contextMenu { ShellNoteMenu(model: model, note: note) }
                                .draggable(note.url)
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: model.selectedNoteURL) { _, url in
                    guard let url else { return }
                    proxy.scrollTo(url)
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(.upArrow) {
                model.selectNext(-1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                model.selectNext(1)
                return .handled
            }
        }
        .id(model.interfaceRevision)
        .background(ShellStyle.background.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
    }

    /// The folder's name, as Bear heads its list, with search one click away;
    /// a query in progress keeps the field open.
    @ViewBuilder private var header: some View {
        HStack(spacing: 6) {
            if model.layout != .all {
                // The folders are hidden, so the traffic lights and the
                // layout button move into this column.
                Spacer().frame(width: ShellStyle.trafficLightsInset - 16)
                ChromeButton(image: "icon_sidebar_left", help: "Toggle Note List") { model.cycleLayout() }
            }
            if model.isSearchOpen || !model.searchText.isEmpty {
                // Return makes a note named after the query, as the storyboard
                // window's search field does.
                ShellSearchField(
                    text: $model.searchText, focused: $searchFocused,
                    onSubmit: {
                        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.createNote(name: query)
                    }
                ) {
                    model.searchText = ""
                    model.isSearchOpen = false
                }
                .onAppear { searchFocused = true }
            } else {
                let size = CGFloat(UserDefaultsManagement.nameFontSize) + 1
                Text(model.scopeTitle)
                    .font(ShellStyle.interface(size, weight: ShellStyle.titleWeight))
                    .kerning(ShellStyle.tracking(size))
                    .foregroundStyle(ShellStyle.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ChromeButton(symbol: "magnifyingglass", help: "Search") { model.isSearchOpen = true }
            }
        }
    }
}

@available(macOS 14, *)
private struct ShellSectionHeader: View {
    let title: String

    var body: some View {
        let size = CGFloat(UserDefaultsManagement.dateFontSize) + 1
        ShellBoldText(string: title, size: size)
            .foregroundStyle(ShellStyle.tertiaryText)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }
}

/// A note card: the title, two lines of the note's opening and the date,
/// parted from the next by space; the open note sits on a sand plate.
@available(macOS 14, *)
private struct ShellNoteRow: View {
    let note: Note
    let snippet: String?
    let date: String
    let isSelected: Bool

    var body: some View {
        let nameSize = CGFloat(UserDefaultsManagement.nameFontSize)
        let bodySize = nameSize - 1
        let dateSize = CGFloat(UserDefaultsManagement.dateFontSize)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(title)
                    .font(ShellStyle.interface(nameSize, weight: ShellStyle.titleWeight))
                    .kerning(ShellStyle.tracking(nameSize))
                    .foregroundStyle(ShellStyle.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if note.isPinned, let pin = NSImage(named: "pinNote") {
                    SwiftUI.Image(nsImage: pin)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 10, height: 10)
                        .foregroundStyle(ShellStyle.tertiaryText)
                }
            }
            if let snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(ShellStyle.interface(bodySize))
                    .kerning(ShellStyle.tracking(bodySize))
                    .foregroundStyle(ShellStyle.secondaryText)
                    .lineLimit(2)
                    .lineSpacing(ShellStyle.lineSpacing(bodySize))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(date)
                .font(ShellStyle.interface(dateSize))
                .kerning(ShellStyle.tracking(dateSize))
                .foregroundStyle(ShellStyle.tertiaryText)
                .lineLimit(1)
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(ShellStyle.selection)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
        }
    }

    private var title: String {
        let title = note.getTitleWithoutLabel()
        return title.isEmpty ? I18n.str("Untitled Note") : title
    }
}

@available(macOS 14, *)
private struct ShellSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}
    let onClose: () -> Void

    var body: some View {
        let size = CGFloat(UserDefaultsManagement.searchFontSize) + 1
        HStack(spacing: 6) {
            SwiftUI.Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ShellStyle.secondaryText)
            TextField(I18n.str("Search"), text: $text)
                .textFieldStyle(.plain)
                .font(ShellStyle.interface(size))
                .focused(focused)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onClose)
            Button(action: onClose) {
                SwiftUI.Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(ShellStyle.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ShellStyle.field))
    }
}

// MARK: - Detail

@available(macOS 14, *)
struct ShellDetail: View {
    @Bindable var model: ShellModel

    var body: some View {
        VStack(spacing: 0) {
            if !model.isPresenting {
                header
            }
            if let note = model.selectedNote {
                switch model.editorMode {
                case .edit:
                    ShellEditorView(controller: model.editor, note: note)
                case .preview:
                    ShellPreview(note: note, revision: model.contentRevision, styleRevision: model.previewStyleRevision) { model.preview = $0 }
                case .split:
                    HStack(spacing: 0) {
                        ShellEditorView(controller: model.editor, note: note)
                        Rectangle().fill(ShellStyle.hairline).frame(width: 1)
                        ShellPreview(note: note, revision: model.contentRevision, styleRevision: model.previewStyleRevision) { model.preview = $0 }
                    }
                }
            } else {
                SwiftUI.Color.clear
            }
        }
        .background(ShellStyle.background.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
    }

    /// The title starts where the note's text starts; the mode buttons sit
    /// light at the trailing edge.
    private var header: some View {
        let titleSize = CGFloat(UserDefaultsManagement.nameFontSize) + 3
        return HStack(spacing: 4) {
            if model.layout == .noteOnly {
                Spacer().frame(width: ShellStyle.trafficLightsInset - ShellStyle.noteTextInset)
                ChromeButton(image: "icon_sidebar_left", help: "Toggle Note List") { model.cycleLayout() }
                    .padding(.trailing, 6)
            }
            ShellTitleField(model: model, size: titleSize)
            Spacer(minLength: 12)
            // The mode buttons act on a note; with none open they are gone.
            if model.selectedNote != nil {
                ChromeButton(image: "icon_editor_split", help: "Toggle Split Mode", isActive: model.editorMode == .split) {
                    model.toggleSplit()
                }
                ChromeButton(image: "icon_format", help: "Format") { model.format() }
                ChromeButton(image: "icon_preview", help: "Toggle Preview", isActive: model.editorMode == .preview) {
                    model.togglePreview()
                }
                ChromeButton(image: "icon_presentation", help: "Presentation") { model.setPresenting(true) }
            }
        }
        .padding(.leading, ShellStyle.noteTextInset)
        .padding(.trailing, 12)
        .frame(height: ShellStyle.headerHeight)
    }
}

/// The note's title in the header. A double click, ⌘R, or a new note turns it
/// into a field; Return renames the file, Escape leaves it as it was.
@available(macOS 14, *)
private struct ShellTitleField: View {
    @Bindable var model: ShellModel
    let size: CGFloat
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let font = ShellStyle.interface(size, weight: ShellStyle.titleWeight)
        Group {
            if model.isRenaming, model.selectedNote != nil {
                TextField(I18n.str("Untitled Note"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(font)
                    .foregroundStyle(ShellStyle.text)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { model.isRenaming = false }
                    .onAppear {
                        draft = model.selectedNote?.getTitleWithoutLabel() ?? ""
                        focused = true
                    }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() }
                    }
            } else {
                Text(model.selectedNote?.getTitleWithoutLabel() ?? "")
                    .font(font)
                    .kerning(ShellStyle.tracking(size))
                    .foregroundStyle(ShellStyle.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .onTapGesture(count: 2) { model.isRenaming = model.selectedNote != nil }
            }
        }
        .onChange(of: model.selectedNoteURL) { _, url in
            // Selecting another note ends an edit; the selection that opens
            // the field for this note does not.
            if model.renamingNoteURL != url { model.renamingNoteURL = nil }
        }
    }

    private func commit() {
        guard let url = model.renamingNoteURL else { return }
        model.renamingNoteURL = nil
        guard let note = AppEnvironment.current.storage.getBy(url: url) else { return }
        model.rename(note, to: draft)
    }
}

/// The note list's right-click menu, the storyboard note menu's everyday items.
@available(macOS 14, *)
private struct ShellNoteMenu: View {
    let model: ShellModel
    let note: Note

    private func exportSelecting(_ format: ShellModel.ExportFormat) {
        model.selectedNoteURL = note.url
        model.export(format)
    }

    var body: some View {
        Button(I18n.str(note.isPinned ? "Unpin Note" : "Pin Note")) { model.togglePin(note) }
        Button(I18n.str("Rename")) {
            model.selectedNoteURL = note.url
            model.isRenaming = true
        }
        Button(I18n.str("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
        // The storyboard list's menu: info, links and copies of the note.
        Button(I18n.str("Show Info")) {
            model.selectedNoteURL = note.url
            NSApp.sendAction(#selector(ShellWindowController.showInfo(_:)), to: nil, from: nil)
        }
        Button(I18n.str("Copy URL")) {
            model.selectedNoteURL = note.url
            model.copyNoteURL()
        }
        Button(I18n.str("Copy Path")) {
            model.selectedNoteURL = note.url
            model.copyNotePath()
        }
        if !note.isTrash() {
            Button(I18n.str("Duplicate")) {
                model.selectedNoteURL = note.url
                model.duplicateSelectedNote()
            }
            Button(I18n.str("MiaoYan PPT")) {
                model.selectedNoteURL = note.url
                model.setPresenting(true, ppt: true)
            }
        }
        if !note.isTrash() {
            Button(I18n.str("Version History")) {
                model.selectedNoteURL = note.url
                model.showVersionHistory()
            }
        }
        if !note.isTrash() {
            Menu(I18n.str("Move")) {
                ForEach(model.folders.filter { $0 != note.project }, id: \.url) { folder in
                    Button(folder.label) { model.move([note], to: folder) }
                }
            }
        }
        Menu(I18n.str("Export")) {
            Button("PDF") { exportSelecting(.pdf) }
            Button(I18n.str("Image")) { exportSelecting(.image) }
            Button("HTML") { exportSelecting(.html) }
            Button(I18n.str("MiaoYan PPT PDF")) { exportSelecting(.ppt) }
        }
        if !note.isTrash() {
            Divider()
            Button(I18n.str("Delete")) {
                model.selectedNoteURL = note.url
                model.deleteSelectedNote()
            }
        }
    }
}

/// The existing WKWebView preview, loaded with whichever note is open.
@available(macOS 14, *)
struct ShellPreview: NSViewRepresentable {
    let note: Note
    /// A change re-renders the open note in place, keeping its scroll.
    var revision = 0
    /// A change reloads the page, for stylesheet changes (font size).
    var styleRevision = 0
    /// Hands the view to whoever runs commands on it (the TOC toggle).
    var onMake: ((MPreviewView) -> Void)?

    final class Coordinator {
        var loadedURL: URL?
        var loadedModifiedAt: Date?
        var revision = 0
        var styleRevision = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MPreviewView {
        let view = MPreviewView(frame: .zero, note: note, closure: nil)
        onMake?(view)
        load(note, into: view, context: context)
        return view
    }

    func updateNSView(_ view: MPreviewView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.loadedURL != note.url || coordinator.styleRevision != styleRevision {
            load(note, into: view, context: context)
        } else if coordinator.revision != revision {
            coordinator.revision = revision
            view.updateContent(note: note)
        } else if coordinator.loadedModifiedAt != note.modifiedLocalAt {
            // The note was written since the last render, by its own debounced
            // save or by a sync. Refresh the content in place; a full template
            // reload here repainted the whole preview after every typing pause.
            coordinator.loadedModifiedAt = note.modifiedLocalAt
            view.updateContent(note: note)
        }
    }

    private func load(_ note: Note, into view: MPreviewView, context: Context) {
        context.coordinator.loadedURL = note.url
        context.coordinator.loadedModifiedAt = note.modifiedLocalAt
        context.coordinator.revision = revision
        context.coordinator.styleRevision = styleRevision
        let coordinator = context.coordinator
        Task { @MainActor in
            await note.ensureContentLoadedAsync()
            // Another note may have been selected while this one loaded.
            guard coordinator.loadedURL == note.url else { return }
            view.load(note: note, force: true)
        }
    }
}
