import Cocoa

// MARK: - Menu Icon Management

@available(macOS 11.0, *)
extension NSMenu {
    @MainActor
    func applyMenuIcons() {
        for item in items {
            if let symbolName = MenuIconRegistry.symbol(for: item),
                let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: item.title)
            {
                image.isTemplate = true
                item.image = image
            }

            if let submenu = item.submenu {
                submenu.applyMenuIcons()
            }
        }
    }

    func setMenuItemIdentifier(_ identifier: String, forTitle title: String) {
        item(withTitle: title)?.identifier = NSUserInterfaceItemIdentifier(identifier)
    }
}

extension NSMenuItem {
    func setIdentifier(_ identifier: String) {
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
    }
}

// MARK: - Icon Registry

@available(macOS 11.0, *)
enum MenuIconRegistry {
    @MainActor
    private static var symbolCache: [String: String?] = [:]

    // MARK: - Icon Mappings Configuration

    private struct IconMapping {
        let symbol: String
        let selectors: [String]
        let identifiers: [String]
    }

    private static let iconMappings: [IconMapping] = [
        IconMapping(symbol: "info.circle", selectors: ["showInfo:", "showAboutWindow:"], identifiers: []),
        IconMapping(symbol: "heart", selectors: ["openCats:"], identifiers: []),
        IconMapping(symbol: "gearshape", selectors: ["openPreferences:"], identifiers: []),
        IconMapping(symbol: "rectangle.stack", selectors: ["activeWindow:", "openMainWindow:", "arrangeInFront:"], identifiers: []),
        IconMapping(symbol: "eye.slash", selectors: ["hide:", "hideOtherApplications:"], identifiers: []),
        IconMapping(symbol: "eye", selectors: ["unhideAllApplications:", "togglePreview:"], identifiers: []),
        IconMapping(symbol: "trash", selectors: ["cleanUnusedAttachments:", "deleteNote:"], identifiers: []),
        IconMapping(symbol: "power", selectors: ["quiteApp:"], identifiers: []),
        IconMapping(symbol: "square.and.pencil", selectors: ["fileMenuNewNote:"], identifiers: []),
        IconMapping(symbol: "externaldrive.badge.plus", selectors: ["singleOpen:"], identifiers: []),
        IconMapping(symbol: "magnifyingglass", selectors: ["searchAndCreate:"], identifiers: []),
        IconMapping(symbol: "plus.square.on.square", selectors: ["duplicate:"], identifiers: []),
        IconMapping(symbol: "pencil", selectors: ["renameMenu:"], identifiers: []),
        IconMapping(symbol: "folder", selectors: ["finderMenu:", "revealInFinder:"], identifiers: []),
        IconMapping(symbol: "square.and.arrow.up", selectors: ["exportMenu:"], identifiers: ["noteMenu.export"]),
        IconMapping(symbol: "arrow.up.right.circle", selectors: ["moveMenu:"], identifiers: ["noteMenu.move"]),
        IconMapping(symbol: "xmark.circle", selectors: ["performClose:"], identifiers: []),
        IconMapping(symbol: "line.3.horizontal.decrease.circle", selectors: ["sortBy:"], identifiers: ["viewMenu.sortBy"]),
        IconMapping(symbol: "arrow.up.and.down.circle", selectors: ["sortDirectionBy:"], identifiers: []),
        IconMapping(symbol: "sidebar.left", selectors: ["toggleSidebarPanel:"], identifiers: []),
        IconMapping(symbol: "list.bullet.rectangle", selectors: ["toggleNoteList:"], identifiers: []),
        IconMapping(symbol: "rectangle.on.rectangle", selectors: ["togglePresentation:"], identifiers: []),
        IconMapping(symbol: "arrow.up.left.and.arrow.down.right", selectors: ["toggleFullScreen:"], identifiers: []),
        IconMapping(symbol: "bold", selectors: ["boldMenu:"], identifiers: []),
        IconMapping(symbol: "italic", selectors: ["italicMenu:"], identifiers: []),
        IconMapping(symbol: "underline", selectors: ["underlineMenu:"], identifiers: []),
        IconMapping(symbol: "text.badge.minus", selectors: ["deletelineMenu:"], identifiers: []),
        IconMapping(symbol: "link", selectors: ["linkMenu:", "copyURL:"], identifiers: []),
        IconMapping(symbol: "checkmark.square", selectors: ["todoMenu:"], identifiers: []),
        IconMapping(symbol: "arrow.left", selectors: ["shiftLeft:"], identifiers: []),
        IconMapping(symbol: "arrow.right", selectors: ["shiftRight:"], identifiers: []),
        IconMapping(symbol: "textformat", selectors: ["formatText:"], identifiers: []),
        IconMapping(symbol: "doc.on.doc", selectors: ["noteCopy:", "copy:"], identifiers: []),
        IconMapping(symbol: "text.magnifyingglass", selectors: ["textFinder:"], identifiers: []),
        IconMapping(symbol: "arrow.down.right.and.arrow.up.left.rectangle", selectors: ["performMiniaturize:"], identifiers: []),
        IconMapping(symbol: "plus.magnifyingglass", selectors: ["performZoom:"], identifiers: []),
        IconMapping(symbol: "globe", selectors: ["openMiaoYan:"], identifiers: []),
        IconMapping(symbol: "chevron.left.slash.chevron.right", selectors: ["openGithub:"], identifiers: []),
        IconMapping(symbol: "paperplane", selectors: ["openTelegram:"], identifiers: []),
        IconMapping(symbol: "bird", selectors: ["openTwitter:"], identifiers: []),
        IconMapping(symbol: "doc.text.magnifyingglass", selectors: ["openRelease:"], identifiers: []),
        IconMapping(symbol: "exclamationmark.bubble", selectors: ["openIssue:"], identifiers: []),
        IconMapping(symbol: "sparkles", selectors: ["toggleMagicPPT:"], identifiers: []),
        IconMapping(symbol: "flag", selectors: ["pinMenu:"], identifiers: []),
        IconMapping(symbol: "pin.circle", selectors: ["toggleAlwaysOnTop:"], identifiers: ["viewMenu.alwaysOnTop"]),
        IconMapping(symbol: "chevron.left.forwardslash.chevron.right", selectors: ["exportHtml:"], identifiers: []),
        IconMapping(symbol: "photo", selectors: ["exportImage:"], identifiers: []),
        IconMapping(symbol: "doc.richtext", selectors: ["exportPdf:"], identifiers: []),
        IconMapping(symbol: "wand.and.stars", selectors: ["exportMiaoYanPPT:"], identifiers: []),
        IconMapping(symbol: "folder.badge.plus", selectors: ["addProject:"], identifiers: []),
        IconMapping(symbol: "folder.badge.plus", selectors: ["newSubfolder:"], identifiers: []),
        IconMapping(symbol: "trash", selectors: ["deleteMenu:"], identifiers: []),
        IconMapping(symbol: "xmark.circle.fill", selectors: ["closeAll:"], identifiers: []),
        IconMapping(symbol: "plus.circle", selectors: ["add:"], identifiers: []),
        IconMapping(symbol: "mic", selectors: ["startDictation:"], identifiers: []),
        IconMapping(symbol: "character.book.closed", selectors: ["orderFrontCharacterPalette:"], identifiers: []),
        IconMapping(symbol: "arrow.triangle.2.circlepath", selectors: ["checkForUpdates:"], identifiers: []),
        IconMapping(symbol: "arrow.uturn.backward", selectors: ["undo:"], identifiers: []),
        IconMapping(symbol: "arrow.uturn.forward", selectors: ["redo:"], identifiers: []),
        IconMapping(symbol: "scissors", selectors: ["cut:"], identifiers: []),
        IconMapping(symbol: "clipboard", selectors: ["paste:"], identifiers: []),
        IconMapping(symbol: "clipboard.fill", selectors: ["pasteAsPlainText:"], identifiers: []),
        IconMapping(symbol: "square.grid.2x2", selectors: ["selectAll:"], identifiers: []),
        IconMapping(symbol: "scope", selectors: ["centerSelectionInVisibleArea:"], identifiers: []),
    ]

