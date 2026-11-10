<p align="center">
    <div align="center"><img src="https://miaoyan.app/assets/notes/miaoyan.png" width="138" /></div>
    <h2 align="center">MiaoYan</h2>
    <div align="center">Lightweight Markdown note-taking app for macOS</div>

</p>

## Features

- **Fantastic**: Local-first, privacy-focused, syntax highlighting, PPT mode, LaTeX, Mermaid diagrams
- **Beautiful**: Minimalist design, three-column layout, dark mode, distraction-free
- **Fast**: Native, quick to launch and to switch between notes
- **Simple**: Lightweight, keyboard shortcuts, auto-formatting

## Getting Started

1. Every note is a plain Markdown file; see or change where they are kept in Settings
2. Press `⇧⌘N` to create a folder and sort your notes
3. Customize the default font in Settings if needed
4. To keep writing away from the Mac, the [iPhone and iPad apps](https://apps.apple.com/app/miaoyan/id6759252269) open the same iCloud Drive folder

## Keyboard Shortcuts

#### Window Operations

- `⌘1` - Toggle folder sidebar
- `⌘2` - Toggle file list
- `⌘3` - Toggle preview mode
- `⌘4` - Toggle presentation mode
- `⌘5` - Toggle table of contents
- `⌘\` - Toggle split view
- `⌥⌘0` - Show the main window
- `⌥⌘M` - Show/hide MiaoYan globally

#### Document Operations

- `⌘N` - New document
- `⌘R` - Rename document
- `⌘D` - Duplicate document
- `⌘O` - Open a file or folder in Single Mode
- `⌘⌫` - Move document to Trash
- `⇧⌘N` - New folder
- `⇧⌘L` - Auto-format
- `⌥⌘R` - Show in Finder
- `⌥⌘I` - Show document properties
- `⌥⌘P` - Launch PPT preview

Explore more shortcuts in the app.

## Helpful Tools

### Preview Table of Contents

- Press `⌘5`, or switch to preview mode (`⌘3`) and hover over the slim handle near the top-right edge, to reveal the table of contents panel.
- Notes with at least two headings generate the outline automatically. Click any heading to jump to that section in the preview.
- Press `Esc` or click outside the panel to close it; the handle fades out again when you stop using it.

### Tab Quick Input Templates

- Type a slash shortcut followed by `Tab` (for example `/table` + `Tab`) while editing to expand rich snippets instantly.
- The menu bar path `Format > Tab Quick Input` shows every template and can insert them for you.
- Built-in shortcuts: `/time`, `/table`, `/img`, `/video`, `/markmap`, `/mermaid`, `/plantuml`, `/fold`, `/task`.

## Markdown Workflow Tips

- Use `⇧⌘L` after pasting plain text to clean up headings, lists, and spacing automatically.
- Press `return` inside a list or todo item to continue it; press `return` twice to break out and keep writing normally.
- Toggle todos from the keyboard via `Format > Todo` or click the checkbox directly in preview mode.
- For ready-made Markdown patterns, open **MiaoYan Markdown Syntax Guide** from the Examples folder in the sidebar.

## Rich Content Templates

- Drop in a collapsible section with `/fold` + `Tab` to keep long notes tidy, or use `/task` for a ready-made project checklist.
- Diagram lovers can expand `/mermaid` or `/plantuml` to insert fenced code blocks that render automatically in preview.
- `/markmap` generates an interactive mind map, perfect for brainstorming before switching back to prose.
- Detailed syntax samples, including collapsible sections and diagram templates, live in **MiaoYan Markdown Syntax Guide**.

## MiaoYan PPT

1. "MiaoYan PPT" in the Examples folder is a ready-made deck, open it to try
2. Press `⌥⌘P` to launch PPT preview, or right-click a document and select "MiaoYan PPT"
3. PPT mode works with documents containing `---` separators. Press Return to preview the outline, `Esc` to exit
4. Use HTML for custom effects. See [Reveal](https://revealjs.com/markdown/) docs for advanced usage

## Why MiaoYan

After trying many note apps (WizNote, Evernote, Ulysses, Quiver, MWeb, Bear, Typora), I couldn't find a Markdown tool that felt right, so I built MiaoYan.

As a front-end developer with some iOS experience, I wanted to explore Swift and macOS development while creating a tool I'd actually use.
