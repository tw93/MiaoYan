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

    /// The brand wordmark, upright Charter at regular weight as in the
    /// storyboard window's sidebar, falling back to the interface face.
    static func brandWordmark(_ size: CGFloat) -> SwiftUI.Font {
        if let charter = NSFont(name: "Charter-Roman", size: size) { return SwiftUI.Font(charter) }
        return interface(size)
    }

    /// Spacing that sets multi-line text at 1.45em. `lineSpacing` adds to the
    /// face's own line height, which is 1.23em for TsangerJinKai02 and 1.38em
    /// for PingFang, so a fixed figure reads tight in one and loose in the other.
    /// Every list row asks on every render, so the figure is kept per face
    /// and size rather than measured with a new layout manager each time.
    static func lineSpacing(_ size: CGFloat) -> CGFloat {
        let font = FontConfiguration.interfaceFont(size: size)
        let key = "\(font.fontName) \(size)"
        if let spacing = lineSpacingCache[key] { return spacing }
        let spacing = max(0, size * 1.45 - NSLayoutManager().defaultLineHeight(for: font))
        lineSpacingCache[key] = spacing
        return spacing
    }

    private static var lineSpacingCache: [String: CGFloat] = [:]

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
        // An image-only button is read as "button" without a label.
        .accessibilityLabel(I18n.str(help))
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
            // Scrolled rows draw past the scroll view's top; an opaque header
            // above them keeps them from showing through the title line.
            .background(ShellTitleBarArea())
            .background(ShellStyle.background)
            .zIndex(1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ShellSidebarBrand(title: model.brandTitle)
                        SwiftUI.Color.clear.frame(height: 6)
                        ForEach(model.sidebarRows) { row in
                            ShellSidebarRow(model: model, row: row, isSelected: model.scope == row.id)
                                .id(row.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.scope = row.id
                                    focused = true
                                }
                                .accessibilityAction { model.scope = row.id }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
                .scrollContentBackground(.hidden)
                // The chosen row stays in view, whether the arrows moved to it
                // or it is a deep folder remembered from the last launch.
                .onChange(of: model.scope) { _, scope in proxy.scrollTo(scope) }
                .onAppear {
                    Task { @MainActor in proxy.scrollTo(model.scope) }
                }
            }
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
        .onKeyPress(.leftArrow) {
            model.setChosenFolderExpanded(false)
            return .handled
        }
        .onChange(of: model.focusRequest) { _, request in
            guard request == .sidebar else { return }
            focused = true
            model.focusRequest = nil
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

    private var isRenaming: Bool {
        guard case .project(let url) = row.id else { return false }
        return model.renamingFolderURL == url
    }
    private var fontSize: CGFloat { CGFloat(UserDefaultsManagement.nameFontSize) }

    var body: some View {
        HStack(spacing: 9) {
            SwiftUI.Image(nsImage: icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(ShellStyle.icon)
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
                Text(row.title)
                    .font(ShellStyle.interface(fontSize))
                    .kerning(ShellStyle.tracking(fontSize))
                    .foregroundStyle(ShellStyle.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // A long name cut short shows in full on hover, as the
                    // storyboard outline's expansion tooltips do.
                    .help(row.title)
            }
            Spacer(minLength: 0)
            if row.hasChildren, let folder {
                SwiftUI.Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ShellStyle.icon)
                    .rotationEffect(.degrees(model.isExpanded(folder.url) ? 90 : 0))
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) { model.toggleExpanded(folder.url) }
                    }
            }
        }
        .padding(.leading, 11 + CGFloat(row.depth) * 16)
        .padding(.trailing, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected || isDropTarget ? ShellStyle.sidebarSelection : .clear)
        )
        // VoiceOver reads a row as one button named after the folder.
        // While renaming, its field stays reachable on its own.
        .accessibilityElement(children: isRenaming ? .contain : .combine)
        .accessibilityLabel(row.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .onHover { inside in
            if inside {
                model.hoveredSidebarRow = row.id
            } else if model.hoveredSidebarRow == row.id {
                model.hoveredSidebarRow = nil
            }
        }
        // The storyboard sidebar's menu, which shows per row only what
        // applies: no New Folder on a folder, Open in Terminal on All Notes
        // for the library, Show in Finder alone on the Trash.
        .contextMenu {
            if let folder {
                item("New Subfolder", "folder.badge.plus") { model.promptNewFolder(parent: folder) }
                if !folder.isRoot {
                    item("Rename Folder", "pencil") {
                        model.scope = row.id
                        model.renamingFolderURL = folder.url
                    }
                    .disabled(folder.isDefault)
                }
                if !folder.isRoot && !folder.isDefault && !folder.isTrash {
                    item("Move to…", "arrow.up.right.circle") { model.promptMoveFolder(folder) }
                }
                item("Show in Finder", "folder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
                item("Open in Terminal", "terminal") { openInTerminal() }
                if !folder.isDefault && !folder.isRoot {
                    Divider()
                    item("Delete Folder", "trash") { model.confirmDeleteFolder(folder) }
                }
            } else if row.kind == .Trash, let trash = AppEnvironment.current.storage.getDefaultTrash() {
                item("Show in Finder", "folder") { NSWorkspace.shared.activateFileViewerSelecting([trash.url]) }
            } else if row.kind == .All {
                item("Open in Terminal", "terminal") { openInTerminal() }
            }
        }
        .modifier(ShellFolderDrag(url: row.depth == 0 ? folder?.url : nil))
        .dropDestination(for: URL.self) { urls, _ in
            let isTrash = row.kind == .Trash
            guard folder != nil || isTrash else { return false }
            // A top-level folder dragged onto another takes its place.
            if let folder, row.depth == 0, urls.count == 1, let dragged = urls.first, model.isTopLevelFolder(dragged) {
                return model.reorderFolder(dragged, onto: folder.url)
            }
            let storage = AppEnvironment.current.storage
            var notes = urls.compactMap { storage.getBy(url: $0) }
            // A row drags only its own URL; one that is part of a multiple
            // selection carries the whole selection, as the storyboard list does.
            if notes.count == 1, let dragged = notes.first, model.isSelected(dragged) {
                notes = model.selectedNotes
            }
            guard !notes.isEmpty else {
                // Finder files are copied into the folder; a Finder folder
                // becomes a subfolder of the same name.
                return folder.map { model.importDropped(urls, into: $0, keepingFolders: true) } ?? false
            }
            if let folder {
                model.move(notes, to: folder)
            } else {
                model.moveToTrash(notes)
            }
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted && (folder != nil || row.kind == .Trash)
        }
    }

    private func item(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(I18n.str(title), systemImage: symbol)
        }
    }

    /// The row's folder, or the library from All Notes.
    private func openInTerminal() {
        model.scope = row.id
        NSApp.sendAction(#selector(ShellWindowController.openInTerminal(_:)), to: nil, from: nil)
    }

    private var icon: NSImage {
        let name: String
        switch row.kind {
        case .Brand: name = "home"
        case .All: name = "allNotes"
        case .Trash: name = "deleteNote"
        case .Category: name = "project"
        }
        return NSImage(named: name) ?? NSImage()
    }
}

