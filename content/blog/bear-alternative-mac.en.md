If you want to leave Bear but keep writing Markdown on a Mac, the move is to export your notes as `.md` files and open the folder in an editor that reads plain files. MiaoYan does this: folders are your categories, every note is a file, and an iCloud Drive folder carries the notes to iPhone and iPad. The trade-off is real. Bear organizes with tags across the whole library, and MiaoYan has no tags at all, so a library that lives on `#tags` needs a plan before you move.

## What Bear does well

Bear's own FAQ describes tags as working like hashtags: type `#tag` anywhere in a note, put as many tags on a note as you like, wrap a phrase in pound signs for a multi-word tag (`#vacation plans#`), and nest them with a slash (`#recipes/italian`). Click a tag in the sidebar and you see every note that contains it. That is a different model from folders, because one note can sit under several tags at once.

The editor is built on the CommonMark specification, and its Markdown guide says formatting is displayed while the note stays plain text, with a "Hide Markdown" setting under Settings > General. It runs on Mac and iOS, and Bear Web works in any major browser with the same iCloud credentials.

Sync is a Pro feature. Bear's Pro page lists iCloud sync, note encryption, export to PDF, HTML, DOCX and JPG, themes and OCR search, at $2.99 a month or $29.99 a year with a 7-day trial (page checked on 2026-10-19; prices change, so confirm on Bear's page). The sync page says Bear syncs through CloudKit, not through files in iCloud Drive.

## How Bear stores your notes

Bear keeps notes in a SQLite database on iOS and macOS. On a Mac it sits at `~/Library/Group Containers/9K33E3U3T4.net.shinyfrog.bear/Application Data/database.sqlite`. Bear's own page says it is safe to access the database for reading only, advises most users not to edit it, and asks anyone who does to make a copy and quit Bear first.

That is the main difference from a folder of files. A Bear note is not a file you can see in Finder or search with `grep`. The notes are still yours, but you get them out through Bear's export, not by copying a file.

## Get your notes out of Bear

The free version of Bear exports to Plain Text, Markdown (`.md`), Text Bundle, Bear Note and RTF. HTML, DOCX, PDF, JPEG and ePub need Pro, but you do not need them for this move.

1. In Bear for Mac, click "Notes" in the sidebar and press ⌘A.
2. Choose File > Export notes… (⇧⌘S) and pick Markdown.
3. Save into a new, empty folder, for example `~/Documents/BearExport`.
4. In Bear > Preferences > General, check "Keep tags during export" before you export if you want tags kept in the files.

Bear's export page does not say how attachments are laid out for each format, so open the folder and check a note with an image before you trust it. If images are missing, export a second time in Text Bundle and compare the two.

## Move them into MiaoYan

MiaoYan reads a folder of `.md`, `.markdown` or `.txt` files, so the import is a folder choice.

1. Copy the export folder to where you want the library, for example a `MiaoYan` folder in iCloud Drive.
2. Open Preferences with ⌘, and find "Note Location".
3. Click "Change", choose the folder, and confirm the restart prompt. MiaoYan loads the library at launch, and cancelling the prompt keeps the old folder.

Sub-folders become sidebar folders. Bear had no folders, so your export is probably one flat list. Make a handful of folders by hand and drag notes in, sorted by the thing that used to be your top-level tag. MiaoYan reads relative image paths from the note's folder and saves its own pasted images as `![name](/i/name.png)` in an `i/` folder there, so open a few notes with images after the move and fix any links that do not resolve. The [Obsidian migration post](/blog/obsidian-alternative-mac/) shows the same kind of cleanup with `rg`.

## How MiaoYan's model differs

MiaoYan treats the folder tree as the only structure. A note lives in exactly one folder, its title is the file name, and nothing is stored outside the files except version snapshots in the app's support folder. Links between notes use `[[Title]]` wikilinks with backlinks, covered in [Wikilinks and backlinks](/blog/wikilinks-and-backlinks/). Bear can link notes too, and its export page mentions an "HTML Links" option that turns wiki links into HTML links, so these are worth checking after export.

For the iPhone and iPad, MiaoYan has no account and no sync service of its own. The apps open the same iCloud Drive folder as the Mac, and iCloud moves the files. [Sync Markdown notes across devices](/blog/sync-markdown-notes-across-devices/) covers the failure cases.

## What Bear does better, and what you lose

- **Tags across folders.** MiaoYan has none. You can type `#recipes` as text and search for it, but it is only text.
- **A mobile app built for writing.** Bear has native iPhone and iPad apps, and its FAQ documents iPadOS keyboard shortcuts. MiaoYan's iPhone and iPad app opens a note in a reader first, switches to an editor when you tap the edit button, and has no keyboard shortcuts of its own.
- **Widgets, Apple Watch and Shortcuts.** Bear's FAQ lists these. MiaoYan's pages do not mention them.
- **Export to PDF, DOCX and JPG as Pro features.** MiaoYan has its own PDF route, described in [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/), without DOCX.
- **One note, several places.** A note lives in one folder, so it cannot also sit under a second heading.

What you gain is a library that survives any app. Files open in any editor, a backup is a copy of a folder, and there is no Pro tier gating sync, because the sync is whatever you already use for the folder. MiaoYan also renders LaTeX, Mermaid, PlantUML and Markmap on the Mac, which Bear's Markdown guide does not mention.

## When to stay with Bear

Stay if tags are how you find things, if you capture mostly on an iPhone, or if you like the styled single-pane editor. If you want a folder-based Mac editor, or want to try plain files before deciding, [Choosing a Markdown editor for Mac](/blog/markdown-editor-for-mac/) compares the main options, and [Local-first Markdown notes](/blog/local-first-markdown-notes/) explains why a plain folder is worth the trade.

You can test the move safely: export is non-destructive, so keep Bear installed, export once, open the copy in MiaoYan and use both for a week.

## FAQ

### Can Bear export all notes to Markdown for free?

Yes. The free version exports to Markdown, plain text, Text Bundle, Bear Note and RTF. Select all notes and use File > Export notes… (⇧⌘S).

### Does MiaoYan support Bear's #tags?

No. A `#tag` in a note stays as text. Folders are the only organization, so turn your main tags into folders before or after the move.

### Can I read Bear's database directly?

On a Mac you can open the SQLite file read-only, which Bear says is safe. Export is the supported route, and iOS does not expose the database.

### Will my notes sync to iPhone and iPad after the move?

If the library folder is in iCloud Drive, yes. The MiaoYan apps for iPhone and iPad open the same folder, and iCloud does the syncing.
