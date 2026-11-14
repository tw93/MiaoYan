Writing Markdown on a Mac by keyboard uses two layers: the macOS text system gives every native text view the same movement and deletion keys, and the app adds its own shortcuts on top. Below are both, from Apple's "Mac keyboard shortcuts" page and from MiaoYan V4.9.0's menus and code. ⌘ is Command, ⇧ is Shift, ⌥ is Option and ⌃ is Control.

## macOS keys that work in any text field

MiaoYan's editor is a native text view, so these work there with no setting, as they do in Notes, Mail and TextEdit.

| Keys | What it does |
| --- | --- |
| ⌥ Left / Right Arrow | Move to the beginning of the previous word, or the end of the next word |
| ⌘ Left / Right Arrow | Move to the beginning or end of the current line |
| ⌘ Up / Down Arrow | Move to the beginning or end of the document |
| ⌥ Delete | Delete the word to the left of the insertion point |
| Fn Delete or ⌃ D | Delete the character to the right |
| ⌃ H | Delete the character to the left |
| ⌃ A / ⌃ E | Move to the beginning or end of the line or paragraph |
| ⌃ F / ⌃ B | Move one character forward or backward |
| ⌃ N / ⌃ P | Move down or up one line |
| ⌃ K | Cut from the insertion point to the end of the paragraph |
| ⌃ Y | Paste what ⌃ K cut |
| ⌃ T | Swap the characters on either side of the insertion point |
| ⇧ plus a movement key | Extend the selection by the same amount |
| ⌘ Z / ⇧⌘ Z | Undo and redo |

One trap is ⌃ K: Apple says it copies to a clipboard available only to the app it came from, so ⌘ V will not paste it and ⌃ Y will.

MiaoYan's editor passes on every combination with Option or Control, so it overrides none of these.

## MiaoYan: views

All of these are in the View menu except the last, which is in the Window menu.

| Keys | Menu item | Chinese menu |
| --- | --- | --- |
| ⌘ 1 | Hide/Show Sidebar | 隐藏/显示侧边栏 |
| ⌘ 2 | Hide/Show NoteList | 隐藏/显示笔记列表 |
| ⌘ 3 | Toggle Preview | 切换预览 |
| ⌘ 4 | Toggle Presentation | 切换演示 |
| ⌘ 5 | Toggle TOC | 切换目录 |
| ⌘ \ | Toggle Split View | 切换分栏 |
| ⌘ + | Zoom In | 放大字体 |
| ⌘ - | Zoom Out | 缩小字体 |
| ⌘ 0 | Actual Size | 实际大小 |
| ⌥⌘ T | Always On Top | 窗口置顶 |
| ⌃⌘ F | Enter Full Screen | 进入全屏幕 |
| ⌥⌘ 0 | Main Window | 主窗口 |

⌘ + is really ⇧⌘ =, and the code also accepts plain ⌘ =. The table of contents is built from headings, covered in [the cheat sheet](/blog/markdown-cheat-sheet/).

## MiaoYan: formatting

The Format menu wraps the selection, or inserts an empty pair with the cursor between the marks. These act on the editor, so they do nothing in preview mode.

