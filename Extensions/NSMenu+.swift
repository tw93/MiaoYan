import Cocoa

// MARK: - Menu Icon Management

@available(macOS 11.0, *)
extension NSMenu {
    /// Applies SF Symbol icons to menu items based on their action selectors
    @MainActor
    func applyMenuIcons() {
        for item in items {
            if let action = item.action {
                if let symbolName = MenuIconRegistry.symbol(for: action),
                    let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: item.title)
                {
                    image.isTemplate = true
                    item.image = image
                } else {
                    #if DEBUG
                        print("⚠️ MenuIcon: No icon found for selector '\(NSStringFromSelector(action))'")
                    #endif
                }
            }

            if let submenu = item.submenu {
                submenu.applyMenuIcons()
            }
        }
    }
}

// MARK: - Icon Registry

/// Manages SF Symbol icon mappings for menu actions
@available(macOS 11.0, *)
enum MenuIconRegistry {
    /// Cache for symbol lookup results to improve performance
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
        register("eye", #selector(NSApplication.unhideAllApplications(_:)), Selector(("togglePreview:")))
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
        register("arrowshape.turn.up.right", Selector(("moveMenu:")))
        register("xmark.circle", #selector(NSWindow.performClose(_:)))
        register("arrow.up.arrow.down", Selector(("sortBy:")))
        register("arrow.up.and.down.circle", Selector(("sortDirectionBy:")))
        register("sidebar.left", Selector(("toggleSidebarPanel:")))
        register("list.bullet.rectangle", Selector(("toggleNoteList:")))
        register("rectangle.on.rectangle", Selector(("togglePresentation:")))
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
        register("textformat", Selector(("formatText:")))
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
        register("sparkles", Selector(("toggleMagicPPT:")))
        register("pin", Selector(("pinMenu:")))
        register("chevron.left.forwardslash.chevron.right", Selector(("exportHtml:")))
        register("photo", Selector(("exportImage:")))
        register("doc.richtext", Selector(("exportPdf:")))
        register("wand.and.stars", Selector(("exportMiaoYanPPT:")))
        register("folder.badge.plus", Selector(("addProject:")))
        register("trash.slash", Selector(("deleteMenu:")))

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
    ]

    /// Returns the SF Symbol name for a given selector, with caching for performance
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
}
