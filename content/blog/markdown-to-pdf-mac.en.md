Select the note and choose File > Export > PDF. MiaoYan prints the rendered preview onto a fixed A4 page and saves `Title.pdf` in Downloads. There are no settings for paper size, margins, headers, or a dark page. The text follows the Preview Font setting, and a page break can be written into the note as raw HTML. For US Letter or other margins, use Pandoc, Typora, or another app's print dialog.

## Export the note

File > Export opens the note menu's Export submenu beside the selected row: HTML, Image, PDF, and MiaoYan PPT PDF. The same submenu is on the note list's context menu. With no row selected, nothing is written.

With the note list focused and slide mode off, `Control + Shift + P` exports to PDF, `Control + Shift + I` exports to Image, and `Option + Control + Shift + P` exports to MiaoYan PPT PDF. During slide mode those keys are ignored.

PDF and Image turn the preview on if it was off, wait one second, then export, and turn the preview off again if this export enabled it. The toast reads `Exporting...` with a percentage, then `Saved to Downloads folder~` or `Export failed`. The file name is the note title with `/` replaced by `_`, followed by `.pdf`. A UUID title becomes `Untitled Note`. A name already in Downloads gains `_yyyy-MM-dd_HH-mm-ss`, and a failed write opens a save panel. In Preview, confirm the inserted title, the footer `1 / N`, and an outline of h1 through h3. Image writes a PNG of the same preview.

## What the PDF contains

Math uses the bundled KaTeX, with delimiters `$...$`, `$$...$$`, `\(...\)`, and `\[...\]`. The syntax that engine accepts is covered in [LaTeX math in Markdown](/blog/latex-math-in-markdown/).

Fenced code is highlighted with highlight.js 11.5.1. The print stylesheet sets `white-space: pre-wrap` on `pre`, so long lines wrap. It sets `page-break-inside: avoid` on `pre`, tables, figures, blockquotes, Mermaid blocks, and diagram panels, and `page-break-after: avoid` on headings.

Mermaid and Markmap run from scripts in the app. Printing waits until Mermaid blocks have `data-processed`, Markmap blocks have `data-markmap-rendered`, and images have a non-zero width: 80 passes at 120 ms, 9.6 seconds in the source comment, then it writes anyway. A failed Mermaid block keeps its source, and the error text stays out of the page.

PlantUML diagrams are fetched from `https://www.plantuml.com/plantuml/svg/`, so they need a network and the source leaves the Mac. [Mermaid diagrams in Markdown](/blog/mermaid-diagrams-in-markdown/) separates the three.

A relative image is resolved in the note's project folder. `/i/photo.png` drops the leading slash and becomes `i/photo.png` there. A full path is used when the file exists. A missing local file is replaced by a box labeled `Image Not Found`. Every image after the first is lazy-loaded with a placeholder and `data-src`; export copies `data-src` back to `src` because the print view never scrolls. Tables are forced to the page width, the on-screen table of contents is hidden, and links lose their underline.

The paper is A4, 595.2 by 841.8 points, with margins of 40, 48, and 45 points (top, bottom, sides), noted as 14 mm, 17 mm, and 16 mm. The print panel stays hidden, wide content is scaled to the page, and the background stays white in a dark preview. Text keeps the Preview Font from settings, with PingFang SC and Hiragino Sans GB behind it for Chinese. Headings h1 through h3 become an outline, with each bookmark's page estimated from the heading's height in the unpaged document, so an image or an unbreakable block can shift it by one page. A gray 8.5 pt footer reads `1 / N`. The PDF title is the export title, and the creator is MiaoYan.

## A slide deck is a different PDF

File > Export > MiaoYan PPT PDF writes `Title_PPT.pdf` when the note contains `---`. Otherwise the toast is `No delimiter --- identification, Cannot use MiaoYan PPT~`. The test is a substring, so a table row `|---|` passes it too. How a line of `---` becomes a slide is in [Markdown to slides](/blog/markdown-to-slides/).

`Command + Option + P` toggles MiaoYan PPT. The PDF item turns that mode on if it was off, enters full screen if the window is not, waits 1.2 seconds, captures reveal.js with `pdfMaxPagesPerSlide` set to 1, then turns the mode off if this export enabled it. The file is a slide snapshot, without the A4 margins or the `1 / N` footer. Choosing PDF while slide mode is already on also takes a web view snapshot of the slides, saved as `Title.pdf`, with no footer.

## How the page is built

MiaoYan renders the note with cmark-gfm, raw HTML included, then a web view runs KaTeX, highlight.js, and the diagram scripts. Export copies that document into a hidden web view, injects the print stylesheet, waits for images and diagrams, and saves with `NSPrintOperation`, print panel off. WebKit paginates. PDFKit adds the outline and the footer. The PDF is the preview, printed.

Pandoc's default converts Markdown to LaTeX and runs `pdflatex`, so TeX has to be on `PATH`. `--pdf-engine` selects the program. The manual includes `pdflatex`, `xelatex`, `lualatex`, `weasyprint`, and `wkhtmltopdf`. With no `-t` flag the engine is `pdflatex`. For `-t html` the default is `weasyprint`, with `wkhtmltopdf` among the other HTML engines. The manual also says `wkhtmltopdf` is deprecated and should not be used on untrusted input.

