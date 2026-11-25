## Copy with styles

Copy formatted puts the note on the clipboard with each element's style written onto the element itself, since documents, mail and CMS editors drop stylesheets and classes, so headings, quotes, lists, tables and code keep MiaoYan's look where you paste them. The quote bar becomes a left border, task boxes become ☐ and ☑, code keeps its indentation and line breaks, Mermaid diagrams become images, and formulas are copied as their `$...$` source for now.

## Writing in it

The shortcuts are MiaoYan's: `⌘B` bold, `⌘I` italic, `⌘K` link, `⌘E` inline code, `⇧⌘E` code block, and `⌘S` saves the Markdown as a file, with Ctrl in place of ⌘ on Windows. Return in a list or quote starts the next item, and Return on an empty one ends it. The two panes scroll together paragraph by paragraph, whichever one you scroll. Phone width lays the preview out at 375 pixels, the button at the end of the toolbar gives the editor the whole screen, and the word count follows MiaoYan's, one for each CJK character and one for each word of other text.

## How close it is to MiaoYan's preview

The preview uses the stylesheets of MiaoYan's own preview, and its code highlighting, math and Mermaid come from the same files the app ships, so fonts, spacing, tables and code blocks look as they do in a note. The difference is the parser: this page reads Markdown with markdown-it and the app with cmark-gfm. Both follow CommonMark plus GitHub's tables, strikethrough and task lists, so only rare edge cases come out differently.

## FAQ

### Is it free, and is my file uploaded?

It is free, with no account. A file you open is read in your browser and never sent to a server, and your last text stays in this browser for the next visit.

### What syntax does it support?

Headings, lists, quotes, tables, task lists, strikethrough, code blocks with highlighting, math with `$...$` and `$$...$$`, and diagrams in mermaid code blocks. The Mermaid syntax is in [Mermaid in Markdown](/blog/mermaid-diagrams-in-markdown/).

### Why does an image not show?

A web page cannot read files on your computer, so an image with a local path such as `images/a.png` does not show; images with an `https://` address do. Opened in MiaoYan, the same file shows its local images.
