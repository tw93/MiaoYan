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
            HStack {
                Spacer()
                ChromeButton(image: "icon_sidebar_left", help: "Toggle Note List") { model.cycleLayout() }
            }
            .padding(.horizontal, 10)
            .frame(height: ShellStyle.headerHeight)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(model.sidebarRows) { row in
                        ShellSidebarRow(row: row, isSelected: model.scope == row.id)
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
    }
}

@available(macOS 14, *)
private struct ShellSidebarRow: View {
    let row: ShellModel.SidebarRow
    let isSelected: Bool

    private var isBrand: Bool { row.kind == .All }
    private var fontSize: CGFloat { CGFloat(UserDefaultsManagement.nameFontSize) + (isBrand ? 1 : 0) }

    var body: some View {
        HStack(spacing: isBrand ? 6 : 9) {
            SwiftUI.Image(nsImage: icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: isBrand ? 20 : 15, height: isBrand ? 20 : 15)
                .foregroundStyle(isBrand ? brandTint : ShellStyle.icon)
            Text(row.title)
                .font(ShellStyle.interface(fontSize, weight: isBrand ? .semibold : .regular))
                .kerning(ShellStyle.tracking(fontSize))
                .foregroundStyle(isBrand ? brandTint : ShellStyle.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.leading, isBrand ? 8 : 11)
        .padding(.trailing, 8)
        .frame(height: isBrand ? 36 : 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected && !isBrand ? ShellStyle.sidebarSelection : .clear)
        )
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
    @State private var isSearchOpen = false

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
            if isSearchOpen || !model.searchText.isEmpty {
                ShellSearchField(text: $model.searchText, focused: $searchFocused) {
                    model.searchText = ""
                    isSearchOpen = false
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
                ChromeButton(symbol: "magnifyingglass", help: "Search") { isSearchOpen = true }
            }
        }
    }
}

@available(macOS 14, *)
private struct ShellSectionHeader: View {
    let title: String

    var body: some View {
        let size = CGFloat(UserDefaultsManagement.dateFontSize) + 1
        Text(title)
            .font(ShellStyle.interface(size, weight: .semibold))
            .kerning(ShellStyle.tracking(size))
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
                    .lineSpacing(2)
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
                    ShellPreview(note: note, revision: model.contentRevision)
                case .split:
                    HStack(spacing: 0) {
                        ShellEditorView(controller: model.editor, note: note)
                        Rectangle().fill(ShellStyle.hairline).frame(width: 1)
                        ShellPreview(note: note, revision: model.contentRevision)
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
            Text(model.selectedNote?.getTitleWithoutLabel() ?? "")
                .font(ShellStyle.interface(titleSize, weight: ShellStyle.titleWeight))
                .kerning(ShellStyle.tracking(titleSize))
                .foregroundStyle(ShellStyle.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            ChromeButton(image: "icon_editor_split", help: "Toggle Split Mode", isActive: model.editorMode == .split) {
                model.toggleSplit()
            }
            ChromeButton(image: "icon_format", help: "Format") { model.format() }
            ChromeButton(image: "icon_preview", help: "Toggle Preview", isActive: model.editorMode == .preview) {
                model.togglePreview()
            }
            ChromeButton(image: "icon_presentation", help: "Presentation") { model.setPresenting(true) }
        }
        .padding(.leading, ShellStyle.noteTextInset)
        .padding(.trailing, 12)
        .frame(height: ShellStyle.headerHeight)
    }
}

/// The existing WKWebView preview, loaded with whichever note is open.
@available(macOS 14, *)
struct ShellPreview: NSViewRepresentable {
    let note: Note
    /// A change re-renders the open note in place, keeping its scroll.
    var revision = 0

    final class Coordinator {
        var loadedURL: URL?
        var loadedModifiedAt: Date?
        var revision = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MPreviewView {
        let view = MPreviewView(frame: .zero, note: note, closure: nil)
        load(note, into: view, context: context)
        return view
    }

    func updateNSView(_ view: MPreviewView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.loadedURL != note.url {
            load(note, into: view, context: context)
        } else if coordinator.revision != revision {
            coordinator.revision = revision
            view.updateContent(note: note)
        } else if coordinator.loadedModifiedAt != note.modifiedLocalAt {
            load(note, into: view, context: context)
        }
    }

    private func load(_ note: Note, into view: MPreviewView, context: Context) {
        context.coordinator.loadedURL = note.url
        context.coordinator.loadedModifiedAt = note.modifiedLocalAt
        context.coordinator.revision = revision
        Task { @MainActor in
            await note.ensureContentLoadedAsync()
            view.load(note: note, force: true)
        }
    }
}
