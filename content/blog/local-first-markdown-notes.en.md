Keeping notes as plain Markdown files in a folder you own means any editor can open them, any backup tool can copy them, and no company's server decides whether you can read your own writing. The price is that you give up things a hosted app does for you: server-side search, automatic merging of conflicting edits, and tidy handling of attachments. For most people who write a lot of text and want it to outlive any single app, that trade is worth making.

## What "local-first" means for a notes folder

A local-first notes app treats the files on your disk as the real copy. There is no account and no database you cannot open. In MiaoYan the library is a folder you pick, and every note is a file in it with the extension `.md`, `.markdown` or `.txt`. The note title is the file name without the extension, so `Project plan.md` shows up as "Project plan".

That is the whole format. Obsidian takes the same view: its documentation says notes are plain text Markdown files in a vault, which is "a folder on your local file system, including any subfolders". Because the format is shared, a folder written in one app opens in another, and `grep`, `git` and Spotlight work on it without any export step.

## What you gain

**Portability.** Moving to a different editor is a matter of pointing it at the same folder. Nothing is trapped in a proprietary container, so the cost of changing your mind is close to zero.

**Tools.** Anything that reads text can read your notes. You can search with `rg`, script a weekly review, or hand the folder to a coding agent. MiaoYan also ships a `miao` command line tool for this, covered in [Markdown notes from the terminal](/blog/markdown-notes-from-terminal/).

**Backups.** A folder of small text files is the easiest thing to back up. Time Machine, a cloud drive or a git repository all treat it as ordinary files, and a restored backup is immediately usable.

**No lock-in, no data collection.** MiaoYan reads and writes your notes in the folder you choose. Its README states that notes are Markdown files in a folder you choose, with no data collection.

## What it costs

Consider these tradeoffs before committing.

**No server-side search or indexing.** Search happens on your devices. MiaoYan searches note titles and note bodies inside the library when you type in the search field. There is no web search and no query across machines.

**Sync is delegated.** The app does not sync for you. A cloud drive does, and cloud drives know nothing about Markdown, so two edits to the same file on two devices become a conflict copy rather than a merged note. The details are in [Sync Markdown notes across devices](/blog/sync-markdown-notes-across-devices/).

**Attachments are just files.** Images and PDFs sit next to your notes, and a link to them is only a path. Move a note without its attachment folder and the image breaks.

**History is your problem.** A hosted app often keeps a full revision log. With plain files you assemble that from the app's own snapshots, Time Machine and optionally git, as described in [Markdown note version history](/blog/markdown-note-version-history/).

## A folder structure that holds up

Notes libraries rarely fail because of the app. They fail because the folder turns into a junk drawer. A structure that tends to survive:

```text
MiaoYan/
  Inbox/
  Projects/
    Website redesign/
      i/
  Reference/
  Journal/
  Archive/
```

A few rules keep it working:

- **Few top-level folders, named by purpose.** Group by what you do with a note (act on it, look it up, archive it), not by topic, because topics overlap and purposes rarely do.
- **Titles that you can type from memory.** Because the file name is the title, and wikilinks point at titles, a clear name is also your link target. See [Wikilinks and backlinks in Markdown notes](/blog/wikilinks-and-backlinks/).
- **Avoid duplicate titles across folders.** Two files called `Meeting notes.md` in different folders are legal, but a title-based link cannot tell them apart.
- **Keep attachments beside the notes.** MiaoYan stores inline images in an `i/` subfolder and other files in `files/`, inside the note's folder.
- **Keep it shallow.** Subfolders work, but two levels are usually enough when search is one keystroke away.

## How MiaoYan reads a folder

This mechanism explains most surprises.

You choose the folder in Preferences (⌘,) under "Note Location" with the "Change" button. MiaoYan checks that the folder is a writable directory before switching and keeps the old location if the check fails. The new folder takes effect after a restart. MiaoYan prompts you to restart, and keeps the old location if you cancel.

Once the folder is open, MiaoYan lists each subfolder as a folder in the sidebar and each `.md`, `.markdown` or `.txt` file as a note. It skips hidden folders (names starting with a dot), the attachment folders `i` and `files`, folders named `assets`, and folders that contain only attachments. Trashed notes go to the system Trash, or to a `Trash` folder inside the library on a volume that has none.

A file watcher based on macOS file system events keeps the app in step with the disk. When another program changes a note that is open in the editor, MiaoYan reloads the file from disk. If your unsaved editor text differs from what is now on disk, it first writes your version to a hidden `.miaoyan-conflicts` folder in the library root and shows "External change detected. Local copy backed up~". Those backups are kept for 30 days, with at least the 100 most recent preserved.

Local images use the form `![name](/i/name.png)`, which MiaoYan resolves against the note's own folder. That convention is specific to MiaoYan, so if you open the same folder in a tool that expects relative paths, check that images still show.

## What goes wrong, and how to check

- **A note is missing from the list.** Confirm the extension is `.md`, `.markdown` or `.txt` and the folder is not hidden or named `i`, `files` or `assets`.
- **The folder is rejected.** Cloud-drive folders sometimes are not exposed as real folders. MiaoYan's message says to open the provider app and make sure the folder is visible in Finder, or to enable offline access.
- **Two copies of one note.** This is nearly always a sync conflict. Look for a second file with a suffix added by the sync service.
- **You edit in two apps at once.** MiaoYan will reload from disk and back up your unsaved text, but the safest habit is one editor at a time.

A quick sanity check after any move: open the folder in Finder, confirm the files are where you expect, then search for a phrase you know is in an old note.

## When this is not the right choice

If you need real-time collaboration with other people, shared databases, or web clipping into a hosted workspace, a plain folder is the wrong tool. If you want to publish a site from the same files, a plain folder is a good start, but you will need a static site generator.

MiaoYan is a native Mac app for exactly this folder-of-Markdown workflow, with split editing and preview, wikilinks and version history built in. The source is on [GitHub](https://github.com/tw93/MiaoYan), and the [App Store](https://apps.apple.com/app/id6759252269) version covers Mac, iPhone and iPad with one purchase. If you are coming from Obsidian, read [an Obsidian alternative for Mac](/blog/obsidian-alternative-mac/) first.

## FAQ

### Can I use a folder that already contains Markdown files?

Yes. Point Note Location at it. Existing `.md`, `.markdown` and `.txt` files appear as notes, and their folders appear in the sidebar.

### Does MiaoYan store my notes in a database?

The notes themselves are files in your folder. The app keeps separate version snapshots in its own support folder, not inside your notes folder.

### Which file extensions does MiaoYan open?

`md`, `markdown` and `txt`, per the app's list of allowed extensions.

### Is it safe to rename or move files in Finder?

Yes, the watcher picks up the change. Remember that the file name is the note title, so wikilinks that used the old name will no longer resolve.
