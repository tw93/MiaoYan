Converting Markdown to HTML takes two steps: a parser reads the Markdown and builds a document tree, and a renderer writes that tree out as HTML tags. For a one-off page, a command-line tool such as Pandoc (`pandoc -s note.md -o note.html`) gives a complete file you can host anywhere. In MiaoYan V4.5.0, File > Export > HTML does the same from the app, with one limit that matters: the file loads its styles and scripts from MiaoYan's CDN and does not carry your local images.

## Fragment or full page

Parsers give you a fragment by default, a pile of `<h1>`, `<p>` and `<ul>` elements with no `<html>` or `<body>`. That is what you want when the HTML goes into a template, a CMS or an email. A full page needs a head with a charset, a title and a stylesheet link around the fragment.

Pandoc is explicit about it. Its manual says "By default, pandoc produces a document fragment", and `-s` or `--standalone` produces a complete document with a `<head>` and `<body>`. `--css` should be used together with `-s`, because the link to the stylesheet goes in the document header.

A full page also needs a `<title>`. With Pandoc 3.12.1, a note with no title metadata got its file name, so `note.md` became a tab titled note. `--metadata title="My Note"` sets it but also adds a title block with its own `<h1>` above the note's `# My Note`, so the heading appears twice. `-V pagetitle="My Note"` sets only the tab title, and `--shift-heading-level-by=-1` turns the opening `#` heading into the document title, which the manual describes, at the cost of moving every `##` up to level 1.

## Command-line routes

```bash
# Pandoc: complete page, linked stylesheet
pandoc -s note.md -o note.html --css style.css

# Pandoc: one file with styles and images inlined
pandoc -s note.md -o note.html --embed-resources

# markdown-it: fragment to a file
npm install markdown-it
npx markdown-it note.md -o note.html
```

Pandoc's `--embed-resources` produces a standalone HTML file with no external dependencies and works only with HTML output. The older `--self-contained` is a deprecated synonym for `--embed-resources --standalone`. Pandoc's own Markdown already reads pipe tables, task lists and strikethrough; `-f gfm`, which the manual describes as GitHub-Flavored Markdown, reads the file by GitHub's rules instead and also turns on `> [!NOTE]` style alerts. Pandoc's math method defaults to MathML, and `--math-method=katex` switches to KaTeX.

The markdown-it CLI reads a file, or standard input when none is given, and writes to standard output unless you pass `-o`. Its flags include `--no-html` to disable embedded HTML, `-l` for autolinking and `-t` for typographic replacements. The project's README lists "Safe by default" among its features, and the library's default options do set `html: false`, but the CLI turns raw HTML on unless you pass `--no-html`, so add that flag before converting text you did not write.

cmark-gfm is the C parser MiaoYan uses. Its README says the library scrubs raw HTML and potentially dangerous links by default, and that `--unsafe` on the command line allows them. It renders the Markdown to HTML; the page head, stylesheet and scripts are yours to add.

## How it actually works

Markdown is a text format, and every tool follows the same pipeline. A block parser decides what each line is, whether paragraph, heading, list or code fence, and an inline parser handles emphasis, links and code spans inside them. The result is a tree, and a renderer walks the tree and prints tags. CommonMark defines how the core syntax maps to HTML, and GFM adds tables and task lists on top, so two tools with different extensions can turn the same file into different HTML. That is why a table can be a table in one tool and plain pipes in another.

Everything else in a "converted" page is added after rendering: the head, the stylesheet, the scripts that draw math or diagrams. Whether a converter does that for you is the real difference between tools. [CommonMark vs GFM](/blog/commonmark-vs-gfm/) lists what each spec defines.

## MiaoYan's HTML export

In MiaoYan V4.5.0, select a note and choose File > Export > HTML, or press `Control + Shift + H` in the MiaoYan window. It does not need the preview to be open. The file is written to Downloads as `Title.html`, where the title is the note title with `/` replaced by `_`, and a name that already exists gets a timestamp appended; if Downloads cannot be written, a save panel opens instead. The toast reads `Saved to Downloads folder~`.

