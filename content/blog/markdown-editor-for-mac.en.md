A good Markdown editor for Mac is one that keeps your notes as ordinary `.md` files in a folder you control, shows you the result without friction, and handles the extras you actually write, such as math and diagrams. Everything else is taste. The real choice is between three styles: a WYSIWYG editor like Typora, a plugin-driven vault like Obsidian, or a source-plus-preview editor like MiaoYan or a code editor with a preview pane. This guide covers the criteria first, then the options, then where MiaoYan fits and where it does not.

## What to look for

### Plain files or a proprietary store

Markdown is a plain text format, so the safest setup is one where each note is a `.md` file in a normal folder. You can open the folder in Finder, back it up with Time Machine, search it with `grep`, and move to another editor on any afternoon. Obsidian describes its notes as "plain text Markdown files" stored locally. Bear's site, on the other hand, does not say whether notes sit in a database or as files, so check how its export works before you commit. If you ever want to switch apps, check this first, because it decides how painful switching is.

### WYSIWYG or source plus preview

In a WYSIWYG editor the formatting renders as you type, and you rarely see the raw syntax. Typora's site calls this a "real live preview" with no separate preview window or mode switcher. In a source-plus-preview editor you type the raw Markdown on one side and see the rendered page on the other. The first reads better while writing. The second shows you exactly what is in the file, which matters when you paste tables, fix a broken list, or debug why a heading did not render. The trade-off is covered in more detail in [Typora alternatives on Mac](/blog/typora-alternative-mac/).

### Math and diagrams

If you write technical notes, check three things: whether `$...$` math renders, whether Mermaid fenced blocks render, and whether either needs a network. Typora lists MathJax support and Mermaid, flowchart.js and sequence diagrams. VS Code renders math with KaTeX and Mermaid in its built-in preview, according to its Markdown documentation. MiaoYan renders KaTeX and Mermaid from files bundled in the app. Details are in [LaTeX math in Markdown](/blog/latex-math-in-markdown/) and [Mermaid diagrams in Markdown](/blog/mermaid-diagrams-in-markdown/).

### Sync

Most Markdown editors on Mac do not run a sync service. They read a folder, and your cloud-drive client moves the files. That works with iCloud Drive, Dropbox, Nutstore or anything else that syncs a folder, and it means a sync problem is a cloud-drive problem you can inspect. Some apps sell their own sync instead, such as Obsidian Sync with end-to-end encryption and a year of version history, or Bear's iCloud sync, which Bear lists as a Pro feature. Decide whether you want an app-owned service or a folder.

### Performance

MiaoYan is a native Swift app and does not ship an Electron runtime, according to its own site. Speed is hard to compare across editors from published numbers, so test it yourself: open your largest note in each candidate and see whether typing stays smooth.

## The main options

| Option | Style | Notes stored as | Worth knowing |
|---|---|---|---|
| Typora | WYSIWYG, one pane | Files | Math via MathJax, Mermaid, many export formats, runs on macOS, Windows and Linux |
| Obsidian | Markdown notes with plugins | Local `.md` in a vault | Thousands of plugins, optional paid Sync, homepage says "Free without limits" (check its license page for commercial use) |
| iA Writer | Plain text with a Preview switch | Plain text files | Focus Mode, no math or diagrams mentioned on its site |
| Bear | Styled Markdown editor | Not stated on its site | Mac, iPhone and iPad, iCloud sync in Pro |
| VS Code | Code editor with side-by-side preview | Files | Built-in preview, KaTeX math and Mermaid, no writing-focused chrome |
| MiaoYan | Source editor plus synced preview | Files in a folder you choose | Native Swift, KaTeX, Mermaid, PlantUML, Markmap, PPT mode |

All vendor claims in the table are from each product's own site, checked on 2026-10-18. Prices change, so none are listed here.

Pick Typora if you want the cleanest WYSIWYG writing surface and work across macOS, Windows and Linux. Pick Obsidian if you want a linked knowledge base and are happy to maintain plugins. Pick iA Writer if you want plain prose with almost no chrome and do not need math. Pick VS Code if you already live in it and your notes sit next to code.

## Where MiaoYan fits

MiaoYan is a native Mac app for local Markdown notes. It uses three columns: folders, a note list, and the editor. You set a storage folder in Preferences (`⌘,`), and the notes are `.md`, `.markdown` or `.txt` files inside it. Split mode puts the editor and preview side by side, toggled with `⌘\`, or you can set Editor Mode to Split Mode in Preferences. The project README explains why there is no WYSIWYG: native WYSIWYG in Swift is heavy and fragile, and split mode keeps you writing against the Markdown source.

Built-in features include KaTeX math, Mermaid, PlantUML and Markmap diagrams, `[[wikilinks]]` with backlinks, per-note version history, auto-format (`⌘⇧L`), HTML, PDF and image export, a `miao` command-line tool, and a presentation mode that turns a note with `---` separators into slides (see [Markdown to slides](/blog/markdown-to-slides/)). There is no plugin system, so you cannot add features that are not built in.

One App Store purchase covers Mac, iPhone and iPad, and all three open the same notes folder, such as one in iCloud Drive. The Mac app is MIT-licensed and its source is public on GitHub. Get it from the [App Store page](https://apps.apple.com/app/id6759252269) or read the code at [github.com/tw93/MiaoYan](https://github.com/tw93/MiaoYan).

## Where MiaoYan does not fit

- You want WYSIWYG. MiaoYan does not offer it, whereas Typora does.
- You want a plugin ecosystem, graph view customization or Kanban boards. That is Obsidian's territory.
- You need Windows or Linux. MiaoYan is Mac, iPhone and iPad only, and requires macOS 12 or later on the Mac.
- You need word-processor export such as DOCX. Typora lists DOCX and EPUB, whereas MiaoYan's export menu offers HTML, PDF and image, plus a PPT PDF for decks.
- You need offline PlantUML. MiaoYan sends PlantUML text to the public plantuml.com server to render it, covered in the diagrams post.

## How to check an editor before committing

1. Create three notes: one with a table and task list, one with a `$$` equation and a Mermaid block, and one with an image.
2. Open the folder in Finder and confirm each note is a readable `.md` file and that the image is a normal file next to it.
3. Open the same folder in a second editor. If the notes look right there too, you are not locked in.
4. Paste in your largest existing note and type in the middle of it.

If all four pass, the editor is a safe default for your notes, whichever one you chose. The syntax is the part that carries over between tools, which is why a short reference like the [Markdown cheat sheet](/blog/markdown-cheat-sheet/) is worth keeping nearby.

## FAQ

### Is Markdown the same in every editor?

The core syntax is. Headings, emphasis, lists, links and code follow CommonMark. Tables, task lists and strikethrough come from GitHub Flavored Markdown, while footnotes, math and diagrams depend on the editor, so check those before relying on them.

### Can I use MiaoYan alongside Obsidian or Typora?

Yes, because all of them can read a folder of `.md` files. Keep one editor writing at a time to avoid sync conflicts, and test image paths on a copy first.

### Does native mean better?

Not by itself. A native app avoids bundling a browser engine, but the better question is whether it renders the syntax you write and keeps your files open. MiaoYan has no plugin system, so what it ships is what you get.
