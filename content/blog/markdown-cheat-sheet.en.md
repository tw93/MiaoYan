Most of what you write in Markdown fits on one screen: headings with `#`, emphasis with `*` and `**`, lists, links, images, code fences, blockquotes and tables. The main source of confusion is that Markdown is not a single standard. CommonMark defines the core, GitHub Flavored Markdown (GFM) adds tables, task lists, strikethrough and autolinks, and everything else, such as footnotes, math and diagrams, depends on the app. This sheet shows the syntax with examples, marks which part is core and which is an extension, and notes what MiaoYan renders.

## Core syntax (CommonMark)

### Headings

```markdown
# Heading 1
## Heading 2
### Heading 3
```

Put a space after the `#` characters. There are six levels, from `#` to `######`. Keep one `#` heading per note and use the lower levels for sections, because outline and table-of-contents views are built from them. In MiaoYan, a note with at least two headings gets an automatic table of contents, shown with `⌘5`.

### Emphasis and inline code

```markdown
*italic* or _italic_
**bold** or __bold__
***bold italic***
`inline code`
```

Use backticks for anything a reader would type or read from a screen, such as a command, a file name or a setting.

### Lists

```markdown
- Unordered item
- Another item
  - Nested item, indented two spaces

1. First
2. Second
3. Third
```

Indent nested items so they line up under the text of the parent item. In MiaoYan, pressing `return` inside a list continues it, and pressing `return` twice leaves the list.

### Links and images

```markdown
[Link text](https://example.com)
![Alt text](/i/photo.png)
```

The image syntax is the link syntax with a leading `!`. MiaoYan keeps local attachments in an `i/` folder next to your notes and writes them as `/i/<filename>`, so the note still works if the folder moves.

### Code blocks

````markdown
```python
print("hello")
```
````

The word after the opening fence names the language and drives syntax highlighting. The same fence mechanism is how diagram tools pick up their input, with `mermaid`, `plantuml` and `markmap` as the language word.

A fence is three or more backticks or three or more tildes (`~~~`), and the closing fence must use the same character and be at least as long as the opening one. That rule is how you show a fence inside a code block, as in the example above: wrap the inner three-backtick fence in an outer four-backtick one. A block of lines indented by four spaces is also a code block, but it has no language word and is easy to trigger by accident inside a list, so fences are the safer habit.

In MiaoYan's preview, highlight.js colors each fenced block. With no language word it guesses the language from the content, so add the word when the colors look wrong; common short names such as `js`, `py` and `sh` work. Long lines wrap inside the block instead of scrolling sideways, so a long command stays readable without a scroll bar.

To put a backtick inside inline code, wrap the span in two backticks with spaces inside: ``` `` a ` b `` ```. A fence inside a list item has to line up with the item's text, or it ends the list.

### Blockquotes and rules

```markdown
> A quoted line.
> Another line in the same quote.

---
```

A line of three hyphens makes a horizontal rule. In MiaoYan's presentation mode, the same `---` on its own line starts a new slide, which is why decks avoid rules inside a slide. See [Markdown to slides](/blog/markdown-to-slides/).

### Paragraphs and line breaks

```markdown
This line ends with a backslash\
so this one starts on a new line.

A blank line starts a new paragraph.
```

In CommonMark, a single newline inside a paragraph is a soft break that renders as a space, and a blank line starts a new paragraph. To force a line break without starting a paragraph, end the line with a backslash or with two spaces; both turn into a `<br>`. Apps differ here. MiaoYan has a Line Break setting in its Editor settings with two options: MiaoYan (the default, each newline starts a new line in the preview) or Github (a new line in the preview needs a blank line). In Github mode MiaoYan follows the CommonMark rule exactly, so a single newline becomes a space and the backslash or two spaces still give you a break. The preview and HTML or PDF export both follow the setting. If your text looks joined together or spread out in one app and not another, this is usually why.

Two pitfalls follow from that. A note written in MiaoYan's default mode can look right in MiaoYan and run together on GitHub or in other editors, which use the soft-break rule, so switch to Github mode while writing anything you will publish elsewhere and the preview will match. And trailing spaces are invisible and often stripped by editors that trim whitespace on save, which is why the backslash is the more reliable way to break a line in a file you share.

### Escaping

Put a backslash before a character Markdown would otherwise read as syntax, for example `\*not italic\*` or `\# not a heading`. Inside code spans and fences, nothing needs escaping.

## GFM extensions

### Tables

```markdown
| Item | Price | In stock |
|:-----|------:|:--------:|
| Tea  | 2.50  | yes      |
| Jam  | 0.50  | no       |
```

The colons in the divider row set alignment: left, right, center. Column widths in the source do not need to line up, though aligning them keeps the file readable. In MiaoYan, `/table` followed by `Tab` inserts a template, and Edit > Format (`⌘⇧L`) tidies pasted plain text.

