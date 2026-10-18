If you are looking for a Typora alternative on Mac, the first question is what you want to change. If you want to keep writing in one WYSIWYG pane, look at other WYSIWYG-style editors. If you want to see the Markdown source with a live preview next to it, a split-view editor such as MiaoYan is the closest swap, and your notes carry over because they are plain `.md` files. The main trade-off is that you give up typing into rendered text in exchange for always seeing exactly what is in the file.

## Why people look for an alternative

Typora's own page describes what it does well: a "real live preview" with no preview window or mode switcher, MathJax math, Mermaid, flowchart.js and sequence diagrams, custom CSS themes, many export formats, and support for macOS, Windows and Linux. People still move for reasons that have nothing to do with quality.

- They want to see the source. In a WYSIWYG editor the raw syntax is hidden, which makes it harder to repair a broken table, a stray list indent or a mis-escaped character.
- They want the same notes on iPhone and iPad. Typora's page lists desktop platforms only. MiaoYan has iPhone and iPad apps in the same App Store purchase as the Mac app, and all three open one notes folder.
- They want a Mac-only, native feel and a three-column layout of folders, notes and editor.
- They want a built-in way to present a note as slides. MiaoYan has one, covered in [Markdown to slides](/blog/markdown-to-slides/).
- They want open source for the Mac app. MiaoYan's Mac app is MIT-licensed and public on GitHub. For Typora's license and price, check its own site.

If none of those apply to you, staying with Typora is reasonable.

## WYSIWYG versus split preview

In Typora you type and the formatting appears in place. The pane is also the document, so there is one place to look. In MiaoYan you write Markdown in the editor and read the rendered note beside it, with scroll sync between the two. Press `⌘\` to toggle split mode, or open Preferences (`⌘,`), and in General set Editor Mode to Split Mode. `⌘3` switches to a full preview.

The MiaoYan README explains the choice directly: native WYSIWYG in Swift is heavy and fragile, so the app keeps pure Markdown editing and gives you synchronized visual feedback instead. That is a product decision, not a limitation to be fixed later, so decide whether it suits how you write.

| | Typora | MiaoYan |
|---|---|---|
| Editing surface | Rendered text in place | Markdown source, preview beside it |
| Math | MathJax, with most extensions per its page | KaTeX 0.16.0, bundled |
| Diagrams | Mermaid, flowchart.js, sequence | Mermaid, PlantUML (public server), Markmap |
| Platforms | macOS, Windows, Linux | Mac, iPhone, iPad |
| Export | PDF, DOCX, EPUB, LaTeX and more per its page | HTML, PDF, image, PPT PDF |
| Extensions | Custom CSS themes | No plugin system |

The Typora column comes from typora.io and the MiaoYan column from the app's source and README, both checked on 2026-10-18. Details on math engines are in [LaTeX math in Markdown](/blog/latex-math-in-markdown/), and diagram behavior is in [Mermaid diagrams in Markdown](/blog/mermaid-diagrams-in-markdown/).

## What carries over

Both apps work with files, so most of the move is pointing a new app at your folder.

1. **Notes.** MiaoYan reads `.md`, `.markdown` and `.txt` files in the folder you choose. Open Preferences (`⌘,`) and set the storage path to your existing Typora folder, or a copy of it.
2. **Images.** MiaoYan resolves relative image paths from the note's folder, so `images/photo.png` next to the note works. Its own convention is an `i/` folder and links written `/i/photo.png`, which it uses when you paste or drop images. Both forms can live in one folder.
3. **Math.** `$...$` and `$$...$$` carry over. KaTeX supports a subset of what MathJax does, so open any note with unusual macros and check it.
4. **Diagrams.** Fenced `mermaid` blocks carry over. Typora's flowchart.js blocks are not Mermaid and will not render in MiaoYan.
5. **Themes.** Typora CSS themes do not carry over. MiaoYan has its own appearance settings: system, light or dark, fonts, preview width and code background.

Do the move on a copy first. Open three notes that use tables, images and math, and compare them side by side with Typora before pointing at the real folder. Because both apps read the same folder, you can also keep using Typora for any note that needs it, though avoid editing the same file in both at once.

## How it actually works

Typora keeps a rendered view as the editing surface and writes Markdown to disk when you save. MiaoYan keeps the Markdown as the editing surface and renders a second view from it. Its renderer is cmark-gfm with table, footnote, strikethrough and task-list extensions. After parsing, the HTML goes into a web view, where bundled KaTeX and the diagram libraries run. The file on disk is the text in the editor, so what you see in the editor is exactly what is saved.

Different renderers can disagree on edge cases, so test your own notes. The core rules are in the [Markdown cheat sheet](/blog/markdown-cheat-sheet/). One MiaoYan default to know: its Line Break setting defaults to MiaoYan, so each newline starts a new line in the preview. Switch it to Github if your notes depend on a blank line to break.

## What goes wrong

- **Line breaks look different.** Check MiaoYan's Line Break setting as above.
- **Images are missing.** The relative path no longer matches the note's folder, usually because the notes moved without the image folder.
- **A formula fails.** It uses a MathJax-only feature. Rewrite it with KaTeX-supported syntax.
- **You miss typing into rendered text.** That is the real cost of this swap. Try split mode for a week before deciding, and keep Typora until you are sure.
- **You need DOCX or EPUB output.** MiaoYan does not offer them.

## Where to get it

MiaoYan is on the [App Store](https://apps.apple.com/app/id6759252269), and one purchase covers the Mac, iPhone and iPad apps. The Mac app's source is at [github.com/tw93/MiaoYan](https://github.com/tw93/MiaoYan). Broader comparison across editors is in [choosing a Markdown editor for Mac](/blog/markdown-editor-for-mac/).

## FAQ

### Will my Typora notes open in MiaoYan?

Yes, if they are `.md`, `.markdown` or `.txt` files in a folder. Point MiaoYan's storage path at the folder or a copy.

### Does MiaoYan have a WYSIWYG mode?

No. It has editor-only, split and preview-only views.

### Is MiaoYan better than Typora?

It depends on whether you want the source visible. The two answer different preferences, so run both on a copy of your notes.
