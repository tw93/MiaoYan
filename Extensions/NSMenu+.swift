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

    private static let iconMappings: [(symbol: String, selectors: [String], identifiers: [String])] = [
        ("info.circle", ["showInfo:", "showAboutWindow:"], []),
        ("heart", ["openCats:"], []),
        ("gearshape", ["openPreferences:"], []),
        ("rectangle.stack", ["activeWindow:", "openMainWindow:", "arrangeInFront:"], []),
        ("eye.slash", ["hide:", "hideOtherApplications:"], []),
        ("eye", ["unhideAllApplications:", "togglePreview:"], []),
        ("trash", ["emptyTrash:", "deleteNote:"], []),
        ("power", ["quiteApp:"], []),
        ("square.and.pencil", ["fileMenuNewNote:"], []),
        ("externaldrive.badge.plus", ["singleOpen:"], []),
        ("square.and.arrow.down", ["importNote:"], []),
        ("magnifyingglass", ["searchAndCreate:"], []),
        ("plus.square.on.square", ["duplicate:"], []),
        ("pencil", ["renameMenu:"], []),
        ("folder", ["finderMenu:", "revealInFinder:"], []),
        ("square.and.arrow.up", ["exportMenu:"], ["noteMenu.export"]),
        ("arrow.up.right.circle", ["moveMenu:"], ["noteMenu.move"]),
        ("xmark.circle", ["performClose:"], []),
        ("line.3.horizontal.decrease.circle", ["sortBy:"], ["viewMenu.sortBy"]),
        ("arrow.up.and.down.circle", ["sortDirectionBy:"], []),
        ("sidebar.left", ["toggleSidebarPanel:"], []),
        ("list.bullet.rectangle", ["toggleNoteList:"], []),
        ("rectangle.on.rectangle", ["togglePresentation:"], []),
        ("arrow.up.left.and.arrow.down.right", ["toggleFullScreen:"], []),
        ("bold", ["boldMenu:"], []),
        ("italic", ["italicMenu:"], []),
        ("underline", ["underlineMenu:"], []),
        ("text.badge.minus", ["deletelineMenu:"], []),
        ("link", ["linkMenu:", "copyURL:"], []),
        ("checkmark.square", ["todoMenu:"], []),
        ("arrow.left", ["shiftLeft:"], []),
        ("arrow.right", ["shiftRight:"], []),
        ("textformat", ["formatText:"], []),
        ("doc.on.doc", ["noteCopy:", "copy:"], []),
        ("text.magnifyingglass", ["textFinder:"], []),
        ("arrow.down.right.and.arrow.up.left.rectangle", ["performMiniaturize:"], []),
        ("plus.magnifyingglass", ["performZoom:"], []),
        ("globe", ["openMiaoYan:"], []),
        ("chevron.left.slash.chevron.right", ["openGithub:"], []),
        ("paperplane", ["openTelegram:"], []),
        ("bird", ["openTwitter:"], []),
        ("doc.text.magnifyingglass", ["openRelease:"], []),
        ("exclamationmark.bubble", ["openIssue:"], []),
        ("sparkles", ["toggleMagicPPT:"], []),
        ("pin", ["pinMenu:"], []),
        ("chevron.left.forwardslash.chevron.right", ["exportHtml:"], []),
        ("photo", ["exportImage:"], []),
        ("doc.richtext", ["exportPdf:"], []),
        ("wand.and.stars", ["exportMiaoYanPPT:"], []),
        ("folder.badge.plus", ["addProject:"], []),
        ("trash.slash", ["deleteMenu:"], []),
        ("xmark.circle.fill", ["closeAll:"], []),
        ("plus.circle", ["add:"], []),
        ("mic", ["startDictation:"], []),
        ("character.book.closed", ["orderFrontCharacterPalette:"], []),
        ("arrow.triangle.2.circlepath", ["checkForUpdates:"], []),
        ("arrow.uturn.backward", ["undo:"], []),
        ("arrow.uturn.forward", ["redo:"], []),
        ("scissors", ["cut:"], []),
        ("clipboard", ["paste:"], []),
        ("clipboard.fill", ["pasteAsPlainText:"], []),
        ("square.grid.2x2", ["selectAll:"], []),
        ("scope", ["centerSelectionInVisibleArea:"], []),
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
