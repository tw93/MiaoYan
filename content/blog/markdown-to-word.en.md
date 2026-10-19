The reliable way to turn Markdown into a Word file is Pandoc: `pandoc note.md -o note.docx` converts headings, lists, tables, code and math into real Word structures, and `--reference-doc` lets you set the fonts and styles of the result. MiaoYan V4.5.0 does not write `.docx`. Its exports are HTML, PNG image and PDF, so inside MiaoYan the choices are to export something Word can read or paste, or to run Pandoc on the same note file. Diagrams, callouts and wikilinks need a manual step in either case.

## The Pandoc route

```bash
pandoc note.md -o note.docx
```

Run it in the folder that holds the note, so the images it refers to can be found. Pandoc's manual says `--resource-path` defaults to the working directory, and that it matters only when Pandoc itself has to find an image, as it does when it writes a docx. If the images live elsewhere, list the folders with `--resource-path`, and include `.` yourself, because once the option is set the working directory is no longer searched unless you list it.

Images pasted into MiaoYan are written as `/i/name.png`, with a leading slash, and Pandoc reads that as a path from the root of the disk, so it warns `Could not fetch resource` and puts the image's description in its place. Drop the slash on the way in, from the note's folder:

```bash
sed 's#](/i/#](i/#g' note.md | pandoc -f gfm -o note.docx
```

Pandoc's own Markdown already reads pipe tables, task lists and strikethrough. Reading the note as GFM follows GitHub's rules instead and turns on the `alerts` extension for `> [!NOTE]` callouts:

```bash
pandoc -f gfm note.md -o note.docx
```

The manual describes `gfm` as GitHub-Flavored Markdown. Without it, Pandoc reads the file as its own Markdown flavor, which overlaps with GFM but is not identical. `$...$` math works either way: the `tex_math_dollars` extension treats text between two dollar signs as TeX math, and it is on for both formats. Run `pandoc --list-extensions=gfm` to see which extensions the format has, where a leading `+` marks one that is on.

## Where the formatting comes from

Pandoc does not draw a Word document from scratch. It fills a reference document with your content, and the look comes from that document's styles. The manual lists them: paragraph styles including Normal, Body Text, First Paragraph, Compact, Title, Author, Date, Heading 1 through Heading 9, Source Code and Footnote Text, character styles such as Verbatim Char and Hyperlink, and one table style named Table.

So the formatting is not in the Markdown. A `##` becomes a Heading 2 paragraph, a fenced code block becomes Source Code, and what those look like is whatever the reference document says. Math is not skipped either: the manual says TeX math in docx output is rendered as OMML, Word's own equation markup, so a formula arrives as an equation you can edit in Word.

## Set the fonts, especially for Chinese

Get the default reference document, edit it in Word, and pass it back:

```bash
pandoc -o custom-reference.docx --print-default-data-file reference.docx
pandoc note.md -o note.docx --reference-doc=custom-reference.docx
```

Open `custom-reference.docx` in Word or LibreOffice and edit the styles, not the sample text: change Normal and Body Text for the body, the Heading styles for titles, and Source Code for code. For a Chinese document, set the Chinese (East Asian) font on those styles as well as the Latin one, because a style can name one face for Latin characters and another for Chinese ones. If you only change the Latin font, the Chinese text keeps whatever face the style already had and can look mismatched. The same reference file works for every note you convert, so this is a one-time job.

The default `reference.docx` also carries page size and margins. If the converted file comes out on the wrong paper, fix it once in the reference document.

## Going through MiaoYan's exports

MiaoYan's File > Export submenu has HTML, Image, PDF and MiaoYan PPT PDF. None is a Word format, and none is a Pandoc substitute for editing. They are useful when the reader needs the document as rendered rather than as editable text.