/// The MiaoYan lockup over the sidebar rows, the storyboard sidebar's brand
/// row: a mark, not a place, so it takes no clicks, plate or menu, and All
/// Notes sits under it (maintainer, 2026-10-19).
@available(macOS 14, *)
private struct ShellSidebarBrand: View {
    let title: String

    var body: some View {
        let size = CGFloat(UserDefaultsManagement.nameFontSize) + 2
        HStack(spacing: 5) {
            SwiftUI.Image(nsImage: NSImage(named: "home") ?? NSImage())
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
            Text(title)
                .font(ShellStyle.brandWordmark(size))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .foregroundStyle(ShellStyle.accent)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(height: 36)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Top-level folder rows can be dragged to reorder the sidebar, as in the
/// storyboard sidebar; subfolders, All Notes and the Trash stay put.
@available(macOS 14, *)
private struct ShellFolderDrag: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url {
            content.draggable(url)
        } else {
            content
        }
    }
}

// MARK: - Note list

@available(macOS 14, *)
struct ShellNoteList: View {
    @Bindable var model: ShellModel
    @FocusState private var listFocused: Bool
    @FocusState private var searchFocused: Bool
    @State private var scrollBox = ShellScrollViewBox()
    /// Each folder's scroll place, for this session.
    @State private var scrollOffsets: [ShellModel.Scope: CGFloat] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .frame(height: ShellStyle.headerHeight)
                .background(ShellTitleBarArea())
                .background(ShellStyle.background)
                .zIndex(1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.sections) { section in
                            if let title = section.title {
                                ShellSectionHeader(title: title)
                            }
                            ForEach(Array(section.notes.enumerated()), id: \.element.url) { index, note in
                                let next = section.notes.indices.contains(index + 1) ? section.notes[index + 1] : nil
                                let isSelected = model.isSelected(note)
                                ShellNoteRow(
                                    note: note,
                                    snippet: model.snippet(for: note),
                                    date: ShellModel.rowDate(for: note),
                                    isSelected: isSelected,
                                    showsDivider: !isSelected && !(next.map(model.isSelected) ?? false)
                                )
                                .id(note.url)
                                .background {
                                    // File ▸ Export pops its menu at the open note's row.
                                    if note.url == model.selectedNoteURL {
                                        GeometryReader { proxy in
                                            let frame = proxy.frame(in: .global)
                                            SwiftUI.Color.clear
                                                .onAppear { model.selectedRowFrame = frame }
                                                .onChange(of: frame) { _, frame in model.selectedRowFrame = frame }
                                                .onDisappear {
                                                    if model.selectedRowFrame == frame { model.selectedRowFrame = nil }
                                                }
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.clickNote(note, modifiers: NSEvent.modifierFlags)
                                    listFocused = true
                                }
                                .accessibilityAction {
                                    model.clickNote(note, modifiers: [])
                                    listFocused = true
                                }
                                // A right-click selects the row under the pointer first.
                                .onHover { inside in
                                    if inside {
                                        model.hoveredNoteURL = note.url
                                    } else if model.hoveredNoteURL == note.url {
                                        model.hoveredNoteURL = nil
                                    }
                                }
                                .contextMenu { ShellNoteMenu(model: model, note: note) }
                                .draggable(note.url)
                            }
                        }
                    }
                    .padding(.bottom, 10)
                    .background(alignment: .topLeading) {
                        ShellScrollViewProbe { scrollBox.view = $0 }.frame(width: 1, height: 1)
                    }
                }
                .scrollContentBackground(.hidden)
                .onChange(of: model.selectedNoteURL) { _, url in
                    guard let url else { return }
                    proxy.scrollTo(url)
                }
                // NotesTableView keeps each folder's scroll place and shows
                // the open note when the list comes back to a folder.
                .onChange(of: model.scope) { old, _ in
                    guard model.listContent == .init(scope: old, isSearch: false),
                        let offset = scrollBox.view?.contentView.bounds.origin.y
                    else { return }
                    scrollOffsets[old] = offset
                }
                .onChange(of: model.listContent) { old, new in
                    guard let new, !new.isSearch else { return }
                    revealSelection(proxy, restoring: old?.scope == new.scope ? nil : scrollOffsets[new.scope] ?? 0)
                }
                .onAppear {
                    if model.listContent != nil { revealSelection(proxy, restoring: nil) }
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
            .onChange(of: model.focusRequest) { _, request in
                switch request {
                case .list:
                    listFocused = true
                case .search:
                    model.isSearchOpen = true
                    if searchFocused {
                        // Marked focused while the editor has the keys, or
                        // set while the column was collapsed: focus again.
                        searchFocused = false
                        Task { @MainActor in searchFocused = true }
                    } else {
                        searchFocused = true
                    }
                default:
                    return
                }
                model.focusRequest = nil
            }
            // Finder files dropped on the list are imported into the chosen
            // folder, or the main folder from All Notes.
            .dropDestination(for: URL.self) { urls, _ in
                model.importDropped(urls, into: model.dropProject)
            }
        }
        .id(model.interfaceRevision)
        .background(ShellStyle.background.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
    }

