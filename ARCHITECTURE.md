# MiaoYan Architecture

> This document describes the architecture as it actually exists, not as it
> ought to be. Aspirational refactors are tracked in
> `~/.claude/plans/9-think-magical-globe.md`, not here. When code drifts, the
> code wins and this document is wrong; please update it.

## Top-Level Map

```
.
├── Business/        # Models and core domain logic (Storage, Note, Project, WikilinkIndex, ...)
├── Controllers/     # AppKit view controllers and window controllers
├── Views/           # AppKit UI components (NSView / NSOutlineView / NSTableView subclasses)
├── Helpers/         # Utilities and services (highlighting, formatting, theming, diagnostics)
├── Extensions/      # Swift extensions on Foundation / AppKit types
├── Resources/       # Bundled assets, including DownView.bundle (HTML/CSS/JS for preview)
├── MiaoYanMobile/   # iOS SwiftUI target (App/Services/Views/Resources)
├── MiaoYanTests/    # Unit tests for pure-logic surfaces
└── scripts/         # Local build, App Store, release helpers, target wiring (Ruby + bash)
```

## Process Model

A single macOS application process owns:

- One `NSApplication` (subclass-free; `AppDelegate` is the delegate).
- One `MainWindowController` (`Controllers/MainWindowController.swift`),
  which loads `Resources/Localization/Base.lproj/Main.storyboard`.
- One `ViewController` (`Controllers/ViewController.swift` + four `+` extensions),
  the host for the sidebar / notes list / editor / preview.
- One `WKWebView` instance per editor pane that loads
  `Resources/DownView.bundle/index.html` for live preview.

The iOS target (`MiaoYanMobile/`) is a separate executable; it shares the
`Business/` models via the same compile pool but has its own SwiftUI app entry
point (`MiaoYanMobileApp.swift`).

## Singleton & Facade Inventory

Process-wide singletons (each "global" surface that holds state):

| Singleton                          | Where                                      | Role                                   |
| ---------------------------------- | ------------------------------------------ | -------------------------------------- |
| `Storage.sharedInstance()`         | `Business/Storage.swift`                   | Filesystem-backed note + project model |
| `WikilinkIndex.shared`             | `Business/WikilinkIndex.swift`             | `[[note]]` outgoing/incoming index     |
| `CloudSyncManager.shared`          | `Business/CloudSyncManager.swift`          | iCloud Drive coordination              |
| `NoteVersionManager.shared`        | `Business/NoteVersionManager.swift`        | Per-note version history               |
| `UserDataService.instance`         | `Helpers/UserDataService.swift`            | Cached user-level appearance state     |
| `AppContext.shared`                | `Business/Types.swift`                     | Holds storage + sessionState + view ref |
| `EditorStateManager.shared`        | `Helpers/UserDefaultsManagement.swift`     | Editor mode toggles                    |
| `ShortcutTemplateManager.shared`   | `Helpers/ShortcutTemplateManager.swift`    | Markdown insert templates              |
| `ToastManager.shared`              | `Views/Toast.swift`                        | Non-modal status messages              |

These are NOT going to be replaced wholesale; Storage is genuinely a single
filesystem mapping and that semantic is correct. New code should access them
through the facade:

```swift
// Preferred (new code)
let storage = AppEnvironment.current.storage

// Tolerated (existing code) but a SwiftLint warning under
// `no_direct_singleton_in_new_code`
let storage = Storage.sharedInstance()
```

`Business/AppEnvironment.swift` is a read-only facade and a substitution
point for tests via `AppEnvironment.withOverride(...)`.

## Storyboard Anchors (Do Not Move Without Reading This First)

The following bindings live in `Main.storyboard` and depend on selectors /
identifiers existing on the named class. Renaming or moving any of these
breaks the UI at runtime without a compile-time error:

- `ViewController.swift` is the storyboard's `viewController` scene; **all**
  `@IBOutlet` and `@IBAction` declarations must stay on this class.
- `SidebarProjectView` is loaded as the storyboard's outline view subclass;
  its `awakeFromNib` is the construction entry point, not `init`.
- `NotesTableView` cell views have `NSUserInterfaceItemIdentifier("NoteCellView")`
  registered in the storyboard and dequeued at `Views/NotesTableView.swift:526`.
- `SidebarProjectView` cell views use identifier `"DataCell"` similarly
  (`Views/SidebarProjectView.swift:639`).
