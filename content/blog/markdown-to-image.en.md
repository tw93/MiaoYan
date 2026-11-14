To turn a Markdown note into one long image on a Mac, the shortest route is an app that renders the preview and saves it as a PNG. In MiaoYan, select the note and choose File > Export > Image, and a PNG of the whole rendered note lands in Downloads. Without such an app you can render the Markdown to HTML and take a full-page screenshot in a browser, which works but leaves you to pick the width and the height yourself. Whichever route you take, decide the width first, because a phone screen is where most long images are read.

## Export a note as an image in MiaoYan

Select the note in the list, then choose File > Export, which opens the Export submenu beside the selected row with HTML, Image, PDF and MiaoYan PPT PDF. The Chinese interface calls the item 图片 under 导出. With the note list focused and slide mode off, `Control + Shift + I` does the same. With no row selected, nothing is exported.

If the preview is hidden, MiaoYan switches it on, waits one second, exports, and switches it off again. A toast shows `Exporting...` with a percentage, then `Saved to Downloads` (已导出到下载文件夹 in Chinese) or `Export failed`. The file is `Note title.png`; if that name is already in Downloads, the time is added to the name as `_yyyy-MM-dd_HH-mm-ss`. If the write to Downloads fails, as it can in a sandboxed build, a save panel opens instead. The shortcut, the preview switch and the file naming are the same as for PDF, which [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/) walks through.

## What ends up in the PNG

The image is a snapshot of the live preview, drawn at double scale. The note's title is inserted as an `h1` above the content, with a thin rule under it. This happens every time: if the note already begins with a `#` heading of the same text, the PNG shows the title twice, so delete that first heading before exporting if you only want it once. The table of contents and the heading anchors are hidden. Tables are set to the width of the column instead of scrolling sideways, so a wide table is squeezed into equal columns, as it is in a PDF.

The height is the full height of the rendered note. There is one image, not pages, and the export code sets no height limit of its own. For a very long note, open the PNG and check that the bottom is there.

The width is the width of the preview pane. The snapshot is drawn at twice the pane's width in points, and on a Retina display each point becomes two pixels, so a pane 800 points wide gives a PNG 3200 pixels wide, and the height is scaled the same way. Inside the pane, the text column is capped by Settings > Editor > Preview Width, which offers 600px, 800px, 1000px, 1200px, 1400px and Full Width, with 1000px as the default. The column is left-aligned, so in a pane wider than the column the extra space shows up as empty background on the right. For an image meant for a phone, narrow the pane by dragging the divider or choose 600px, then export and check the right edge.

Colors follow the app. In light mode the page is white with `#262626` text, and in dark mode it is `#1E1D1B` with `#D6D1C6` text. PDF export forces the light page; image export does not.

## Does it wait for diagrams and images

Yes for images, Mermaid and Markmap. Before the snapshot, the export loads every lazy image and checks that all images have finished loading and that no Mermaid block lacks `data-processed` and no Markmap block lacks its shown or failed marker. It checks up to five times, half a second apart, and after about two and a half seconds it exports anyway, so an image on a slow network or a heavy diagram can still be missing from the PNG. PlantUML diagrams are images fetched from plantuml.com, so they count as images and need a network connection. Overall the export gives up after 30 seconds and reports `Export failed`.

The readiness check does not mention math. KaTeX is loaded with the preview page, so formulas are normally drawn by then, but a formula-heavy note is worth a quick look in the result. The three diagram types are separated in [Mermaid diagrams in Markdown](/blog/mermaid-diagrams-in-markdown/).

## Other ways to get a long image

### A browser full-page screenshot

Export the note to HTML, open it in Chrome, and use DevTools device mode. Open DevTools, click Toggle device toolbar, then in the More options menu choose Capture a full size screenshot. Chrome's documentation lists it next to Capture screenshot, which saves only the visible viewport. The width is whatever device width you set in the toolbar, which makes this route good for a phone-shaped image.

The catch is the HTML itself. MiaoYan's HTML export loads its stylesheets and scripts from a CDN, so the page needs a network while you capture it, and the details are in [Markdown to HTML](/blog/markdown-to-html/).

### Pandoc, then the same screenshot

Pandoc can build a page that needs no network:

```bash
pandoc -s --embed-resources --css=style.css note.md -o note.html
```

In Pandoc's manual, `-s` produces a complete document rather than a fragment, `--embed-resources` puts scripts, stylesheets and images into the file as `data:` URIs, and `--css` links a style sheet and should be used with `-s`. Open `note.html` in Chrome and take the full-size screenshot from device mode as above. Chrome's headless mode can run the browser from a script, but its current documentation describes only the `--headless` switch and no screenshot option, so for a one-off image the DevTools route is the documented one.

## Tips for an image people read on a phone

Width matters more than anything else. A column that is comfortable on a desktop becomes tiny type once a chat app scales it to the phone's width, so narrow the preview before exporting. A long line of text, a wide table or a wide code block is where it goes wrong first.

Light or dark is a choice about where it will be posted. A white page is the safe default for chats and posts, since it looks the same in either theme of the receiving app. Because image export follows the app's appearance, set Settings > General > Appearance to Light first if the note will go into a bright feed.

Chat and social apps can recompress an image, or cut off the part below a certain height, when it is very long. The behavior differs by app and changes, so send the image to yourself or a test chat first. If the bottom is cut or the text is soft, split the note into two notes and export each, or share a PDF instead.

## FAQ

### Is the PNG sharp enough to zoom in?

It is drawn at twice the pane's width in points, which is four pixels per point on a Retina display, so text stays crisp when zoomed, within whatever the receiving app does to it afterwards.

### Where does the file go?

To the Downloads folder, named after the note title.

### Can I export only part of a note?

Not from the Export menu, which takes the whole note. Copy the part into a new note and export that.

### Image or PDF for sharing?

An image is easier to post and to read on a phone. A PDF has pages and a selectable text layer, and it is the better choice for printing, as in [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/).
