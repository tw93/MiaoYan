# MiaoYan - Claude Development Guide

## Project Overview

MiaoYan (妙言) is a lightweight macOS Markdown editor built with Swift 5 + AppKit. Features a three-panel layout: sidebar + file list + editor.

## 🎯 Core Principles

- **Incremental Improvements** > Major Refactoring
- **Understand First** > Implement Immediately  
- **Pragmatism** > Dogmatism
- **Clear Intent** > Clever Code

## Claude Code Eight Honors and Eight Shames

- **Shame** in guessing APIs, **Honor** in careful research
- **Shame** in vague execution, **Honor** in seeking confirmation  
- **Shame** in assuming business logic, **Honor** in human verification
- **Shame** in creating interfaces, **Honor** in reusing existing ones
- **Shame** in skipping validation, **Honor** in proactive testing
- **Shame** in breaking architecture, **Honor** in following specifications
- **Shame** in pretending to understand, **Honor** in honest ignorance
- **Shame** in blind modification, **Honor** in careful refactoring

## Development Workflow

1. **Analysis**: Use Grep/Read to analyze code and understand existing patterns
2. **Planning**: Break down tasks into 3-5 steps using TodoWrite
3. **Implementation**: Small iterative changes, modify one file at a time
4. **Verification**: Ensure code compiles and functions work correctly

## ⛔ Absolute Rules

- **NEVER commit changes unless explicitly asked by user**
- Never commit non-compiling code
- Stop after 3 consecutive failures - reassess the approach
- Follow existing code patterns and conventions
- Keep every commit in a working state

## Project Structure

```text
Controllers/        # View Controllers & Window Controllers
Views/             # UI Components (Custom Views, UI Elements)  
Business/          # Business Logic (Models, Data Structures)
Helpers/           # Utilities & Services (Managers, Processors)
Extensions/        # Swift Extensions
AppDelegate.swift  # Application entry point
Info.plist         # Application configuration

Resources/
├── Images.xcassets/# Image and Color Resources
├── Localization/   # All localization files (*.lproj)
├── DownView.bundle/# Web view resources
└── Initial/        # Initial data files
```

## Key Conventions

- Follow existing project conventions and use established utility classes
- Use `I18n.str()` for internationalization (NOT `NSLocalizedString`)
- Retrieve colors from `Images.xcassets`
- Minimal comments - only add English comments for complex logic that's hard to understand
- Use `// MARK:` for organizing code sections

## MCP Tools

- **CONTEXT7**: Primary tool for code analysis and context gathering
- **mcp__ide__getDiagnostics**: Check Swift compilation issues
- Use MCP tools to supplement (not replace) manual code analysis

## Development Commands

```bash
# Build project
xcodebuild -scheme MiaoYan -configuration Debug build

# Clean build
xcodebuild clean

# Run tests (if available)
xcodebuild test -scheme MiaoYan
```

## Split View (分栏预览) Architecture

### Key Components

- **EditorContentSplitView** (`Views/EditorScrollView.swift`): Main split container with three modes
  - `editorOnly`: Full editor view
  - `previewOnly`: Full preview view
  - `sideBySide`: Split view with draggable divider

- **MPreviewView** (`Views/MPreviewView.swift`): WKWebView-based markdown preview
  - `load(note:)`: Full reload with new HTML template
  - `updateContent(note:)`: Lightweight update via JavaScript (preserves scroll)

- **ViewController+Editor** (`Controllers/ViewController+Editor.swift`): Mode management
  - `enableSplitViewMode()`: Activate split view
  - `startSplitScrollSync()`: Bidirectional scroll synchronization

### JavaScript Renderers

All renderers in `Resources/DownView.bundle/` require re-initialization after HTML content updates:

- **KaTeX**: `renderMathInElement()` for formulas (`$$...$$`, `$...$`)
- **Mermaid**: `mermaid.init()` for diagrams
- **PlantUML**: `DiagramHandler.initializePlantUML()` for UML diagrams
- **Markmap**: `DiagramHandler.initializeMarkmap()` for mind maps

### Critical Pattern: Content Update Workflow

When updating preview content without full page reload:

1. Update HTML via JavaScript: `container.innerHTML = newHTML`
2. Re-initialize renderers: `renderMathInElement()` + `DiagramHandler.initializeAll()`
3. Re-setup observers: `setupScrollObserver()`

**Example** (from `MPreviewView.swift:318-346`):

```swift
container.innerHTML = `\(escapedHTML)`;
if (typeof renderMathInElement === 'function') {
    renderMathInElement(document.body, {...});
}
if (window.DiagramHandler) {
    DiagramHandler.initializeAll();
}
```

### Scroll Synchronization

- **Editor → Preview**: NSNotification observer on `NSView.boundsDidChangeNotification`
- **Preview → WebView**: JavaScript scroll event with debouncing (100ms)
- **Anti-loop**: `isProgrammaticSplitScroll` flag prevents feedback loops
- **Performance**: 60fps sync (~16ms reset delay)

---
*Pragmatism > Perfectionism • Working Simple Solutions > Complex Designs*
