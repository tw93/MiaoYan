Markdown has no table-of-contents syntax. You get one in one of three ways: write a nested list of anchor links by hand, put a tool-specific marker such as `[TOC]` where the tool supports it, or run a generator that writes the list into the file for you. Which one is right depends on where the note will be read, because heading anchors and `[TOC]` markers are decided by the renderer, not by Markdown itself.

## What a table of contents is in Markdown

A table of contents is an ordinary nested list whose items are links to headings in the same document. The links point at heading ids, written as `#id`. CommonMark does not say how a heading becomes an id, so every tool has its own rule, and that single fact explains most of the ways a hand-written table of contents breaks.

```markdown
## Contents

- [Install](#install)
  - [On Mac](#on-mac)
  - [From source](#from-source)
- [Usage](#usage)
```

Indent child items to nest them. The list is plain Markdown and renders anywhere; whether the links jump depends on the anchors.

## How heading anchors are generated

GitHub documents its rules in the basic writing and formatting syntax page: letters are converted to lower case, spaces are replaced by hyphens, any other whitespace or punctuation is removed, and a duplicate heading gets a hyphen and an auto-incrementing integer appended. So `## Install on Mac` is `#install-on-mac`, `## What's new?` is `#whats-new`, and a second `## Install on Mac` later in the same file is `#install-on-mac-1`. To see the anchor GitHub made, hover over a heading and click the link icon that appears, then read the address bar.

Other tools differ. Python-Markdown's `toc` extension joins duplicates with an underscore (`header`, `header_1`, `header_2`), and its slug function is configurable. Because of this, a table of contents copied from a GitHub README into another site can silently stop working on duplicate headings or punctuation. For the longer treatment of anchors, custom `<a id>` targets and non-ASCII headings, see [Markdown links and anchors](/blog/markdown-links-and-anchors/).

## The [TOC] marker and where it works

Several tools let you write a marker line and replace it with a generated list. None of this is part of CommonMark or GFM, and GitHub's syntax documentation does not list any such marker.

- **Python-Markdown** (the engine behind MkDocs) has the `toc` extension. The marker defaults to `[TOC]`, is replaced with a nested list of the headings, and `toc_depth` sets which levels are included.
- **Typora** documents `[toc]` followed by Return, which creates a table of contents section that updates as the document changes.
- **markdown-it-table-of-contents** is a plugin for the markdown-it library. Its default marker is `[[toc]]`, matched at the start of a line, and it includes levels 1 and 2 by default. Its README warns that the plugin does not add ids to headings, so without an anchor plugin the links in the list go nowhere.

The practical rule is that a marker is a promise from one toolchain. If the note is only ever read in that toolchain, the marker is the least work. If the file travels, to GitHub or to a different app, the marker shows up as literal text.

## Generating the list instead of typing it

A generator writes the nested list of links for you, so the list is plain Markdown in the file and survives any renderer, as long as the anchors match the target site.

### doctoc

doctoc is a Node command-line tool. Install it and run it on a file or on a whole directory:

```bash
npm install -g doctoc
doctoc README.md
doctoc .
```

By default it inserts the list at the top of the file, after any front matter, wrapped in marker comments (`<!-- START doctoc ... -->` and `<!-- END doctoc ... -->`). Later runs find those comments and update the list in place, and you can move the block where you want it. Useful options from its README: `--maxlevel 3` limits depth, `--notitle` drops the generated title, `--github` or `--gitlab` selects the anchor style (GitHub is the default), and `--dryrun` writes nothing and exits with code 1 if a file is out of date, which suits CI. A file with `<!-- DOCTOC SKIP -->` at the top is skipped, and a heading with `<!-- DOCTOC EXCLUDE -->` on the line above is left out.

### Markdown All in One for VS Code

