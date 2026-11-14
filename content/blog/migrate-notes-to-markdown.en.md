Both apps can get your notes out, but neither hands you a finished folder of Markdown. Notion exports Markdown and CSV straight from its Export dialog. Evernote exports ENEX, an XML format, and a separate converter such as evernote2md or Yarle turns that into Markdown. The last step is yours in both cases: read what came out, fix file names and image paths, and open the folder in an editor that works on plain files. Apple Notes has its own route, covered in [Apple Notes to Markdown](/blog/apple-notes-to-markdown/).

## Export from Notion

Open the page, click the `•••` icon at the top right, and choose `Export`. In the export window pick `Markdown & CSV`. Notion's help page says pages that are not databases become Markdown files, and full-page databases become CSV files, with a Markdown file for each subpage. Callout blocks are written as HTML, because Markdown has no equivalent, though MiaoYan's preview still shows raw HTML. Tick the `Include subpages` option to take the whole tree.

The help page describes folders and assets for HTML and PDF exports: with subpages included, pages go in their own folders when unzipped, and images and other assets are saved separately inside them. It does not say the same for Markdown & CSV, so unzip your export and look at the layout before planning the cleanup. On Windows, a path-length error on extraction can be avoided by unchecking `Create folders for subpages` or extracting with a tool such as 7-Zip.

To export everything, open `Settings`, choose `General` under `Workspace`, then `Export all workspace content`. It works on desktop and web only, can take up to 30 hours, and the download link arrives by email and expires after 7 days.

### What Notion drops or changes

- **Database views.** Exporting a database gives you only the current view or the default view, never all views at once. Form views cannot be exported; the help page suggests exporting the responses from a Table view.
- **Databases become CSV.** The rows' properties live in the CSV, while each row's page body is a Markdown file. To keep a property with its note, you copy it into front matter yourself (below).
- **Comments.** The help page mentions comments only for HTML export, so do not expect them in Markdown & CSV.
- **File names.** The help page does not say how exported files are named or whether an identifier is added. Check the unzipped folder; the rename script below only touches names that match its pattern.

## Export from Evernote

Evernote's help page says export works only in the Evernote desktop app for Mac or Windows, not on Evernote Web, and free accounts can export. Select a notebook or specific notes, right-click, and choose `Export...`. Pick a format, either ENEX, single-page HTML or multi-page HTML, check or uncheck the attributes to include (tags, created date, author), and click `Export`. The file is saved to your desktop. Evernote exports up to 100 notes at a time or entire notebooks, and ENEX files can be capped between 300 MB and 2 GB each. Attributes are stored as metadata inside the ENEX or HTML file.

Choose ENEX, the format both converters below read. Of the two, evernote2md is one command, and Yarle adds a desktop app and more options.

### Convert with evernote2md

The evernote2md README installs it with `brew install evernote2md` or from its Releases page. The command form is:

```bash
evernote2md [flags] [input] [outputDir]
```

The input can be one `.enex` file, a directory of exports, or a glob such as `exports/My*.enex`. Without an output directory the notes go to `./notes`. You get one Markdown file per note, an `image` directory for images and a `file` directory for other attachments such as PDFs, with links kept correct, and file dates set from the note's attributes. Tags are inserted into the notes as text, and `--tagTemplate` changes how they look. The README says front matter is optional, with Jekyll as its example use, and `--help` lists the flags.

```bash
evernote2md "Work.enex" ./work-notes
```

### Convert with Yarle

Yarle comes as a desktop app for Mac, Windows and Linux, and as a command-line tool:

```bash
npx -p yarle-evernote-to-md@latest yarle --configFile ./config.json
```

