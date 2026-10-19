On macOS Tahoe and later, Apple Notes can save a note as a Markdown file. Open the note, choose File, then Export To, and pick Markdown. Apple's archive article for iCloud data, published 14 September 2026, says that menu may read Export To or Export as, and that on macOS Sequoia and earlier the File menu only offers Export as PDF. The `.md` file is plain text. MiaoYan does not open the Notes database. It lists `.md`, `.markdown` and `.txt` files in a folder you pick, and the preview shows only the syntax that is actually in those files.

## Export a note on macOS Tahoe

Apple announced this with macOS Tahoe 26. The June 2025 newsroom post says Notes adds the ability to import and export a note into a markdown file, and the September 2025 feature list describes it as saving notes as Markdown files, or importing Markdown formatted files.

The current Notes User Guide on the Mac gives the steps.

1. Open Notes.
2. Click the note you want to export.
3. Choose File > Export To, then choose Markdown. If the menu reads Export as instead, that is the other label in Apple's archive article. Choose Markdown there.
4. Type a name if you want a different file name, and add Finder tags if you want them searchable in Finder.
5. Click Save.

The same guide has a second path for a fragment of the note. Select the text in the note body, then choose Edit > Copy as Markdown, and paste it into a new `.md` file. Pasting Markdown back into Notes turns it into formatted headings, lists, and similar rich text. That direction is useful when you are checking a file you already wrote.

On iPhone, the current user guide says to open the note, tap the share button, then tap Export as Markdown. If that option is missing, tap the View More button first, then choose how to send or save the note. The iOS 18 edition of that page has PDF, Pages, and print, and it stops there. Importing a `.md` file into Notes, the other direction, is documented for macOS Tahoe 26, iOS 26, and iPadOS 26 and later. On the Mac the menu is File > Import Markdown, and the notes land in a folder named Imported Notes.

The export steps describe one note. They do not describe a command that exports a Notes folder. Import is the place Apple documents a folder: File > Import to Notes can take a folder, and Preserve folder structure on import keeps that layout. The checkbox sits behind Options, or Show Options, when it is hidden. For export, you pick the destination yourself, so the folder the `.md` file lands in is the one you chose in the save dialog.

## What Sequoia and earlier can do

The Notes User Guide for macOS 15 says you can export a note as a PDF with File > Export as PDF, or open it in Pages with File > Open in Pages. The Pages document keeps formatting such as bullets, indentation, and bold text, and it is a separate copy. Changes in Notes do not flow back to that Pages file. That guide's export page has PDF and Pages, and no Markdown command.

A short note is often faster to write again in Markdown than to push through a converter. When you want the drawings, scans, tables, and photos as files, Obsidian's Importer plugin documents a different route, and it does not use Apple's Markdown menu. It reads the Notes data on macOS. In Obsidian, open Settings, install Importer from Community Plugins, enable it, open it, set File format to Apple Notes, and choose Import. The open panel is titled Select the "group.com.apple.notes" folder to allow Obsidian to read Apple Notes data. Review the generated template and the preview, then select Import again. Obsidian's help says this covers tables, images, drawings, scans, PDFs, and links introduced in iOS 17. Locked notes are skipped until you unlock them, because Apple encrypts them. Scans come out as uncropped images, cropped images, or PDFs, depending on which system created or edited them. The plugin runs on macOS, and the iOS app does not have it yet. The folder it writes is ordinary Markdown, which is what you then point MiaoYan at. What happens to Obsidian-only syntax after that is covered in [an Obsidian alternative for Mac](/blog/obsidian-alternative-mac/).

On iPhone, Open in Pages shows which objects are fragile even when Markdown is available. The current iPhone guide says you cannot edit drawings in Pages, scans and PDFs show up as thumbnails, and tags, mentions, checklists, and links to other notes are not active items there. A PDF export uses the note's current attachment view, and a multipage PDF or scan contributes only its first page. That is a description of Pages and PDF, not a Markdown specification. It is still the reason a text export has to flatten or drop some of those objects.

## Why the preview follows the file

Notes stores a rich-text note. Markdown is a text file whose meaning comes from characters such as `#`, `-`, and `|`. Apple's export pages name the command and the file type. They do not publish a map of what a checklist, a table, an attachment, or a drawing becomes. Open the `.md` file as text and read it.

MiaoYan, at the V4.5.0 release this article is based on, parses that text with cmark-gfm. The extensions it turns on are `table`, `footnotes`, `strikethrough`, and `tasklist`. A checklist displays as a checkbox when the line is a task item, written `- [ ]` for an open item or `- [x]` for a done one. A grid displays as a table when the file contains a GFM table, with a header row and a divider row. The syntax, including the divider mistakes that leave a table as plain text, is in the [Markdown cheat sheet](/blog/markdown-cheat-sheet/). A drawing, a scan, or a PDF shows up when the export wrote a file and the note links to it. If the `.md` file has a sentence where the drawing was, the preview has nothing else to draw.

