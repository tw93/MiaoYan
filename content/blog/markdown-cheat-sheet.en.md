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

### Blockquotes and rules

```markdown
> A quoted line.
> Another line in the same quote.

---
```

A line of three hyphens makes a horizontal rule. In MiaoYan's presentation mode, the same `---` on its own line starts a new slide, which is why decks avoid rules inside a slide. See [Markdown to slides](/blog/markdown-to-slides/).

### Paragraphs and line breaks

In CommonMark, a single newline inside a paragraph is a soft break that renders as a space, and a blank line starts a new paragraph. To force a line break, end a line with two spaces or a backslash. Apps differ here. MiaoYan has a Line Break setting with two options: MiaoYan (the default, each newline starts a new line in the preview) or Github (a new line in the preview needs a blank line). If your text looks joined together or spread out in one app and not another, this is usually why.

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

### Task lists

```markdown
- [x] Draft the post
- [ ] Add screenshots
```

In MiaoYan, you can click the checkbox in preview mode to toggle it.

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