    /// NotesTableView.restoreScrollPosition: the folder's remembered place
    /// (`offset`, the top for one not seen yet), then the open note scrolled
    /// into view when it is off screen. Runs once the new rows are laid out.
    private func revealSelection(_ proxy: ScrollViewProxy, restoring offset: CGFloat?) {
        Task { @MainActor in
            if let offset, let scrollView = scrollBox.view {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            if let url = model.selectedNoteURL { proxy.scrollTo(url) }
        }
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
                // Return opens the matching note and Command-Return makes one
                // named after the query, as the storyboard window's search
                // field does; the window controller's key monitor takes both.
                ShellSearchField(
                    text: $model.searchText, focused: $searchFocused
                ) {
                    model.searchText = ""
                    model.isSearchOpen = false
                    // The field goes away; the list keeps the keys, so the
                    // arrows and Command-Delete work without a click.
                    listFocused = true
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

/// The AppKit scroll view behind the note list's ScrollView, whose offset
/// SwiftUI on macOS 14 neither reports nor sets.
@MainActor
private final class ShellScrollViewBox {
    weak var view: NSScrollView?
}

/// Hands over the scroll view it sits in once it is in a window.
@available(macOS 14, *)
private struct ShellScrollViewProbe: NSViewRepresentable {
    let found: (NSScrollView) -> Void

    final class Probe: NSView {
        var found: ((NSScrollView) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let scrollView = enclosingScrollView { found?(scrollView) }
        }
    }

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.found = found
        return view
    }

    func updateNSView(_ view: Probe, context: Context) {
        view.found = found
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
/// parted from the next by a hairline inset to the title; the open note sits
/// on a sand plate and the lines beside it hide, as in the storyboard list.
@available(macOS 14, *)
private struct ShellNoteRow: View {
    let note: Note
    let snippet: String?
    let date: String
    let isSelected: Bool
    let showsDivider: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let nameSize = CGFloat(UserDefaultsManagement.nameFontSize)
        let bodySize = nameSize - 1
        let dateSize = CGFloat(UserDefaultsManagement.dateFontSize)
        let titleText = Text(title)
            .font(ShellStyle.interface(nameSize, weight: ShellStyle.titleWeight))
            .kerning(ShellStyle.tracking(nameSize))
            .foregroundStyle(ShellStyle.text)
            .lineLimit(1)
            .truncationMode(.tail)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                // A cut-off title shows in full on hover, as the storyboard
                // list's expansion tooltips do; one that fits shows none.
                ViewThatFits(in: .horizontal) {
                    titleText
                    titleText.help(title)
                }
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
        .overlay(alignment: .bottom) {
            if showsDivider {
                ShellStyle.hairline
                    .frame(height: 1 / displayScale)
                    .padding(.horizontal, 20)
            }
        }
        // VoiceOver reads a row as one item: the title, then its date and
        // opening; the list's tap action is its default action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([date, snippet ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
                    ShellPreview(
                        note: note, revision: model.contentRevision, styleRevision: model.previewStyleRevision,
                        onMake: { model.preview = $0 }, onLoad: { model.previewDidLoad($0) })
                case .split:
                    ShellEditorSplit(
                        controller: model.editor, note: note,
                        preview: ShellPreview(
                            note: note, revision: model.contentRevision, styleRevision: model.previewStyleRevision,
                            onMake: { model.preview = $0 }, onLoad: { model.editor.splitPreviewDidLoad($0) }))
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
        // Button Display "On Hover" keeps them out of sight until the
        // pointer is over the header, as the storyboard title bar does.
        let showsButtons = !isButtonDisplayOnHover || isHoveringHeader
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
                HStack(spacing: 4) {
                    ChromeButton(image: "icon_editor_split", help: "Toggle Split Mode", isActive: model.editorMode == .split) {
                        model.toggleSplit()
                    }
                    ChromeButton(image: "icon_format", help: model.isFormatting ? "Formatting... click again to cancel" : "Format") {
                        model.format()
                    }
                    .opacity(model.isFormatting ? 0.6 : 1)
                    ChromeButton(image: "icon_preview", help: "Toggle Preview", isActive: model.editorMode == .preview) {
                        model.togglePreview()
                    }
                    ChromeButton(image: "icon_presentation", help: "Presentation") { model.setPresenting(true) }
                }
                .opacity(showsButtons ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: showsButtons)
            }
        }
        .padding(.leading, ShellStyle.noteTextInset)
        .padding(.trailing, 12)
        .frame(height: ShellStyle.headerHeight)
        .background(ShellTitleBarArea())
        .background(ShellHoverTracker { isHoveringHeader = $0 })
    }

    @State private var isHoveringHeader = false
    /// UserDefaultsManagement.buttonShow, observed so a change in Settings
    /// shows or hides the buttons at once.
    @AppStorage("buttonShow") private var buttonShow = "Always"

    private var isButtonDisplayOnHover: Bool {
        buttonShow == "Hover"
    }
}

/// Reports the pointer entering and leaving its area without taking clicks,
/// so the header's empty space still drags the window.
@available(macOS 14, *)
private struct ShellHoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var area: NSTrackingArea?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
            addTrackingArea(area)
            self.area = area
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }
}

/// The note's title in the header. A click, ⌘R, or a new note turns it into
/// a field; Return renames the file, Escape leaves it as it was.
@available(macOS 14, *)
private struct ShellTitleField: View {
    @Bindable var model: ShellModel
    let size: CGFloat
    @FocusState private var focused: Bool

