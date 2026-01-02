<p align="center">
    <div align="center"><img src=https://gw.alipayobjects.com/zos/k/t0/43.png width=138  /></div>
    <h2 align="center">MiaoYan</h2>
    <div align="center">Lightweight Markdown note-taking app for macOS</div>

</p>

## Features

- **Fantastic**: Local-first, privacy-focused, syntax highlighting, PPT mode, LaTeX, Mermaid diagrams
- **Beautiful**: Minimalist design, three-column layout, dark mode, distraction-free
- **Fast**: Swift 6 native, better performance than Electron-based apps
- **Simple**: Lightweight, keyboard shortcuts, auto-formatting

## Getting Started

1. Download the latest package from <a href="https://github.com/tw93/MiaoYan/releases" target="_blank">GitHub Releases</a>. Requires macOS 11.5+. For installation issues, refer to [this guide](https://zhuanlan.zhihu.com/p/135948430)
2. Create a `MiaoYan` folder in iCloud or preferred location, then set it as default storage in Settings
3. Click the new folder icon in the upper left to create document categories
4. Customize the default font in Settings if needed

## Keyboard Shortcuts

#### Window Operations

- `command + 1` - Toggle folder sidebar
- `command + 2` - Toggle file list
- `command + 3` - Toggle preview mode
- `command + 4` - Toggle presentation mode
- `command + option + m` - Show/hide MiaoYan globally

#### Document Operations

- `command + n` - New document
- `command + r` - Rename document
- `command + d` - Duplicate document
- `command + o` - Open in separate window
- `command + delete` - Delete document
- `command + shift + n` - New folder
- `command + shift + l` - Auto-format
- `command + option + r` - Show in Finder
- `command + option + i` - Show document properties
- `command + option + p` - Launch PPT preview

Explore more shortcuts in the app.

## Helpful Tools

### Preview Table of Contents

- Switch to preview mode (`command + 3`) and hover over the slim handle near the top-right edge to reveal the table of contents panel.
- Notes with at least two headings generate the outline automatically—click any heading to jump to that section in the preview.
- Press `esc` or click outside the panel to close it; the handle fades out again when you stop using it.

### Tab Quick Input Templates

- Type a slash shortcut followed by `Tab` (for example `/table` + `Tab`) while editing to expand rich snippets instantly.
- The menu bar path `Format > Tab Quick Input` shows every template and can insert them for you.
- Built-in shortcuts: `/time`, `/table`, `/img`, `/video`, `/markmap`, `/mermaid`, `/plantuml`, `/fold`, `/task`.

## Markdown Workflow Tips

- Use `command + shift + l` after pasting plain text to clean up headings, lists, and spacing automatically.
- Press `return` inside a list or todo item to continue it; press `return` twice to break out and keep writing normally.
- Toggle todos from the keyboard via `Format > Todo` or click the checkbox directly in preview mode.
- For ready-made Markdown patterns, open **MiaoYan Markdown Syntax Guide** from the sidebar templates.

## Rich Content Templates

- Drop in a collapsible section with `/fold` + `Tab` to keep long notes tidy, or use `/task` for a ready-made project checklist.
- Diagram lovers can expand `/mermaid` or `/plantuml` to insert fenced code blocks that render automatically in preview.
- `/markmap` generates an interactive mind map—perfect for brainstorming before switching back to prose.
- Detailed syntax samples, including collapsible sections and diagram templates, live in **MiaoYan Markdown Syntax Guide**.

## MiaoYan PPT

1. New users get templates by default. Existing users can copy [this file](https://raw.githubusercontent.com/tw93/MiaoYan/master/Resources/Initial/%E5%A6%99%E8%A8%80%20PPT.md) to try it out
2. Press `command + option + p` to launch PPT preview, or right-click a document and select "MiaoYan PPT"
3. PPT mode works with documents containing `---` separators. Press Enter to preview outline, ESC to exit
4. Use HTML for custom effects. See [Reveal](https://revealjs.com/markdown/) docs for advanced usage

## Why MiaoYan

After trying many note apps (WizNote, Evernote, Ulysses, Quiver, MWeb, Bear, Typora), I couldn't find a Markdown tool that felt right, so I built MiaoYan.

As a front-end developer with some iOS experience, I wanted to explore Swift and macOS development while creating a tool I'd actually use.