What the file contains:

- The body is cmark-gfm's output with raw HTML allowed, so tags you typed are kept. Front matter at the top of the note is removed first.
- MiaoYan puts the note title in an `<h1>` at the top. The check meant to skip this when the note already opens with a `#` heading never matches in V4.5.0, so the title line is added above your own heading too, and when the two are the same the title appears twice; delete one in the exported file if that matters.
- The page uses the preview template, with your Preview Font setting, a content column limited to 760 pixels, and light or dark colors depending on the current theme.
- It does not inline anything. A `<base>` tag points to `https://cdn.miaoyan.app/Resources/DownView.bundle/`, so the template's stylesheets and scripts for typography, KaTeX, highlight.js, Mermaid and Markmap load from there. Opened offline, the file keeps the background, text color and column width written into the page itself but loses the typography stylesheet, and math and diagrams are not drawn.

The limit that surprises people is images. HTML export renders the Markdown without the step that preview and PDF export use to find local images, and the `<base>` tag makes every relative path resolve against the CDN, so `/i/photo.png` becomes `https://cdn.miaoyan.app/i/photo.png` and `images/fig.png` a path under `DownView.bundle/` there, neither of which exists. Copying the images next to the HTML file does not help either. Remote images with an `https://` address load. For a file you plan to share, either use remote image URLs in the note, or export a PDF as covered in [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/). [Markdown images](/blog/markdown-images/) has the details on image paths.

## Putting the result online

A file that needs no server can go to any static host. GitHub Pages, for example, takes HTML, CSS and JavaScript files from a repository and publishes them, and it looks for an `index.html` as the entry file, at the top level of the folder you publish from. Name the converted page `index.html`, put images next to it, and use relative paths in the Markdown so they still resolve after the move.

With Pandoc, `--embed-resources` gives you one file you can email or upload with nothing to forget. With MiaoYan's export, remember the CDN dependency: if you host the page, the styles come from `cdn.miaoyan.app`, not from your own site.

## Raw HTML and safety

Markdown allows raw HTML, and a converter that passes it through will pass through a `<script>` tag too. Pandoc's manual states the consequence for its Markdown reader: with `raw_html` enabled, users can inject arbitrary HTML, and it advises running all HTML generated from untrusted input through an HTML sanitizer. You can turn the extension off with `-f markdown-raw_html`, but the same section warns that URLs and attributes can still carry dangerous content, so a sanitizer is the answer for user-submitted text.

DOMPurify describes itself as a DOM-only XSS sanitizer for HTML, MathML and SVG, used as `DOMPurify.sanitize(dirty)`, and on a server it needs a DOM such as jsdom. For your own notes none of this matters. It matters when the Markdown comes from somebody else, because MiaoYan's preview and export both leave raw HTML on.

## What goes wrong

- **The page is unstyled.** A Pandoc page has no stylesheet of yours unless you pass `--css`, and a MiaoYan export opened offline cannot load its stylesheet.
- **Images are broken.** Local paths in a MiaoYan export resolve against MiaoYan's CDN. Use remote URLs, or use `--embed-resources` in Pandoc.
- **A table appears as pipes.** The converter is a plain CommonMark parser with no table extension. Pandoc and markdown-it read pipe tables by default, and cmark-gfm reads them once its table extension is attached.
- **Math shows as raw dollar signs.** The page has no math renderer. In MiaoYan's export it needs the CDN to be reachable.
- **A hosted page 404s.** The entry file is not named `index.html` or not at the top level of the published folder.

## FAQ

### Do I need to host the HTML?

No. It opens from disk in any browser, though a MiaoYan export needs a network connection for its styles and scripts.

### Which tool gives the cleanest HTML?

cmark-gfm and markdown-it give plain fragments. Pandoc with `-s` gives a full page, and its output depends on the extensions you enable.

### Can MiaoYan convert a whole folder?

The export menu works on the selected note only.