    var body: some View {
        let font = ShellStyle.interface(size, weight: ShellStyle.titleWeight)
        Group {
            if model.isRenaming, model.selectedNote != nil {
                TextField(I18n.str("Untitled Note"), text: $model.renameDraft)
                    .textFieldStyle(.plain)
                    .font(font)
                    .foregroundStyle(ShellStyle.text)
                    .focused($focused)
                    .onSubmit {
                        // Return goes on to the note's text, as in the storyboard
                        // window, which keeps Japanese input's Return in place.
                        model.commitPendingRename()
                        if UserDefaultsManagement.defaultLanguage != 0x02 { model.focusEditor() }
                    }
                    .onExitCommand { model.isRenaming = false }
                    .onAppear {
                        model.beginRenameDraft()
                        focused = true
                    }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { model.commitPendingRename() }
                    }
                    .onChange(of: model.renameDraft) { _, draft in
                        let line = ShellModel.singleLineTitle(draft)
                        if line != draft { model.renameDraft = line }
                    }
            } else {
                // One click starts editing, as the storyboard window's title
                // field does.
                // A new note has no title yet; an empty Text had no width to
                // click, so its title could not be edited at all.
                let title = model.selectedNote?.getTitleWithoutLabel() ?? ""
                Text(title.isEmpty && model.selectedNote != nil ? I18n.str("Untitled Note") : title)
                    .font(font)
                    .kerning(ShellStyle.tracking(size))
                    .foregroundStyle(title.isEmpty ? ShellStyle.tertiaryText : ShellStyle.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { model.isRenaming = model.selectedNote != nil }
            }
        }
        .onChange(of: model.selectedNoteURL) { _, url in
            // Selecting another note ends an edit and keeps what was typed:
            // the field leaves with the old selection, often before its
            // focus-loss commit could run. The selection that opens the field
            // for this note does not end it.
            if model.renamingNoteURL != url { model.commitPendingRename() }
        }
    }
}

/// The note list's right-click menu: the storyboard note menu's items in
/// its order with its SF Symbols (Main.storyboard's note menu, the icons
/// from `MenuIconRegistry`, Version History and Move appended as
/// `loadMoveMenu` does), keeping a Pin or Unpin title for the clicked note.
@available(macOS 14, *)
private struct ShellNoteMenu: View {
    let model: ShellModel
    let note: Note