- The First Responder action chain is selector-based. `@IBAction` methods on
  `ViewController+Action.swift` must keep their exact ObjC selectors.

If you need to split `ViewController`, leave outlets and actions on the host
class and forward to coordinator objects from the action body. See
`~/.claude/plans/9-think-magical-globe.md` Phase 3.

## Editing Pipeline (Hot Path)

```
keystroke
  → EditTextView (NSTextView subclass; CustomTextStorage)
  → NSTextStorage.processEditing
  → NotesTextProcessor.checkPerformanceLevel
     ├─ short text:    full Markdown highlight via MarkdownRuleHighlighter
     └─ long/large:    simplified highlight (skips code block regex)
  → ViewController.textDidChange (URL drift tripwire fires here)
     ├─ debounced disk save:  Note.save(content:)
     └─ debounced preview:    MPreviewView.updateContent (adaptive 0.3/0.6/1.0s)
```

Performance ceilings live in `Helpers/NotesTextProcessor.swift`:

- > 1 MB total length OR > 64 KB in a single paragraph: simplified highlight, no code highlight.
- > 5000 lines: simplified, no code highlight.
- > 2000 lines: simplified, code highlight still on.

## Preview Pipeline

```
Note.content (NSMutableAttributedString)
  → swift-cmark-gfm → HTML string
  → MPreviewView (WKWebView)
     ↳ loads Resources/DownView.bundle/index.html one-shot
     ↳ postReadyCallbacks fire when WKWebView didFinish navigation lands
     ↳ subsequent edits use incremental DOM mutation, not full reload
```

Bundled JS used by the preview is vendored under
`Resources/DownView.bundle/js/` and indexed in
`Resources/DownView.bundle/js/vendor/MANIFEST.json` (versions + SHA-256).

## Filesystem Conventions

- Note files: user-selected storage path (security-scoped bookmark in
  `UserDefaultsManagement.storageBookmark`).
- Note attachments: `i/` (inline images) and `files/` (other attachments)
  subdirectories at the note's level.
- Trash: a `.Trash` directory inside the storage root, plus a fallback to the
  OS-level trash via `FileManager.default.trashItem(...)`.
- Symlinked directories: supported but indexed in a way that avoids recursion
  loops (`Business/Storage.swift::checkSub`).
- Version history: `Library/Application Support/MiaoYan/Versions/<note-id>/`
  managed by `NoteVersionManager`.
- Diagnostics log: `~/Library/Logs/MiaoYan/diagnostics.log` (ring buffer,
  50 lines, JSON per line). See `Helpers/Diagnostics.swift`.

## iOS Target Boundary

`MiaoYanMobile/` compiles into the same `MiaoYan.xcodeproj` and shares the
`Business/` source pool. SwiftUI lives only inside `MiaoYanMobile/`; AppKit
lives only outside. There is no shared UI layer. The iOS target reads notes
through `MiaoYanMobile/Services/FileReader.swift`, which is a parallel
implementation to (not a thin wrapper over) the macOS storage flow.

## Release & Update Path

- Mac App Store builds: signed and uploaded by the maintainer; `Sparkle` is
  excluded via `#if !APPSTORE`.
- Direct downloads: `bash scripts/build.sh` produces a zipped `.app`. The
  Sparkle `appcast.xml` is updated by `scripts/release-ci/update_appcast.sh`
  (needs the Sparkle EdDSA private key).
- Version triplet (must stay aligned): git tag `Vx.y.z`, `MARKETING_VERSION`,
  `CURRENT_PROJECT_VERSION`. CI rejects mismatches when a tag is pushed.

## Current Wiring Notes

- `Helpers/Diagnostics.swift` is in the app target, and
  `AppDelegate.trackError` records release diagnostics through it.
- `Business/AppEnvironment.swift` is in the app target and is the preferred
  facade for new singleton access.
- `Helpers/UIDelay.swift` is in the app target for semantic async delay names.
- `MiaoYanTests/` is wired into `MiaoYan.xcodeproj`, and CI runs the macOS unit
  test step together with the Debug app build.

## See Also

- `AGENTS.md` — agent-facing repo guide (commands, hot files, current risk areas)
- `CLAUDE.md` — project-level overrides for Claude Code
- `.claude/rules/swift.md` — project-level Swift conventions
- `~/.claude/CLAUDE.md` — global rules (writing style, commit policy, git safety)
