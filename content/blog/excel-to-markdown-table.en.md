Copy cells in Excel, Numbers or Google Sheets and the clipboard holds tab-separated text, one row per line, so pasting into a Markdown file gives you tabs, not a table. To get a pipe table, convert the text. An online generator such as tablesgenerator.com is the fastest for a one-off, Pandoc (`pandoc -f csv -t gfm`) suits files you convert repeatedly, and a short `awk` filter handles a range you just copied. Afterwards check three things: merged cells, line breaks inside cells, and any `|` in the data.

## Why the paste is not a table

A spreadsheet is a grid, and a plain-text clipboard has no grid. A copied range becomes text with a tab between cells and a line break between rows, the same layout as a `.tsv` file. A [Markdown table](/blog/markdown-tables/) needs pipes between cells and a divider row of hyphens under the header, so the tabs stay in the file as invisible whitespace and the preview shows the numbers as a paragraph.

Some apps also put an HTML version of the range on the clipboard next to the plain text, and some editors read it. MiaoYan does, as described near the end. The practical test is to paste once and look: pipes mean the HTML path worked, tabs mean you need a converter.

## Option 1: an online generator

The Markdown table page on tablesgenerator.com says you can copy cells from Excel, Google Sheets or LibreOffice Calc, click the top-left cell of its grid and press Ctrl+V, and the grid grows to fit. It also imports a file through **File / Import CSV or Excel file**, which accepts `.csv` and `.xlsx` and lets you choose a sheet. The Markdown appears under the editor, and **Copy to clipboard** copies it.

The same page describes the options that change the result:

- Alignment is set per column in the **Column** menu's **Text align** submenu, and in the output each column takes the alignment of its cell in the first row. That becomes the colons in the divider row.
- A line break inside a cell becomes a space by default. Ticking **Line breaks as `<br>`** writes `<br>` instead.
- Markdown cannot merge cells. When the page imports HTML or Markdown, merged cells are split, and it points to its HTML table generator for the merged case.
- **Compact mode** leaves out the spaces that line up the columns.

For a confidential sheet, a local tool is the safer default.

## Option 2: Pandoc

Pandoc lists `csv` and `tsv` among its input formats and `gfm` among its output formats. The runs below used Pandoc 3.13.

```bash
pandoc -f csv -t gfm data.csv
pandoc -f tsv -t gfm data.tsv
```

For a TSV with a header and two data rows the output was:

```markdown
| Name  | Qty |
|-------|-----|
| Apple | 3   |
| Pear  | 12  |
```

Export the sheet as CSV in UTF-8 so Chinese and accented text survives. To convert what is on the clipboard instead of a file, `pbpaste | pandoc -f tsv -t gfm | pbcopy` works on a Mac, because `pbpaste` and `pbcopy` read and write the clipboard.

Three behaviours showed up.

**Pipes are escaped.** A cell containing `a|b` came out as `a\|b`, so the table keeps its shape. Escaping in general is covered in [Markdown escape characters](/blog/markdown-escape-characters/).

**A multi-line cell stops Pandoc writing a pipe table.** With one cell containing a line break, the `gfm` writer produced a full HTML `<table>` with `<br />` instead of pipes. That fits the manual's statement that pipe table cells cannot contain block elements or span multiple lines. Remove the line breaks from the cells first if you want pipes.

**CJK text is padded by display width.** Pandoc counts a Chinese character as two columns, so a cell holding `中文` got two fewer padding spaces than a cell holding `ab`, and the columns line up in a monospaced font. This only affects the raw file.

Pandoc takes the first row as the header, and the divider it writes has no alignment colons. Add `:---:` or `---:` by hand where you want centred or right-aligned numbers.

## Option 3: a command-line filter

For small tab-separated data, such as a range you just copied, this `awk` command escapes pipes, builds each row and adds the divider after the first line.

```bash
pbpaste | awk -F'\t' '{
  gsub(/\|/, "\\|")
  out = "|"
  for (i = 1; i <= NF; i++) out = out " " $i " |"
  print out
  if (NR == 1) { s = "|"; for (i = 1; i <= NF; i++) s = s " --- |"; print s }
}' | pbcopy
```

On a two-line sample with `A|x` in a cell it printed `| A\|x | 3 |` for the data row and `| --- | --- |` for the divider. It does not understand quoted CSV, so use it only on tab-separated text, and it does not pad columns, which the renderer ignores anyway.

## The tricky cells

| Situation | What happens |
| --- | --- |
| Merged cells | Split or lost, because pipe tables have no spans |
| Line break in a cell | A space, `<br>`, or an HTML table, depending on the tool |
| Pipe in a cell | Escaped as `\|` by Pandoc, the awk filter and MiaoYan |
| Alignment | Usually lost, except in tablesgenerator.com |
| Header row | The first row, always |

The limits come from the GFM spec. The header row and divider row must have the same number of cells or the block is not a table. A body row with fewer cells gets empty cells added, extra cells are ignored, and block-level elements cannot go inside a cell.

If the sheet depends on merged cells or lists inside cells, write an HTML `<table>` with `colspan` or `rowspan`, or split it into two simpler tables.

## Pasting a table in MiaoYan

MiaoYan has no CSV or TSV import and does not turn tab-separated text into pipes on paste. It does convert HTML. When the clipboard holds an HTML version containing a `<table>`, a heading, a list, a quote or a code block, the editor inserts Markdown instead of the plain text. For tables the V4.9.0 source shows this:

- The first row always becomes the header, with `th` cells or without.
- A pipe in a cell is escaped as `\|`.
- A line break inside a cell becomes a space.
- Rows shorter than the widest row are padded with empty cells on the right. The code ignores `colspan`, so a merged cell becomes one cell and the gap lands at the end of the row, not where the merge was.
- The divider is plain `---`, so alignment is not kept.

It is aimed at rich text copied from browsers, so whether a spreadsheet paste takes this path depends on whether the app puts HTML on the clipboard. When a paste gives you tabs, convert with Pandoc or a generator and paste the result. [Markdown to HTML](/blog/markdown-to-html/) explains why a table sometimes shows as raw pipes in other tools.

## Checking the result

Look at the rendered table, not only the source. A table that renders as a paragraph of pipes almost always has a divider row whose cell count differs from the header. A shifted column usually means an unescaped pipe in the data, and a literal `<br>` in a cell means the viewer escapes HTML. On a long table, check the last row and the widest row, where a stray tab or a missing cell usually shows up.

## FAQ

### Why does pasting from Excel give me tabs?

Spreadsheet apps copy a range as tab-separated plain text. Markdown tables use pipes, so the text needs converting first.

### Can a Markdown table have merged cells?

No. Pipe tables are a plain grid. Use an HTML table with `colspan` or `rowspan`, or split the data.

### How do I convert a CSV file to a Markdown table?

Run `pandoc -f csv -t gfm file.csv`, or import the file into a generator such as tablesgenerator.com. Remove line breaks inside cells first if you want Pandoc to write a pipe table.