A table needs a header row and a divider row with the same number of cells. If the divider row has more or fewer cells than the header, the whole block stays plain text. Body rows are more forgiving: a short row gets empty cells and extra cells are dropped. The pipes at the start and end of each row are optional.

Each cell holds one line of inline Markdown, so emphasis, links, inline code and images work, while lists, code blocks and line breaks do not. Use `<br>` for a line break inside a cell, which MiaoYan renders because its preview allows raw HTML. A literal `|` inside a cell has to be written as `\|`, even inside backticks, or it splits the cell. Merged cells are not part of the syntax; write an HTML `<table>` with `colspan` if you need them.

In MiaoYan's preview, a table spans the width of the note, and a table too wide to fit, for example one with a long formula or URL in a cell, scrolls sideways in its own box instead of widening the page. PDF and image exports cannot scroll, so there the table is fitted to the page width, as [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/) shows.

### Task lists

```markdown
- [x] Draft the post
- [ ] Add screenshots
  - [ ] Crop the second one
```

A task item is a list item whose text starts with `[ ]` for an open task or `[x]` for a done one, followed by a space. The space inside the brackets matters: `[]` stays literal text, and so does `-[ ]` with no space after the hyphen. Task items nest like any other list item.

In MiaoYan, you can click the checkbox in preview mode to toggle it, and the change is written back to the file as `- [x]` or `- [ ]`, so the note stays plain Markdown. To find the line to change, MiaoYan counts the `- [ ]` and `- [x]` items in the note. Write task items with a hyphen and a lowercase `x`: items written with `*`, `+`, a number or a capital `X` still show as checkboxes, but clicking one can flip a different line.

### Strikethrough

```markdown
~~removed text~~
```

### Autolinks

GFM turns bare URLs into links. MiaoYan's parser turns on tables, footnotes, strikethrough and task lists, and autolinking is not in that list, so write `<https://example.com>` or a normal link if the URL matters.

## Beyond GFM

### Footnotes

```markdown
The claim needs a source.[^1]

[^1]: Here is the source.
```

Footnotes are not part of the GFM specification, so treat them as an app feature. MiaoYan enables footnote parsing.

### Math and diagrams

`$E = mc^2$` for inline math, `$$ ... $$` for a block, and fenced `mermaid` blocks for diagrams. Both are renderer features, covered in [LaTeX math in Markdown](/blog/latex-math-in-markdown/) and [Mermaid diagrams in Markdown](/blog/mermaid-diagrams-in-markdown/).

### Callouts

```markdown
> [!NOTE]
> Useful context.
```

MiaoYan recognizes `NOTE`, `TIP`, `IMPORTANT`, `WARNING` and `CAUTION`. Other apps show these as plain blockquotes.

### Raw HTML and collapsible sections

```html
<details>
<summary>More</summary>

Markdown works inside after a blank line.

</details>
```

MiaoYan renders raw HTML in the preview, and `/fold` followed by `Tab` inserts this block.

### Wikilinks and frontmatter

`[[Project plan]]` links to another note by its exact title, without the `.md` suffix, and MiaoYan builds backlinks from them. A block at the very start of the note between two `---` lines is treated as frontmatter and hidden in the rendered preview.

### Subscript and superscript

MiaoYan's bundled syntax guide shows `H~2~O` and `26^th^`. MiaoYan does not render that syntax, so do not rely on it. Use `<sub>` and `<sup>` HTML if you need either.

## How the pieces fit

Markdown source passes through a parser that produces HTML. CommonMark specifies how the core syntax maps to HTML, and GFM adds extra rules on top. MiaoYan's preview uses a Swift port of cmark-gfm with four extensions attached: table, footnotes, strikethrough and tasklist. The HTML then loads into a web view, where KaTeX turns math into typeset output and the diagram libraries turn fenced blocks into SVG. That split explains most surprises. If it fails in the parser, the syntax is wrong or unsupported. If it fails later, it is a renderer problem such as a math error or a diagram typo.

## Common mistakes

- No space after `#` or `-`, so the line stays plain text.
- A table without the divider row, which stays plain text.
- A nested list indented with tabs in one place and spaces in another.
- Unbalanced code fences, which swallow the rest of the note. Count the backtick lines.
- A single `---` directly under a line of text, which some parsers read as a heading underline.

To check a note, open it in preview and look for literal syntax characters left on the page. They mark the lines the parser did not understand.

## FAQ

### What is the difference between CommonMark and GFM?

CommonMark is a precise specification of the core syntax. GFM is a superset that adds tables, task lists, strikethrough, autolinks and a rule about disallowed raw HTML.

### Do I need two spaces at the end of a line?

Only if your app follows strict CommonMark and you want a line break without a new paragraph. MiaoYan's default Line Break setting breaks at every newline.

### Can I paste a cheat sheet into MiaoYan to test it?

Yes. The app ships a MiaoYan Markdown Syntax Guide in its Examples folder that covers each element above, and the full app is on the [App Store](https://apps.apple.com/app/id6759252269) and [GitHub](https://github.com/tw93/MiaoYan).