In VS Code, install the extension named Markdown All in One, open the Command Palette and run `Markdown All in One: Create Table of Contents`. The `markdown.extension.toc.levels` setting (default `1..6`) controls which heading levels appear, and `markdown.extension.toc.updateOnSave` (default `true`) refreshes the list whenever you save. If the extension mistakes a list of yours for a table of contents, put `<!-- no toc -->` above it. The same extension has `Markdown All in One: Add/Update section numbers` if you want numbered headings.

### Pandoc

Pandoc puts the table of contents in the converted output, not in the Markdown source:

```bash
pandoc notes.md -s --toc --toc-depth=2 -o notes.html
```

The manual says `--toc` has no effect unless `-s` (standalone) is used, and that it has no effect on `man`, `docbook4`, `docbook5` or `jats` output. The default depth is 3. For `docx`, `odt`, `rst`, `latex` and a few other formats it inserts an instruction for that format to build the contents instead of an HTML list. This route suits documents you are converting, not a README you want to read as Markdown.

## GitHub's own outline

For files that GitHub renders, you do not need a table of contents at all. GitHub's documentation states that it generates one automatically when a file has two or more headings, and you open it with the Outline menu icon in the file header. A hand-written table of contents in a README is then only worth keeping when people read the raw file or a copy on another site.

## MiaoYan's table of contents

MiaoYan shows a table of contents in the preview, not in the Markdown file, and it needs no marker. The menu item is View, Toggle TOC (切换目录 in the Chinese interface), with the shortcut `Cmd+5`.

What the panel does, from the V4.9.0 source:

- It lists headings of levels 1 to 3 in a floating panel on the right edge of the preview. A narrow strip on the edge shows it when you hover; `Cmd+5` opens it pinned, and a pin button in the panel keeps it open.
- It appears only when the note has at least two headings of level 1 to 3, and when the preview is narrower than 600 pixels the edge strip is hidden and an unpinned panel closes.
- The menu item works in preview and split mode, and is disabled in MiaoYan PPT mode.
- The first time you see a preview, a small red "TOC" badge appears on the edge strip, once.
- Click an entry and the preview scrolls to that heading. The active heading is highlighted as you scroll.
- PDF export hides the panel and instead writes headings h1 to h3 into the PDF as bookmarks, which a PDF reader shows in its sidebar.

Two things to know. MiaoYan does not turn `[TOC]` or `[[toc]]` into a list, so those lines render as plain text. And its heading ids are the visible heading text, not GitHub's lowercase-and-hyphen form, so a hand-written `[Install](#install-on-mac)` does not jump in the preview. The panel is unaffected, because it builds its own links, but a manual list needs the `#Install%20on%20Mac` form or a custom `<a id>` target; the details are in [Markdown links and anchors](/blog/markdown-links-and-anchors/). For PDF export and how those bookmarks land on pages, see [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/), and for the syntax around headings and lists, the [Markdown cheat sheet](/blog/markdown-cheat-sheet/).

## What goes wrong

- **Links do nothing.** The anchor in the list does not match the id the renderer generated. Check by hovering the heading on GitHub, or by comparing against the tool's slug rule. Duplicate headings and punctuation are the usual cause.
- **The `[TOC]` line appears as text.** The renderer does not support that marker. Use a generated list or the viewer's own outline.
- **The list is stale.** A hand-written list does not follow edits. Use doctoc or the VS Code command, or turn on `updateOnSave`.

## FAQ

### How do I add a table of contents in Markdown?

Write a nested list of `[text](#anchor)` links by hand, or generate it with doctoc or the VS Code extension Markdown All in One. A `[TOC]` marker works only in tools that support it.

### Does GitHub support [TOC]?

GitHub's syntax documentation does not list it. GitHub instead shows an Outline menu in the file header when a file has two or more headings.

### Why does my table of contents link not jump?

The anchor does not match the heading id your renderer generates. On GitHub it is lowercase with hyphens and punctuation removed; other tools differ.

### Can I get a table of contents in an exported PDF?

MiaoYan's PDF export does not print the TOC panel, but it adds h1 to h3 as PDF bookmarks. For a printed contents page, Pandoc with `-s --toc` can produce one in its own output formats.