    private static let suppressedSelectors: Set<String> = [
        "submenuAction:",
        "_handleInsertFromContactsCommand:",
        "_handleInsertFromPasswordsCommand:",
        "_handleInsertFromCreditCardsCommand:",
        "insertTimeShortcut:",
        "insertTableShortcut:",
        "insertImgShortcut:",
        "insertVideoShortcut:",
        "insertMarkmapShortcut:",
        "insertMermaidShortcut:",
        "insertPlantumlShortcut:",
        "insertFoldShortcut:",
        "insertTaskShortcut:",
    ]

    // MARK: - Computed Symbol Maps

    private static let symbolMap: [String: String] = {
        var map: [String: String] = [:]

        for mapping in iconMappings {
            for selector in mapping.selectors {
                map[selector] = mapping.symbol
            }
            for identifier in mapping.identifiers {
                map[identifier] = mapping.symbol
            }
        }

        return map
    }()

    // MARK: - Public Interface

    @MainActor
    static func symbol(for selector: Selector) -> String? {
        let selectorString = NSStringFromSelector(selector)

        if let cached = symbolCache[selectorString] {
            return cached
        }

        let symbol = symbolMap[selectorString]
        symbolCache[selectorString] = symbol

        return symbol
    }

    @MainActor
    static func symbol(for item: NSMenuItem) -> String? {
        if let identifier = item.identifier {
            let identifierKey = "id:\(identifier.rawValue)"
            if let cached = symbolCache[identifierKey] {
                return cached
            }

            if let symbol = symbolMap[identifier.rawValue] {
                symbolCache[identifierKey] = symbol
                return symbol
            }
            symbolCache[identifierKey] = nil
        }

        if let action = item.action {
            return symbol(for: action)
        }

        return nil
    }

    @MainActor
    static func shouldSuppressWarning(for selector: Selector) -> Bool {
        let selectorString = NSStringFromSelector(selector)
        return suppressedSelectors.contains(selectorString)
    }
}