LaTeX takes paper, margins, and fonts as variables, and a missing package stops in the TeX log. An HTML engine prints a styled page, and `--css` is how you change it. Write `-s -o test.tex` and run `pdflatex test.tex` to inspect the intermediate `.tex` file.

## Pandoc, Typora, VS Code, and the print dialog

From the folder that holds the note and its images:

```bash
pandoc note.md -o note.pdf --pdf-engine=xelatex -V CJKmainfont="PingFang SC"
```

If you omit `--resource-path`, Pandoc searches the working directory for images, and only when it needs the file, which includes writing a PDF. For an HTML engine:

```bash
pandoc note.md -o note.pdf --pdf-engine=weasyprint
```

Inline TeX reaches the LaTeX writer, so `\newpage` breaks a page there and does nothing for WeasyPrint. YAML `papersize` accepts `a4` and `letter`, and `geometry` accepts options such as `top=30mm` and `left=20mm`. With `CJKmainfont` set, `xelatex` needs `xeCJK`, and either `xelatex` or `lualatex` needs `fontspec`. PingFang SC is the CJK family already named in MiaoYan's print stack.

Typora exports from File > Export > PDF. Export > PDF in preferences sets paper size (A4, A5, or custom), margins, a theme, a break between h1 headings, and a header and footer such as `No. ${pageNo} / ${pageCount}`. On Windows and Linux that path only supports light themes. PDF (LaTeX / Pandoc) shows up only after you add it, and then it needs Pandoc installed plus an engine on `PATH` or its full path. [Typora alternatives on Mac](/blog/typora-alternative-mac/) compares the editors.

In VS Code, yzane's Markdown PDF extension puts `markdown-pdf: Export (pdf)` on the editor's right-click menu and in the palette opened with F1. It prints through Chrome, Edge, Chromium, or a Chromium it downloads. Math is KaTeX with no network, Mermaid fences are included but the Mermaid script loads from a CDN by default (`markdown-pdf.mermaidServer`), and `markdown-pdf.displayHeaderFooter` defaults to true.

MiaoYan has no File > Print, so this route runs in another app that opens the note. Apple's Mac User Guide gives this route for any printable document: File > Print, then the PDF menu, Save as PDF, and the same Print dialog is where paper size is chosen. MiaoYan's HTML export is a poor choice to open in a browser and print: its base URL is `https://cdn.miaoyan.app/Resources/DownView.bundle/`, and local images are not rewritten to `file://`, so `images/fig.png` is looked up on that CDN and does not load.

## What goes wrong

Dollar signs left on the page. KaTeX skips code, and math runs on an idle callback with a 200 ms timeout, so export again after the preview has drawn the formula. `$5` is classified as currency and stays text. `$2+2$` is math.

An `Image Not Found` box, or a blank figure. Image lookup uses the project folder. `/i/photo.png` is `i/photo.png` there. Remote images and PlantUML need the network, and once the wait ends the PDF is saved with the hole still there.

A fence split across two pages. `pre` is asked to stay whole, with lines wrapping, on that fixed A4. Shorten the fence, or set Pandoc `geometry`. Raw HTML reaches the preview, so `style="page-break-before: always"` is a break you can write into the note.

Chinese missing from a Pandoc PDF. The default engine is `pdflatex`. Use `xelatex` and `CJKmainfont` as above. MiaoYan's own PDF already names PingFang SC and does not need TeX.

A bookmark one page off. Trust the footer, which is the real page index. The outline uses each heading's height in the unpaged document, and images or unbreakable blocks move the real breaks.

Only the delimiter toast. The note has no `---`, so MiaoYan PPT PDF stops there. A note-list shortcut pressed during slide mode does nothing at all; use Export in the menu.

A white page while the preview is dark. Print CSS sets the background to `#ffffff`. Article export has no dark page.

`Export failed` and no file. The captured page was 50 characters or fewer, the hidden page failed to load, or printing produced almost nothing. Let the preview finish rendering, then export again. If Downloads cannot be written, you get a save panel instead.

## FAQ

### Can this PDF be US Letter instead of A4?

MiaoYan has no paper control. Set Pandoc's `papersize` to `letter`, use Typora's paper size, or open the note in an app that prints and pick the size in File > Print before Save as PDF.

### Does MiaoYan need TeX installed?

No. Its PDF export is a WebKit print. TeX is for Pandoc's default LaTeX path, and for Typora only after you add PDF (LaTeX / Pandoc).

### Why did PDF come out as slides?

Slide mode was on, so PDF takes the reveal.js snapshot. Leave that mode and export again. MiaoYan PPT PDF names its file `Title_PPT.pdf`, while PDF in slide mode keeps `Title.pdf`.

### The bookmark opens the wrong page. Is the footer wrong?

The footer shows the real page index over the page count. The bookmark page is estimated from the heading's height in the unpaged document and can be off by one.
