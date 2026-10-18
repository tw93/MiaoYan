To turn Markdown into slides, put `---` on its own line between slides and open the note in a tool that treats that line as a page break. In MiaoYan, press `Command + Option + P`; the note must contain at least one `---` line. The same convention is used by reveal.js, Marp and Slidev, so a deck written for one is mostly portable to the others. What differs is theming, export formats, and setup requirements.

## The basic format

```markdown
# Quarterly review

Notes for the team

---

## What shipped

- Editor rewrite
- Faster preview

---

## What is next

1. Sync
2. Export
```

Each block between separators is one slide. The first block becomes the opening slide, so a top-level heading and a subtitle make a title slide. Keep the `---` alone on its line with nothing else on it. MiaoYan's bundled PPT guide and agent skill both say a horizontal rule inside a slide is not possible, because the same characters are the slide boundary.

If you press the shortcut on a note with no `---`, MiaoYan tells you that no delimiter was found and the slideshow cannot start.

## Running it in MiaoYan

1. Open or create a note and add `---` lines between slides.
2. Press `Command + Option + P`.
3. Press Enter to preview the slide outline, and ESC to exit, as the bundled PPT note describes.
4. To export a file, use the Export menu and choose MiaoYan PPT PDF.

New installs include a MiaoYan PPT note with working examples. Existing users can create a note with that name and paste a deck into it.

### Configure with a comment

Put an HTML comment of `key: value` lines at the very start of the note, after any YAML frontmatter:

```markdown
<!--
transition: slide
slideNumber: c/t
controls: true
progress: true
-->
```

The keys map straight onto reveal.js configuration options. Values are read as booleans, numbers, `null`, bracketed lists or strings, and dotted keys such as `highlight.lineNumbers` set nested options. MiaoYan removes the comment before rendering. Its defaults are the slide transition, visible controls and progress bar, URL hash navigation, slide numbers off and slides that are not vertically centered.

### Per-slide extras

````markdown
<!-- .slide: data-background="#F8CB9E" -->
## Custom background

- First point <!-- .element: class="fragment" data-fragment-index="1" -->
- Second point <!-- .element: class="fragment" data-fragment-index="2" -->

```swift [1|2-3]
let a = 1
let b = 2
```
````

The `.slide:` comment sets slide attributes such as a background color, gradient or image. The `.element:` comment on a line adds attributes to that element, and `class="fragment"` reveals it on the next click. A language fence followed by `[1|2-3]` highlights lines step by step. These are reveal.js features, documented at revealjs.com/markdown.

Math works inside slides with `$...$` and `$$...$$`, and Mermaid, PlantUML and Markmap blocks render in presentation mode too. For two columns, raw HTML with `display: flex` works; leave a blank line inside each `div` so the Markdown still parses.

Local images written as `/i/photo.png` are rewritten to a path the slides can load, so the same image works in a normal note and in the deck.

## How it actually works

MiaoYan's PPT mode is a reveal.js page. The note text is placed inside a markdown section, and reveal's Markdown plugin splits it at the separator, whose default pattern is a `---` line surrounded by newlines. Vertical slides, which use a second separator, are off by default in reveal.js and the PPT page does not enable them, so you get a flat horizontal sequence. Before the text reaches the plugin, MiaoYan protects math, escapes backslashes and dollar signs, and rewrites image paths. The theme switches between reveal's white and night styles to match MiaoYan's light or dark appearance.

Because it is reveal.js, speaker notes also follow reveal's convention: a line starting with `Note:` begins notes for that slide. Try the speaker view once before you present with it.

## Structure tips that work in any tool

- One idea per slide. If a slide needs scrolling, split it.
- Use headings as slide titles, `##` for ordinary slides and `#` for section openers.
- Keep bullets to four or five, and turn long lists into fragments only if the order matters.
- Put the conclusion first. A deck is easier to follow when slide two states the answer.
- Use images with alt text, and keep them in one folder so paths survive a move.
- Preview the deck at the size you will present at; code and tables shrink quickly.

## Other ways to make slides

| Tool | How you write | Output | Needs |
|---|---|---|---|
| MiaoYan PPT mode | A note with `---` separators | Slideshow, PDF | MiaoYan on Mac |
| reveal.js | Markdown or HTML | Browser slides, PDF through print | A browser; you set up the page |
| Marp | Markdown with `---`, based on CommonMark | HTML, PDF, PowerPoint | Marp for VS Code or Marp CLI; PDF and PowerPoint export use Chrome or Chromium |
| Slidev | Markdown with `---` and per-slide YAML frontmatter | See sli.dev for formats | Install steps are in its Getting Started guide |

Facts in the table are from marp.app, revealjs.com and sli.dev, checked on 2026-10-18. Pick Marp when you need a `.pptx` file for someone else. Pick Slidev when you want layouts and backgrounds set per slide in YAML and are comfortable setting up its toolchain. Pick reveal.js directly when you want full control over the page. Pick MiaoYan's mode when the deck is a by-product of notes you already keep and you want to present with one shortcut.

## What goes wrong

- **The shortcut only shows a message.** There is no `---` line in the note, so MiaoYan reports that no delimiter was found.
- **The first slide is missing.** When a note opens with a `---` line, everything up to the next `---` line is hidden as frontmatter, so start the deck with its title, not with a separator.
- **A horizontal rule breaks the slide.** Replace it with a heading or spacing.
- **Images are missing.** Use `/i/<file>` in the note or an `https://` address, not a `file://` path.
- **Need a PowerPoint file.** MiaoYan exports a PPT PDF, not `.pptx`.

Related: [Markdown cheat sheet](/blog/markdown-cheat-sheet/), [Mermaid diagrams in Markdown](/blog/mermaid-diagrams-in-markdown/), and the app itself on the [App Store](https://apps.apple.com/app/id6759252269) or at [github.com/tw93/MiaoYan](https://github.com/tw93/MiaoYan).

## FAQ

### Can I export the deck as PowerPoint?

Not from MiaoYan, which exports PDF from PPT mode. Marp lists PowerPoint output.

### Do I need to know reveal.js?

Not for basic decks. Knowing its attribute comments helps for backgrounds and step-by-step reveals.

### Can I use the same file elsewhere?

The `---` separators carry over to Marp and Slidev. The `<!-- .slide: -->` comments are reveal.js-specific.
