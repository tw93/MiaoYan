## What happens when you paste

Copy cells in Excel, Numbers or Google Sheets, click the first cell of the grid and paste, and the whole table becomes what you copied. Paste into a cell further in and it fills right and down from there, adding rows and columns as needed, and Undo takes it back. CSV and TSV files can be dropped onto the grid, and an existing Markdown table pasted in brings its column alignment with it.

Markdown tables have limits of their own, so a line break inside a cell becomes `<br>`, a pipe is escaped as `\|`, and a merged cell is split, with its content in the first cell. The first row is always the header. The syntax is covered in [Markdown tables: alignment, pipes and line breaks](/blog/markdown-tables/), and other ways to convert a sheet in [Excel to Markdown table: paste, convert and check](/blog/excel-to-markdown-table/).

## FAQ

### Is it free?

Yes, and there is no account. The table is converted in your browser, so pasted data is never sent to a server, and your last table stays in this browser for the next visit.

### Why do Chinese and Japanese characters count as two?

Terminals and Prettier count a CJK character as two columns wide, and the padding here does the same, so the pipes line up in a font where a CJK character is exactly two Latin characters wide. Turn off Line up columns for the compact form without padding.

### Can I merge cells?

Markdown tables cannot merge cells, so merged cells you paste are split, with the content in the first one. When a merge is essential, write an HTML `<table>` in the note and use `colspan` and `rowspan`.
