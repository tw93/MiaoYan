MiaoYan keeps up to 20 earlier versions of each note, saved automatically while you edit, and you can browse and restore them with Command Shift H. The snapshots live in the app's own support folder, not in your notes folder, so they are a safety net on one Mac and do not travel with your files. For real protection, pair them with Time Machine for whole-disk backups and optionally git for a history you control.

## Open and restore a version

1. Select a note and press Command Shift H, or use the "Version History" item in the note menu.
2. The window lists "Current Version" at the top, then saved versions with their time and a relative description such as "2 hours ago". Click one to preview its text.
3. Click "Restore to This Version". MiaoYan replaces the note's text with that version and shows a confirmation, "Restored to version from" followed by that version's time.

If the note has no snapshots yet, the window says "No Version History" and explains that "Versions are saved automatically every 5 minutes while editing".

Restoring is itself recoverable. Before it replaces the text, MiaoYan saves your current text as a new snapshot, so your pre-restore text appears in the same list as a new snapshot and you can go back.

## How it actually works

This is read from the app's source, so it describes behavior rather than promises.

**When a snapshot is taken.** A snapshot is considered whenever the note is written to disk, which happens after a short pause in typing. A new one is saved only if at least five minutes have passed since the previous snapshot of that note. Two events skip the five-minute wait: switching to another note (the one you leave is saved as a snapshot) and restoring a version (the current text is saved as a snapshot first). Opening the history window also tries a save, but a normal, throttled one that respects the interval.

**What is skipped.** Empty or whitespace-only notes are not saved. A snapshot is also skipped when it matches the newest saved version after comparing line by line with surrounding whitespace trimmed and blank lines removed, so a pure spacing change does not create an entry.

**Where files go.** Each note gets its own folder under `Library/Application Support/com.tw93.miaoyan/Versions/`, named with the note's file name plus a hash of its full path. Inside are plain `.md` files named by their UTC timestamp, for example `2026-10-18T15-42-07Z.md`. They are ordinary text, so you can open them in any editor. The history window shows the date in your local time.

**How many.** At most 20 per note. When a new one is saved and the folder holds more than 20, the oldest are deleted.

**Renames, moves and deletions.** Because versions are filed by path, renaming a note, moving it to another folder or sending it to the Trash gives it a new path, and its earlier history stays filed under the old one. The history window then starts again from the new path.

**The five-minute timer is per session.** The record of when the last snapshot happened lives in memory, so after you quit and reopen the app, the first save of a note can create a snapshot straight away, provided the text differs from the newest saved version.

## What this covers and what it does not

| | MiaoYan version history | Time Machine | git |
| --- | --- | --- | --- |
| Granularity | About every 5 minutes while editing, plus on note switch | Hourly, daily, weekly backups | Whenever you commit |
| Depth | 20 versions per note | Not stated on Apple's page | As many commits as you make |
| Where it lives | App support folder on this Mac | Backup disk, plus local snapshots | The repository |
| Syncs to other devices | No | No | Yes, by push and pull |
| Covers attachments | No, note text only | Yes, files on the disk | Yes, files you add |
| Survives losing the Mac | No | Yes, if the disk is separate | Yes, with a remote |

Apple's documentation says Time Machine backs up files that were not part of the macOS installation and performs hourly, daily and weekly backups once it is on. On APFS disks it also keeps local snapshots, hourly, for up to 24 hours or until the disk needs the space. Apple recommends a backup location other than the internal disk, such as an external drive or network disk.

Git's own documentation describes each commit as a snapshot of your project that you can revert to or compare with later. That is exactly the property a note history needs, but nothing is recorded until you commit.

What MiaoYan's history does not cover:

- **Anything older than 20 versions.** With five minutes between snapshots, 20 versions reach back about 100 minutes of continuous editing, longer if you edit in bursts, so earlier text drops off the list.
- **Other devices.** The snapshots are not in the notes folder, so a sync service does not carry them. Snapshots taken on one device stay on that device. See [Sync Markdown notes across devices](/blog/sync-markdown-notes-across-devices/).
- **Attachments.** Images in `i/` are not versioned.
- **External overwrites.** If another tool or a sync conflict replaces a note, MiaoYan writes your unsaved editor text to a hidden `.miaoyan-conflicts` folder in the library root, which is a separate safety net, kept for the 100 newest files and anything under 30 days.

## A practical setup

1. Leave MiaoYan's history on. It needs no configuration.
2. Turn on Time Machine with an external disk. It protects the notes folder and the snapshots together.
3. For notes you care about long term, add git. Run `git init` in the library, commit when you finish a piece of work, and add `.miaoyan-conflicts/` to `.gitignore`. Pushing to a private remote also gives you an offsite copy.
4. If you use a cloud drive for sync, remember it is not a backup. Deleting or corrupting a file propagates to every device. See [Local-first Markdown notes](/blog/local-first-markdown-notes/).

## What goes wrong and how to check

- **The window says "No Version History".** The note is new, empty, or has not been saved twice with different text. Edit it, wait, switch to another note and come back.
- **A version you expected is missing.** The newest 20 are kept, and near-identical saves are skipped. Check whether the text differs only by spacing.
- **Restore did not seem to change the file.** The text is replaced in the editor and written to disk after the usual short delay. Re-open the note to confirm.
- **You moved the library folder.** Snapshots are keyed by the note's full path. If you relocate the whole library in Finder, or rename or move a note, the paths change and the old history is no longer found for those notes.

MiaoYan is a Mac app for plain Markdown folders. The source is on [GitHub](https://github.com/tw93/MiaoYan), and the [App Store](https://apps.apple.com/app/id6759252269) version covers Mac, iPhone and iPad.

## FAQ

### Does MiaoYan save a version every time I type?

No. At most one every five minutes per note while editing, plus one when you leave the note.

### Can I turn version history off?

There is no setting for it in the app's preferences, so it is always on.

### Are versions stored in my notes folder?

No, in the app's support folder, so they do not appear in Finder next to your notes or sync with them.

### Can I recover a note I deleted?

Notes sent to the Trash can be recovered from the Trash. The history window looks the note up by its path, so the versions from before it was trashed only show again once the note is back at its original path.