    private func exportSelecting(_ format: ShellModel.ExportFormat) {
        model.selectedNoteURL = note.url
        model.export(format)
    }

    private func item(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(I18n.str(title), systemImage: symbol)
        }
    }

    var body: some View {
        let group = model.notesForMenu(on: note)
        Group {
            item("Show Info", "info.circle") {
                model.selectedNoteURL = note.url
                NSApp.sendAction(#selector(ShellWindowController.showInfo(_:)), to: nil, from: nil)
            }
            item("Reveal in Finder", "folder") { model.revealInFinder(group) }
            item("Copy URL", "link") {
                model.selectedNoteURL = note.url
                model.copyNoteURL()
            }
            item("Copy Path", "doc.on.clipboard") { model.copyNotePaths(group) }
            Divider()
            if !note.isTrash() {
                item("MiaoYan PPT", "sparkles") {
                    model.selectedNoteURL = note.url
                    model.setPresenting(true, ppt: true)
                }
                Divider()
            }
            item(note.isPinned ? "Unpin Note" : "Pin Note", "flag") { model.togglePin(note) }
            if !note.isTrash() {
                item("Duplicate", "plus.square.on.square") { model.duplicate(group) }
            }
            // The storyboard hides Rename for a multiple selection.
            if group.count <= 1 {
                item("Rename", "pencil") {
                    model.selectedNoteURL = note.url
                    model.isRenaming = true
                }
            }
            item("Delete", "trash") { delete() }
            Menu {
                item("HTML", "chevron.left.forwardslash.chevron.right") { exportSelecting(.html) }
                item("Image", "photo") { exportSelecting(.image) }
                item("PDF", "doc.richtext") { exportSelecting(.pdf) }
                item("MiaoYan PPT PDF", "wand.and.stars") { exportSelecting(.ppt) }
                    // A deck needs a --- slide break; an unread note is let through.
                    .disabled(!model.hasSlides(note))
            } label: {
                Label(I18n.str("Export"), systemImage: "square.and.arrow.up")
            }
            if !note.isTrash() {
                item("Version History", "clock.arrow.circlepath") {
                    model.selectedNoteURL = note.url
                    model.showVersionHistory()
                }
            }
            Menu {
                // Notes already in the Trash move back out by these folders.
                if !note.isTrash() {
                    item("Trash", "trash") { delete() }
                    Divider()
                }
                ForEach(model.moveTargets(for: note), id: \.url) { folder in
                    Button {
                        model.move(group, to: folder)
                    } label: {
                        Label(folder.label, systemImage: "folder")
                    }
                }
            } label: {
                Label(I18n.str("Move"), systemImage: "arrow.up.right.circle")
            }
        }
        .labelStyle(.titleAndIcon)
    }

    /// Part of the selection: delete all of it, keeping the selection. In
    /// the Trash this moves them on to the system Trash.
    private func delete() {
        if !model.isSelected(note) { model.selectedNoteURL = note.url }
        model.deleteSelectedNote()
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
    /// Called once the note has started loading into the page.
    var onLoad: ((MPreviewView) -> Void)?

    final class Coordinator {
        var loadedURL: URL?
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

    /// Typing reaches the split preview from the editor controller, and a
    /// change from outside bumps `revision`; a save alone renders nothing.
    func updateNSView(_ view: MPreviewView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.loadedURL != note.url || coordinator.styleRevision != styleRevision {
            // NotesTableView: switching notes closes the preview's find bar.
            if coordinator.loadedURL != note.url, view.isSearchBarVisible { view.hideSearchBar() }
            load(note, into: view, context: context)
        } else if coordinator.revision != revision {
            coordinator.revision = revision
            view.updateContent(note: note)
        }
    }

    private func load(_ note: Note, into view: MPreviewView, context: Context) {
        context.coordinator.loadedURL = note.url
        context.coordinator.revision = revision
        context.coordinator.styleRevision = styleRevision
        let coordinator = context.coordinator
        let onLoad = onLoad
        Task { @MainActor in
            await note.ensureContentLoadedAsync()
            // Another note may have been selected while this one loaded.
            guard coordinator.loadedURL == note.url else { return }
            view.load(note: note, force: true)
            onLoad?(view)
        }
    }
}
