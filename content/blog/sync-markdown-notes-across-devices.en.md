MiaoYan does not sync anything itself. It reads and writes one folder of Markdown files, and whatever keeps that folder identical on your devices does the syncing: iCloud Drive, a Nutstore (坚果云) folder, Dropbox, or a git repository. Pick one tool per folder, set the folder as the Note Location in Preferences, and let the file sync run. The only real risk is editing the same note on two devices before changes sync, which produces a conflict copy.

## Choosing a sync method

| Method | Best for | Watch out for |
| --- | --- | --- |
| iCloud Drive | Mac, iPhone and iPad, no setup beyond signing in | Files "optimized" away from the Mac need to be downloaded before they can be read |
| Nutstore (坚果云) | Users in mainland China who want a folder synced by its desktop client | The folder must be the local one the desktop client syncs, not the web interface |
| Dropbox | Mixed Mac, Windows and Linux machines | Conflicts show up as "conflicted copy" files |
| git | People who want history and are fine syncing by hand | Nothing is automatic: you commit, pull and push yourself |

If you use Apple devices only, iCloud Drive is the shortest path. MiaoYan's App Store version is built around it: with no folder chosen and iCloud available, the app uses a folder in iCloud Drive, and the iPhone and iPad apps open the same one.

## How file sync actually works

Cloud drives sync files, not notes. Each service watches the folder, notices that a file's contents or modification time changed, and uploads the whole file. Other devices download the new version and replace the old one. The service has no idea that the file is Markdown, so it cannot merge two edits the way a text-aware tool would.

That is where conflicts come from. Suppose you edit `Ideas.md` on the Mac while the iPhone is offline, and also edit it on the iPhone. When the iPhone reconnects, the service now holds two versions of one file with no common record of who changed what. It keeps both. Dropbox's help page describes this as a conflicted copy created when "multiple people edit the same file at the same time" or when someone edits a file offline while another person edits it. It names the copy with the editor's username, the words "conflicted copy" and the date.

One situation looks like a conflict but is not. A file that is still downloading may be read as missing by an editor, which is why the notes folder needs to be available offline. Obsidian's sync guide notes the same issue, warning that files not kept offline can be treated as missing.

## Set the storage path in MiaoYan

1. Create a folder named `MiaoYan` (any name works) inside the synced location: iCloud Drive, the local folder your Nutstore desktop client syncs, your Dropbox folder, or the working copy of a git repository.
2. Open Preferences with ⌘, and find "Note Location".
3. Click "Change" and choose the folder.
4. Confirm the restart prompt that appears. MiaoYan loads its library at launch, so the new folder takes effect on the next start, and cancelling the prompt keeps the old folder.

Before it accepts the folder, MiaoYan checks that it can read and write there. If the check fails, it keeps your current location and shows a message such as "MiaoYan cannot read this folder. If this is a cloud drive, open the provider app and make sure the folder is exposed in Finder." The Chinese README adds that this is not reported as a MiaoYan sync failure, because the problem is the folder or the cloud drive, not the app.

MiaoYan does not sign in to WebDAV or cloud-drive accounts. It only sees the folder.

## iPhone and iPad

On iPhone, pick the same cloud-drive folder in the system Files app. The README notes the caveat: if a provider does not offer a writable folder in Files, use iCloud Drive, or make the folder available offline in that provider's own app first. In practice, iCloud Drive is the reliable choice for the iPhone and iPad apps, while third-party drives depend on whether their Files integration provides writable, offline access.

## What each service documents

- **iCloud Drive.** Apple's guide describes Download Now to fetch an item for offline use, and Keep Downloaded to keep it on the Mac even when Optimize Mac Storage moves older documents to iCloud. For a notes folder, use Keep Downloaded so search and the editor never encounter a placeholder file.
- **Obsidian's sync notes.** Obsidian's documentation notes that iCloud can sync vaults between Apple devices, warns that iCloud Drive on Windows may cause duplication or corruption, and says files must stay available offline or may be treated as missing. The same applies to any folder of notes, whichever app opens it.
- **Git.** Git records snapshots when you commit, and Obsidian's guide notes that syncing is not automatic: you push and pull yourself. That is a feature if you want deliberate history and a drawback if you want it to just work.

## What goes wrong and how to recover

**You get two copies of a note.** Open both, copy what you need into the one you want to keep, and delete the other. A sync service names the extra file, for example with "conflicted copy" for Dropbox, so searching for that text finds them.

**MiaoYan says an external change was detected.** If a sync brings in a newer version of a note you have open, MiaoYan reloads it from disk. When your unsaved editor text differs, it first saves your text into a hidden `.miaoyan-conflicts` folder at the root of the library and shows "External change detected. Local copy backed up~". The backups keep at least the 100 most recent files and anything younger than 30 days. Check that folder before assuming text was lost.

**A note looks empty.** The file may not have downloaded yet. Open the folder in Finder, make the files available offline, and let the sync finish.

**Version history is not in the cloud.** MiaoYan keeps its snapshots in its own support folder rather than in your notes folder, so they do not sync. See [Markdown note version history](/blog/markdown-note-version-history/).

**Using git with MiaoYan.** Commit from the library folder. Add `.miaoyan-conflicts/` to `.gitignore` so backup files are not committed. Do not run git and a cloud drive on the same folder unless you are comfortable with both touching the same files.

## Habits that prevent most conflicts

- Let the sync finish before you switch devices. Most clients show sync progress.
- Do not edit the same note on two devices in the same minute.
- Keep one sync mechanism per folder.
- Keep a second copy outside the sync tool, such as a Time Machine backup, because sync copies mistakes as faithfully as it copies work.

For the bigger picture of why a plain folder is worth this trouble, read [Local-first Markdown notes](/blog/local-first-markdown-notes/). If you want to script against the synced folder, see [Markdown notes from the terminal](/blog/markdown-notes-from-terminal/).

MiaoYan for Mac is open source on [GitHub](https://github.com/tw93/MiaoYan), and the [App Store](https://apps.apple.com/app/id6759252269) version covers Mac, iPhone and iPad with one purchase.

## FAQ

### Does MiaoYan have its own sync service?

No. It reads and writes the folder you choose, and iCloud Drive, Nutstore, Dropbox or another client syncs that folder.

### Can I use Nutstore with MiaoYan?

Yes. Create a folder inside the local folder that the Nutstore desktop client syncs, and choose it as the Note Location. MiaoYan does not talk to Nutstore or WebDAV directly.

### Which option is best for iPhone?

iCloud Drive, because the README says third-party providers may not offer a writable folder in the Files app.

### Why did my folder change not take effect?

The library opens at launch. After you choose a new Note Location, restart MiaoYan.