Images are the part that usually needs a path fix. When MiaoYan saves an image you paste, it writes the file into an `i` directory in the folder that contains the note, and inserts a link of the form `![](/i/filename)`. Other files go under `files` and use a `/files/` prefix. The preview resolves `/i/...` against that same folder. A relative path with no leading slash, such as `attachments/photo.png`, is resolved against that folder too. A path that starts with `/` and is not `/i/` is treated as an absolute path on disk, so an image link `/files/photo.png` looks for a file at `/files/photo.png` in the preview, rather than inside your notes folder.

GitHub reads the same characters differently. Its documentation says a link is relative to the current file, and a link that starts with `/` is relative to the repository root. A MiaoYan `/i/photo.png` link finds the image beside the note in MiaoYan. On GitHub it looks for `i/photo.png` at the root of the repository. If these notes will also be read on GitHub, a relative link such as `i/photo.png` or `attachments/photo.png` points at the same file in both, as long as the image sits where that path says, next to the note.

## Put the files in a folder MiaoYan opens

If you already keep notes in a folder, as described in [local-first Markdown notes](/blog/local-first-markdown-notes/), copy the exported `.md` files into it, and copy the image files so each link still names a real file. MiaoYan watches the folder with macOS file system events and adds a new `.md`, `.markdown`, or `.txt` file to the list. That copy does not need a restart.

If this export should be the library, set it as the note location. Choose MiaoYan > Preferences… (Command-,), stay on General, and click Change next to Note Location. Pick the folder. MiaoYan checks that it is a writable directory. When the check fails, the alert title is "Could not use this folder", and the old location stays. The message under that title says whether the folder could not be read or written, and for a cloud drive it suggests opening the provider app to make sure the folder is exposed in Finder, or enabling offline access. After a valid choice, MiaoYan asks you to restart with "Restart to MiaoYan to take effect". Confirm restarts the app. Cancel puts the previous location back. Syncing that folder with iCloud Drive or another service is a separate decision, covered in [syncing Markdown notes across devices](/blog/sync-markdown-notes-across-devices/).

A layout that matches the images MiaoYan writes itself looks like this:

```text
Inbox/
  Meeting notes.md
  i/
    photo.png
```

The note then contains `![photo](/i/photo.png)`. The sidebar skips folders named `i`, `files`, `assets`, `.cache`, and `.Trash`. It also hides a folder that holds only attachment files, with no notes and no subfolders. Those files stay on disk. If the export arrived as a Markdown file plus a folder of pictures, and the pictures are absent from the sidebar, that rule is what hid the folder.

The title in the list is the file name without the extension. Rename the file in Finder when the save dialog left a name you do not want. The note you open is that file.

## Check what came across

Open the `.md` file in any text editor before you judge the preview. Search for `![` to see image links, for `- [` to see whether a checklist became a task list, and for a row of pipes and dashes to see whether a table became a GFM table. When those strings are absent, the preview has no checkbox, table, or picture to build.

Then confirm the files. In MiaoYan, Reveal in Finder (Option-Command-R) shows the note file. In Finder, the image named in the link should sit at that path relative to the note's folder, or under `i` if you rewrote the link to `/i/`. Toggle Preview with Command-3. A missing local image is replaced in the preview by a small box whose text reads "Image Not Found". Toggle Split View with Command-backslash when you want the source and the preview together.

A note missing from the list is usually a file the app did not treat as a note. The extension has to be `md`, `markdown`, or `txt`, matched in that lowercase form, so `.MD` is outside the list. The file has to be under 100,000,000 bytes, and its type has to be text or Markdown. Hidden files are skipped, and so are files inside `i`, `files`, or `assets`. If you changed Note Location and then clicked Cancel, the app is still reading the previous folder.

## When a text file is the wrong copy

A sketch, a marked-up PDF, or a scan you still need as a document fits a PDF better than a text file. Apple's PDF export is the documented visual copy, with the first-page limit on iPhone for a multipage PDF or scan. Obsidian's importer is the documented way, on a Mac, to pull tables, images, drawings, scans, and PDFs out of the Notes store in one pass. MiaoYan is where you open the resulting folder when you want to keep editing those files as Markdown. A drawing that the `.md` file does not link to an image stays absent in the preview.

## FAQ

### Can one command export a whole Notes folder?

The Mac user guide describes clicking one note and choosing File > Export To. Import is the command that can take a folder and keep its structure. A library-wide conversion on the Mac is what Obsidian's Importer documents, by reading the Notes data folder.

### Does a checked item stay checked?

It stays checked when the exported line is `- [x]`. An open item is `- [ ]`. A circle character or a plain sentence stays plain text in the preview. The cheat sheet covers how a click in MiaoYan's preview writes the checkbox back into the file.

### Why does the same image link work in one app and miss in the other?

`/i/photo.png` points at the `i` folder beside the note in MiaoYan. On GitHub, a link that starts with `/` points at the repository root, which is a different directory unless the notes folder is the root of the repo. A relative path such as `i/photo.png` or `attachments/photo.png` names the same file in both when the image sits at that path next to the note.

### Does copying files in require a restart?

Copying into the folder that is already the note location does not. The file watcher imports the new note. Restart belongs to a change of Note Location, and Cancel on that prompt leaves the old folder in place.