- **PDF.** File > Export > PDF prints the preview onto a fixed A4 page and saves it in Downloads. Use it when the recipient only reads, or when diagrams must stay exactly as drawn. [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/) covers what it contains.
- **HTML.** File > Export > HTML writes `Title.html`. Its styles and scripts load from MiaoYan's CDN and local image paths point at that CDN too, so they do not load, as described in [Markdown to HTML](/blog/markdown-to-html/). You can open it in a browser, select the content and paste it into Word, but what Word keeps from pasted HTML varies, so try it with your own note and check the result. Only remote images can come along.
- **Image.** Writes a PNG of the whole preview, which suits a single figure more than a document.

## What survives and what breaks

| Element in the note | Through Pandoc | What to do |
| --- | --- | --- |
| Headings, lists, bold, links | Become Word styles | Check the styles in the reference document |
| Tables | Become Word tables using the Table style | Check widths and alignment |
| Code fences | Fenced code with a language name is highlighted; in docx it uses Source Code | Check long lines |
| `$...$` math | Written as Word equations (OMML) | Click an equation and check it |
| Mermaid, PlantUML, Markmap blocks | A fence with a language word is ordinary code to Pandoc, not a drawing | Paste a picture of the diagram |
| `> [!NOTE]` callouts | With `-f gfm`, a plain paragraph reading Note followed by the text; with Pandoc's own Markdown, a quote starting with `[!NOTE]` | Restyle or rewrite it in Word |
| `[[wikilinks]]` | Pandoc has wikilinks extensions, named `wikilinks_title_after_pipe` and `wikilinks_title_before_pipe` | Replace with real links, or enable one |

For diagrams, MiaoYan renders Mermaid and Markmap in its preview and in PDF export, so one workable path is to capture the diagram from the preview and insert it as a picture, with the Mermaid source kept in the note. PlantUML needs a network because the preview asks a PlantUML server for the SVG.

Callouts lose their box. MiaoYan turns `> [!NOTE]` blockquotes into styled callouts in its preview. Pandoc's manual says its `alerts` extension supports GitHub-style Markdown alerts, and `--list-extensions` shows it on for `gfm` and off for Pandoc's own Markdown. With Pandoc 3.12.1, `-f gfm` turns the callout into a paragraph reading Note followed by the text, both in the First Paragraph style with no box or color, while Pandoc's own Markdown keeps a quote that starts with `[!NOTE]`.

## A short check after converting

1. Open the file and look at the heading levels in Word's navigation pane. A skipped level means the source skipped one.
2. Scroll to every table and every image. A missing image means Pandoc could not find the file, so run it from the note's folder or set `--resource-path`.
3. Click one equation. It should be an equation, and if it is a picture or raw dollar signs, revisit the input format.
4. Look at the first page. A front matter block at the top of the note is metadata and not body text, so check that the title and author came out the way you want.
5. Search for `[!`, `[[` and three backticks to find callouts, wikilinks and code fences that did not convert.
6. Change one style in `custom-reference.docx`, convert again, and confirm the whole document follows.

Pandoc's raw blocks can insert Word-specific XML, such as a page break, into a docx. The manual shows this under the `raw_attribute` extension, which is on in Pandoc's own Markdown and off in `gfm`, so with GFM input write `-f gfm+raw_attribute`. It is the way to control layout details Markdown cannot express. For the rest of what the Markdown side can express, see the [Markdown cheat sheet](/blog/markdown-cheat-sheet/) and [Mermaid diagrams in Markdown](/blog/mermaid-diagrams-in-markdown/).

## FAQ

### Can MiaoYan save a .docx directly?

No. V4.5.0 exports HTML, Image, PDF and MiaoYan PPT PDF. Use Pandoc on the note file for a docx.

### Why do my Chinese characters look different from the English ones?

The style names one font for Latin text and another for Chinese. Set the East Asian font in the reference document's styles.

### Do I need LaTeX installed?

Not for docx. Pandoc's LaTeX requirement applies to its default PDF route, not to a Word file.