| Keys | Menu item | Chinese menu | Writes |
| --- | --- | --- | --- |
| ⌘ B | Bold | 粗体 | `**text**` |
| ⌘ I | Italic | 斜体 | `*text*` |
| ⌘ U | Underline | 下划线 | `<u>text</u>` |
| ⇧⌘ X | Deleteline | 删除线 | `~~text~~` |
| ⌘ K | Link | 链接 | a link |
| ⌘ T | Todo | 待办 | `- [ ] `, or toggles `[ ]` and `[x]` |
| ⌘ E | Inline Code | 行内代码 | backticks |
| ⇧⌘ E | Code Block | 代码块 | a fenced block |
| ⌘ ] / ⌘ [ | Shift Right / Shift Left | 右移 / 左移 | indent or outdent |
| ⇧⌘ L | Format (Edit menu) | 文档排版 | tidies the whole note |

Bold, italic, underline and strikethrough always wrap and never toggle, so a second ⌘ B adds another layer; see [the bold and italic post](/blog/markdown-bold-italic-strikethrough/). Clean Typography has no shortcut, and neither do headings, quotes or lists, so you type `#`, `>` and `- ` yourself.

### Keys handled in the editor

These keys are in no menu; the app handles them in code.

| Keys | What it does |
| --- | --- |
| Tab / ⇧ Tab | Indent or outdent the line, or every selected line, by two spaces (three after a numbered item) |
| Return | Continue a list: bullets, numbers (next number) and tasks (unticked). On an empty marker it removes the marker |
| ⇧ Return | A plain new line, with no list continuation |
| ⌘ Delete | Delete to the start of the line while the editor is focused |
| ⌘ S | Flush the pending save and show a "Saved" toast |
| Esc | Close the search bar |

### Tab Quick Input

Type a slash and a name, then press Tab, to insert a template. Format > Tab Quick Input lists them.

| Type, then Tab | Inserts |
| --- | --- |
| `/table` | A three-column table template |
| `/task` | Two open tasks and one done |
| `/img`, `/video` | An `<img>` or `<video>` tag with the cursor in `src` |
| `/mermaid`, `/plantuml`, `/markmap` | A fenced block with a starter diagram |
| `/fold` | A `<details>` collapsible section |
| `/time` | The current time as `yyyy-MM-dd HH:mm:ss` |

The placeholder text inside these templates is Chinese in V4.9.0, so replace it. What each block renders is in [Mermaid diagrams in Markdown](/blog/mermaid-diagrams-in-markdown/).

## MiaoYan: notes and folders

| Keys | Menu item | Chinese menu |
| --- | --- | --- |
| ⌘ N | New | 新建 |
| ⌘ O | Single Mode | 单独模式 |
| ⌘ D | Duplicate | 制作副本 |
| ⌘ R | Rename | 重命名 |
| ⇧⌘ P | Pin Note | 置顶笔记 |
| ⌥⌘ R | Reveal in Finder | 在 Finder 中显示 |
| ⇧⌘ R | Reload Note | 重新加载 |
| ⌘ Delete | Move to Trash | 移到废纸篓 |
| ⌘ W | Close | 关闭 |
| ⇧⌘ N | New Folder | 新建文件夹 |
| ⇧ F6 | Rename Folder | 重命名文件夹 |
| ⌘ J | Open in Terminal | 在终端中打开 |
| ⌥⌘ M | Active Window | 全局唤起妙言 |
| ⌘ , | Settings… | 设置… |

⇧⌘ T also pins, through a key monitor in the code; the menu shows ⇧⌘ P. Active Window is a global key you can change in Settings. Open in Terminal opens the selected folder in your terminal, handy for [the `miao` command line](/blog/markdown-notes-from-terminal/).

## MiaoYan: search

| Keys | What it does |
| --- | --- |
| ⌘ / | Search: focus the note search field |
| ⌘ F | Find in the editor, or in the preview when the preview is showing |
| ⌥⌘ F | Find and Replace |
| ⌘ G / ⇧⌘ G | Find Next and Find Previous |
| ⌥⌘ J | Jump to Selection |

## MiaoYan: preview, presentation and export

| Keys | What it does |
| --- | --- |
| ⌥⌘ P | MiaoYan PPT, slides from `---` lines |
| ⌃⇧ H | Export HTML |
| ⌃⇧ I | Export Image |
| ⌃⇧ P | Export PDF |
| ⌥⌃⇧ P | Export MiaoYan PPT PDF |
| ⇧⌘ H | Version History |
| ⌥⌘ I | Show Info |
| ⌥⌘ U | Copy URL |

A note's right-click menu shows ⌃⇧ H, ⌃⇧ I and ⌃⇧ P under Export, and File > Export opens that submenu. ⌃⇧ H works anywhere in the main window; the other export keys need the note list focused and slide mode off. ⌥⌘ P, ⇧⌘ H, ⌥⌘ I and ⌥⌘ U are handled in code, not by File menu items. Slides are in [Markdown to slides](/blog/markdown-to-slides/), export formats in [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/).

## Change a shortcut

In System Settings, click Keyboard, then Keyboard Shortcuts, then App Shortcuts. Click Add, choose the app, type the menu title exactly as the app shows it (nested menus as `Format->Bold`), press the keys and click Done. Apple notes that a shortcut already used by another command will not work, and only existing menu commands can be remapped, so code-only keys such as Tab, Return or ⇧⌘ H cannot.

## FAQ

### What is the shortcut for bold in Markdown on a Mac?

In MiaoYan it is ⌘ B, which wraps the selection in `**`. Other editors may differ.
