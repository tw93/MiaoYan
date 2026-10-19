A Markdown table is a header row, a divider row of hyphens, and one row per line, with cells separated by pipes. Colons in the divider row set the alignment. A literal pipe inside a cell is written `\|`, and a line break inside a cell is `<br>`. The syntax is a GitHub Flavored Markdown extension, not core CommonMark, and it has hard limits: one line per cell and no merged cells. When you need more, fall back to an HTML `<table>`.

## The basic shape

```markdown
| Tool    | Format | Price |
| :------ | :----: | ----: |
| Pandoc  | CLI    | free  |
| MiaoYan | app    | free  |
```

The header row and the divider row must have the same number of cells, otherwise the whole block stays plain text. The GFM spec states that rule, along with the others in this post. The divider cells contain only hyphens and optional colons: a colon on the left (`:---`) aligns left, on both sides (`:---:`) centers, and on the right (`---:`) aligns right. With no colons the column uses the renderer's default.

The columns in the source do not need to line up; the padding in the example is for people reading the raw file. The leading and trailing pipes on each row are optional, though the spec recommends them for clarity and for cases where parsing would otherwise be ambiguous. Body rows are forgiving: a row with fewer cells than the header gets empty cells, and extra cells are ignored. The table ends at the first blank line or at the start of another block, such as a quote.

## What goes inside a cell

A cell holds inline Markdown only. Emphasis, links, images, inline code and strikethrough work. Lists, headings and fenced code blocks do not, because the spec says block-level elements cannot be inserted in a table.

**Pipes.** The pipe is the column separator, so a literal one must be escaped as `\|`. The spec's own example shows that this also applies inside inline code and bold text: `` `\|` `` renders as a code span containing a plain pipe. Writing `a|b` in a cell without the backslash starts a new column.

**Line breaks.** A row is one source line, so there is no way to press Return inside a cell. Use `<br>`:

```markdown
| Step | Notes                       |
| ---- | --------------------------- |
| 1    | Open the file<br>Press save |
```

That works where the renderer allows inline HTML. MiaoYan's preview does. A backslash at the end of the line cannot help here, because the cell has no following source line to continue onto. If the viewer escapes HTML, you will see `<br>` as text, which is the cue to restructure the data instead.

**Inline code and math.** Inline code is fine apart from the pipe rule. For math, MiaoYan's renderer masks each character inside `$...$`, `$$...$$`, `\(...\)` and `\[...\]` before the table parser runs, so `$n$` in a cell is safe, and the source also shows that a `|` inside a math span is masked too. That is this renderer's behavior and should not be assumed elsewhere; for a notation like absolute value, `\vert` sidesteps the problem in any KaTeX renderer. See [LaTeX math in Markdown](/blog/latex-math-in-markdown/) for the delimiters.

## What a table cannot do

There are no merged cells, no row spans, no multi-paragraph cells, no lists in cells and no column widths. The syntax describes a plain grid. If you need a merged header or a list inside a cell, write the table in HTML:

```markdown
<table>
  <tr><th colspan="2">Export</th></tr>
  <tr><td>PDF</td><td>A4 page</td></tr>
</table>
```

Raw HTML passes through in MiaoYan's preview, so this renders. Not every renderer allows raw HTML, so test where the note will be read. The trade-off is that an HTML table is harder to edit than a pipe table and does not diff cleanly.

Often the better answer is to change the data. A cell that needs a list usually wants to be a list under a heading, and a table that needs merged cells is often two tables.

## Wide tables in MiaoYan

On screen, MiaoYan wraps every table in a scrolling container. A table is at least as wide as the column, and when a cell contains something that cannot shrink, such as a long URL or a formula, the table grows past the column and scrolls sideways in its own box instead of widening the page. Text wraps at spaces, and a long unbroken token keeps its width and makes the table scroll instead of being cut in the middle of a word.

PDF and image export cannot scroll, so the export styles undo that. The scroll wrapper stops clipping and the table is set to the page width with fixed layout, which makes columns equal in width. The consequence is that a table with one very long column and several short ones gets squeezed into equal columns on paper. If an exported table looks cramped, shorten the longest cells, drop a column or split the table. The export steps are in [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/). The print styles also ask that a table not be split across pages.

## Getting a table from a spreadsheet

MiaoYan has no CSV or TSV import and does not turn tab-separated text into a pipe table on paste. What it does convert is HTML: when you paste rich text that contains a `<table>`, from a web page for example, it writes a pipe table. The first row becomes the header when there are no `<th>` cells, pipes in cells are escaped as `\|`, and line breaks inside a cell become spaces. Pasting from an app that puts only plain tab-separated text on the clipboard gives you tabs, not pipes.

For CSV or TSV files, Pandoc lists `csv` and `tsv` among its input formats and `gfm` among its output formats, so a conversion looks like `pandoc -f csv -t gfm data.csv`. The result is a pipe table you can paste into the note, though long cells make the source ragged. [Markdown notes from the terminal](/blog/markdown-notes-from-terminal/) covers the `miao` command-line tool for creating notes.

## FAQ

### Why is my Markdown table not rendering?

Usually the divider row has a different number of cells than the header row. Fix the count so both rows match.

### Can I have a multi-line cell?

Not in pipe syntax. Use `<br>` for a line break, or an HTML table for paragraphs and lists.

### Can I merge cells?

No. Use an HTML table with `colspan` or `rowspan`.

### How do I put a pipe character in a cell?

Write `\|`. It also works inside inline code.
