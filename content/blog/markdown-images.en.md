Markdown has no syntax for image size. Write the image as `![alt text](path "optional title")`, and when you need a width, switch that one image to HTML: `<img src="/i/photo.png" width="320" alt="alt text">`. In MiaoYan V4.5.0 the HTML form works in the preview because raw HTML is allowed, and the width you set is capped at the column width. Keep images next to the notes and refer to them by a relative path, because that is the part that breaks when a note moves.

## Image syntax, alt text and titles

An image is the link syntax with a leading `!`. The CommonMark spec calls the bracketed part the image description and says it is standardly used as the `alt` attribute when the image is rendered to HTML. A title in quotes after the path becomes the `title` attribute, which browsers show as a tooltip.

```markdown
![Sunset over the harbor](/i/harbor.jpg "Taken from the pier")
```

Write the description for someone who cannot see the picture: what it shows, not "image" or the file name. An empty description, `![](...)`, is valid and is what MiaoYan writes when you paste an image, so fill it in afterwards if the note will be published.

## Where the image file lives

When you paste an image into a note, or insert an image file through the file picker, MiaoYan V4.5.0 copies it into an `i/` folder inside the folder the note is in, creating it if needed, and writes `![](/i/<filename>)` into the text. The folder name `i` is fixed, and files that are not images go to a `files/` folder in the same way. Image files keep their name, with each run of characters other than letters, digits, `-` and `_` turned into one `-`. A pasted screenshot has no file name, so it is saved as JPEG under a lowercase UUID, and a name that is already taken also falls back to a UUID. The mobile editor writes into the same `i/` folder, so after sync a note opened in the other app finds its pictures.

In the preview, MiaoYan resolves `/i/harbor.jpg` against the folder the note is in, not against the root of your disk. A leading slash therefore does not mean what it means on a web server. GitHub's syntax page lists `/assets/images/electrocat.png` as the relative link for a file on the same branch and tells you to prefer relative links over absolute ones for images in a repository.

## How the preview resolves a path

For each `<img>` the preview checks the `src` value. An `http://` or `https://` address is left alone. A path that starts with `/` but not `/i/` is treated as an absolute system path and used only if the file exists. Anything else, including `/i/...` and `images/fig.png`, is looked up relative to the note's folder and turned into a `file://` address. If the file is missing, MiaoYan replaces the whole image with a gray box that says `Image Not Found`. The first image loads straight away and later ones load lazily as you scroll, and a click zooms an image that sits in a paragraph.

[[figure:markdown-images|Pasted images are copied into an i/ folder and referenced in the note text; the preview resolves the reference against the note's folder, PDF export prints the preview, and HTML export cannot find local images.|Pasting copies the file into i/ and writes its path into the note, so the preview and PDF find it, while HTML export does not.]]

A note that uses `/i/harbor.jpg` or `i/harbor.jpg` works on any Mac as long as the `i/` folder travels with the note. A note that uses `/Users/you/Pictures/harbor.jpg` works only on the Mac that has that file, and shows the placeholder everywhere else.

## Why images break when a note moves

- **You moved only the `.md` file.** The `i/` folder stayed behind, so every relative path now points at nothing. Move the folder and the notes together, or keep them in a notes folder that you sync as one unit.
- **You renamed the folder or the file.** A path in the note is plain text; nothing updates it for you.
- **The path is absolute.** It names a location on one machine.
- **The link is remote and the page moved or the site blocks hotlinks.** The note then depends on someone else's server.

Local files cost disk space and need to move with the note. Remote images keep the note small and need a network every time you open it. If you want remote links without hand-uploading, the Editor pane of MiaoYan's Settings has an `Upload Service:` menu with None, uPic, PicGo, Picsee and PicList. MiaoYan sends the pasted image over HTTP to PicGo or PicList, which must be running, and runs the uPic or Picsee app installed in `/Applications` to upload it. When an upload succeeds the remote URL goes into the note and the local copy is deleted; when it fails, the local `/i/` path stays and MiaoYan shows a failure message.

## Resizing an image

CommonMark and GFM have no size syntax. The options are all outside the core:

| Method | Example | Works in |
| --- | --- | --- |
| HTML attribute | `<img src="/i/photo.png" width="320">` | Anywhere that allows raw HTML |
| Pandoc attributes | `![](photo.png){width=50%}` | Pandoc only |

In MiaoYan the preview adds `max-width: 100%` and `height: auto` to every image, so `width="320"` gives a 320-pixel image, a `width="2000"` is shrunk to the column, and a `height` attribute is overridden so the proportions stay. The Pandoc `{width=50%}` form is not parsed by MiaoYan, because the parser only has the table, footnotes, strikethrough and task list extensions, and the braces show up as text after the image. Pandoc's manual documents the attribute form, with units of `px`, `cm`, `mm`, `in`, `inch` and `%`. Write the `src` of an `<img>` tag in double quotes: MiaoYan only resolves local paths in that form.

On GitHub, the syntax page documents the `![]()` form and the `<picture>` element, and says nothing about size, so check in a preview before relying on `width` in a README.

One edge case is that if the file is missing, the `Image Not Found` replacement drops the tag, including its `width`.

## Images in PDF and HTML export

PDF export prints the preview. It waits for images to have a width and swaps the lazy placeholders back to the real addresses, so local `/i/` images appear in the PDF. The details are in [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/).

HTML export is different in V4.5.0. It renders the Markdown without the local-image step and adds a base address of `https://cdn.miaoyan.app/Resources/DownView.bundle/`, so a file opened from Downloads cannot find `/i/harbor.jpg` or `images/fig.png`. Remote images do load. For a shareable single file today, use remote image URLs in the note, or export to PDF.

## Checking the result

1. Open the preview and confirm every image shows, not the `Image Not Found` box.
2. Move a copy of the note and its `i/` folder to another place and open it there.
3. For web images, turn off the network and see what remains.

More syntax that varies between apps is in the [Markdown cheat sheet](/blog/markdown-cheat-sheet/), and a note you share across Macs needs its folder synced as in [Sync Markdown notes across devices without a sync service](/blog/sync-markdown-notes-across-devices/).

## FAQ

### Can I set an image size in plain Markdown?

No. The CommonMark spec defines only the description, path and title. Use an HTML `<img>` tag, or Pandoc's attribute syntax if Pandoc renders the file.

### Should I use relative or absolute paths?

Relative. An absolute path names one machine's disk. GitHub's documentation recommends relative links for images in a repository.

### Why does my image show `Image Not Found`?

The file is not where the path says, usually because the `i/` folder was not moved with the note or the file was renamed.
