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
            } else if let action = item.action,
                !MenuIconRegistry.shouldSuppressWarning(for: action)
            {
                #if DEBUG
                    print("⚠️ MenuIcon: No icon found for selector '\(NSStringFromSelector(action))'")
                #endif
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

    private static let symbolsBySelector: [Selector: String] = {
        var map: [Selector: String] = [:]
        func register(_ symbol: String, _ selectors: Selector...) {
            selectors.forEach { map[$0] = symbol }
        }

        register(
            "info.circle",
            Selector(("showInfo:")),
            Selector(("showAboutWindow:"))
        )
        register("heart", Selector(("openCats:")))
        register("gearshape", Selector(("openPreferences:")))
        register(
            "rectangle.stack",
            Selector(("activeWindow:")),
            Selector(("openMainWindow:")),
            #selector(NSApplication.arrangeInFront(_:))
        )
        register(
            "eye.slash",
            #selector(NSApplication.hide(_:)),
            #selector(NSApplication.hideOtherApplications(_:))
        )
        register("eye", #selector(NSApplication.unhideAllApplications(_:)))
        register("trash", Selector(("emptyTrash:")), Selector(("deleteNote:")))
        register("power", Selector(("quiteApp:")))
        register("square.and.pencil", Selector(("fileMenuNewNote:")))
        register("externaldrive.badge.plus", Selector(("singleOpen:")))
        register("square.and.arrow.down", Selector(("importNote:")))
        register("magnifyingglass", Selector(("searchAndCreate:")))
        register("plus.square.on.square", Selector(("duplicate:")))
        register(
            "pencil",
            Selector(("renameMenu:")),
            Selector(("renameMenu:"))
        )
        register(
            "folder",
            Selector(("finderMenu:")),
            Selector(("revealInFinder:"))
        )
        register("square.and.arrow.up", Selector(("exportMenu:")))
        register("arrow.up.right.circle", Selector(("moveMenu:")))
        register("xmark.circle", #selector(NSWindow.performClose(_:)))
        register("line.3.horizontal.decrease.circle", Selector(("sortBy:")))
        register("arrow.up.and.down.circle", Selector(("sortDirectionBy:")))
        register("sidebar.left", Selector(("toggleSidebarPanel:")))
        register("list.bullet.rectangle", Selector(("toggleNoteList:")))
        register("rectangle.on.rectangle")
        register("arrow.up.left.and.arrow.down.right", #selector(NSWindow.toggleFullScreen(_:)))
        register("bold", Selector(("boldMenu:")))
        register("italic", Selector(("italicMenu:")))
        register("underline", Selector(("underlineMenu:")))
        register("text.badge.minus", Selector(("deletelineMenu:")))
        register(
            "link",
            Selector(("linkMenu:")),
            Selector(("copyURL:"))
        )
        register("checkmark.square", Selector(("todoMenu:")))
        register("arrow.left", Selector(("shiftLeft:")))
        register("arrow.right", Selector(("shiftRight:")))
        register("textformat")
        register("doc.on.doc", Selector(("noteCopy:")))
        register("text.magnifyingglass", Selector(("textFinder:")))
        register("arrow.down.right.and.arrow.up.left.rectangle", #selector(NSWindow.performMiniaturize(_:)))
        register("plus.magnifyingglass", #selector(NSWindow.performZoom(_:)))
        register("globe", Selector(("openMiaoYan:")))
        register("chevron.left.slash.chevron.right", Selector(("openGithub:")))
        register("paperplane", Selector(("openTelegram:")))
        register("bird", Selector(("openTwitter:")))
        register("doc.text.magnifyingglass", Selector(("openRelease:")))
        register("exclamationmark.bubble", Selector(("openIssue:")))
        register("sparkles")
        register("pin", Selector(("pinMenu:")))
        register("chevron.left.forwardslash.chevron.right", Selector(("exportHtml:")))
        register("photo", Selector(("exportImage:")))
        register("doc.richtext", Selector(("exportPdf:")))
        register("wand.and.stars", Selector(("exportMiaoYanPPT:")))
        register("folder.badge.plus", Selector(("addProject:")))
        register("trash.slash", Selector(("deleteMenu:")))
        register("xmark.circle.fill", Selector(("closeAll:")))
        register("plus.circle", #selector(NSObjectController.add(_:)))
        register("mic", Selector(("startDictation:")))
        register("character.book.closed", #selector(NSApplication.orderFrontCharacterPalette(_:)))

        return map
    }()

    private static let symbolsByName: [String: String] = [
        "checkForUpdates:": "arrow.triangle.2.circlepath",
        "undo:": "arrow.uturn.backward",
        "redo:": "arrow.uturn.forward",
        "cut:": "scissors",
        "copy:": "doc.on.doc",
        "paste:": "clipboard",
        "pasteAsPlainText:": "clipboard.fill",
        "selectAll:": "square.grid.2x2",
        "centerSelectionInVisibleArea:": "scope",
        "togglePreview:": "eye",
        "togglePresentation:": "rectangle.on.rectangle",
        "formatText:": "textformat",
        "toggleMagicPPT:": "sparkles",
    ]

    private static let symbolsByIdentifier: [String: String] = [
        "viewMenu.sortBy": "line.3.horizontal.decrease.circle",
        "noteMenu.export": "square.and.arrow.up",
        "noteMenu.move": "arrow.up.right.circle",
    ]

    private static let suppressedSelectors: Set<String> = [
        "submenuAction:",  // Generic submenu actions don't need icons
        "_handleInsertFromContactsCommand:",  // System insertion commands
        "_handleInsertFromPasswordsCommand:",
        "_handleInsertFromCreditCardsCommand:",
    ]

    @MainActor
    static func symbol(for selector: Selector) -> String? {
        let selectorString = NSStringFromSelector(selector)

        if let cached = symbolCache[selectorString] {
            return cached
        }

        let symbol: String? = symbolsBySelector[selector] ?? symbolsByName[selectorString]
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

            if let symbol = symbolsByIdentifier[identifier.rawValue] {
                symbolCache[identifierKey] = symbol
                return symbol
            }
            symbolCache[identifierKey] = nil
        }

        if let action = item.action {
            let selectorKey = "sel:\(NSStringFromSelector(action))"
            if let cached = symbolCache[selectorKey] {
                return cached
            }

            let symbol = symbolsBySelector[action] ?? symbolsByName[NSStringFromSelector(action)]
            symbolCache[selectorKey] = symbol
            return symbol
        }

        return nil
    }

    @MainActor
    static func shouldSuppressWarning(for selector: Selector) -> Bool {
        let selectorString = NSStringFromSelector(selector)
        return suppressedSelectors.contains(selectorString)
    }
}