The options sit in that config file. The ones this migration needs are `enexSources` (an absolute path to one `.enex` file, or a folder of them), `outputDir`, `resourcesDir` for attachments, `outputFormat` set to `StandardMD` instead of `ObsidianMD`, and `useHashTags`. `nestedTags` rewrites a tag such as `tag1_sub tag of tag1` as `tag1/sub-tag-of-tag1`. `replacementCharacterMap` swaps characters that are invalid in file names for `_`. The README says that to put the title, created and updated times, tags, source and notebook into the note as metadata, you set up a custom template and point `templateFile` at it; without one, a default template is used. The README is inconsistent about the default attachments folder, `resources` in the sample config and `_resources` in the text, so look at what it produced.

### What Evernote loses

The Yarle README lists what it handles: text, tags, links, code blocks, inline images, attachments and web clips. Neither README promises how tables or complex layouts come out, so open your most heavily formatted notes first. Yarle's README also warns that duplicate note names can make links between notes convert wrongly, and suggests creating a table-of-contents note and exporting it together with the notebook.

## Clean up the folder

Do this before importing, while the folder is small enough to check by eye.

**Rename files.** MiaoYan lists a note by its file name without the extension, so whatever trails the name is the title you will read. If your Notion names end in a 32-character hexadecimal ID, this loop prints the renames it would make. Delete `echo` once the list looks right; `-n` stops `mv` overwriting a file on a name clash:

```bash
for f in *.md; do
  n=$(printf '%s' "$f" | sed -E 's/ [0-9a-f]{32}\.md$/.md/')
  [ "$n" != "$f" ] && echo mv -n "$f" "$n"
done
```


**Collect images in one folder.** Make an `assets` folder next to the notes, move the images in, and edit the links. MiaoYan's preview resolves a path that is not absolute against the note's own folder and decodes percent-encoding, so `![](assets/photo.png)` works, and `%20` in a link finds a folder with a space in its name. A path that starts with `/`, other than `/i/`, is treated as an absolute path on your disk, so `/assets/photo.png` will not find your notes folder. A missing file shows a gray box reading `Image Not Found`. [Markdown images](/blog/markdown-images/) explains the path rules. The `image` and `file` folders from evernote2md can stay where they are; check one link to be sure.

**Turn properties into front matter.** A Notion row's properties and an Evernote note's tags and dates are metadata. Put them in a YAML block at the top of the file:

```markdown
---
title: Q3 plan
tags: [work, planning]
created: 2024-03-02
---
```

MiaoYan hides a block like this in the preview and in exports when the file starts with `---`. MiaoYan V4.9.0 does not turn those tags into a sidebar or filter, so treat the block as data that stays in the file for other tools. [Markdown front matter](/blog/markdown-front-matter/) has the syntax and quoting rules.

## Open the folder in MiaoYan

To make the migrated folder your library, choose MiaoYan > Settings… (Command-comma), click `Change` next to Note Location, and pick the folder. MiaoYan checks it is a writable directory; if not, it shows "Could not use this folder" and keeps the old one. After a valid pick a `Restart` button appears, because the new folder is used from the next launch.

To add the notes to a library you already have, use File > Import. The open panel shows the message "Select Markdown files or folders to import" and accepts several files or folders. The scan goes through folders recursively, keeps `.md`, `.markdown` and `.txt` files, and skips hidden entries and folders named `i`, `files` and `.Trash`. Import copies the note files only, into the main notes folder by file name. It does not copy image folders or recreate the source folder structure. If a name is taken, the copy becomes `Name Copy.md`, then `Name Copy 2.md`. When the notes link to images, copy the image folders by hand, or use Note Location instead so the links stay valid. If nothing matches, a toast says "No Markdown files to import".

The sidebar hides a folder that holds only attachment files, with no notes and no subfolders, and an `assets` folder with no notes directly inside, so an `assets` or `image` folder of pictures will not appear in the list. The files are still on disk. [Local-first Markdown notes](/blog/local-first-markdown-notes/) covers why keeping plain files is worth the cleanup.

## FAQ

### Does Notion's Markdown export include images?

The help page says images and other assets are saved separately, but it states that for HTML and PDF exports, not for Markdown & CSV. Check the unzipped folder.

### Can I export Evernote without the desktop app?

No. Evernote's help page says export is available only in the desktop app for Mac or Windows.
