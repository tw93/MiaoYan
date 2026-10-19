For Markdown on an iPad, pick an app that edits real `.md` files in a folder the Files app can see, and keep that folder in iCloud Drive so your Mac sees the same notes. MiaoYan's iPad app does exactly that: it opens the folder your Mac uses, shows a three-column library, and reads a note first and edits it when you tap the edit button. It is a reader with an editor, not a full writing environment, so check the limits below against how you write.

## What an iPad Markdown setup needs

Four things decide whether it works day to day.

- **Where the files live.** Notes should be ordinary files in a folder, not rows in an app database. Then Files, backups and any other editor can reach them.
- **How you edit.** A hardware keyboard, or the on-screen one with formatting help. Apps differ a lot here.
- **Preview.** Some apps show a styled preview beside the text, some switch between the two.
- **Sync.** Whatever moves the folder to your other devices. For Apple-only setups that is usually iCloud Drive.

The first and last are the ones that bite later. A note stuck in an app's private storage is hard to leave, and a folder that has not finished syncing looks like a missing note.

## MiaoYan on iPad

MiaoYan's site says the same App Store purchase runs on iPhone and iPad and opens the same iCloud Drive folder as your Mac. It is a one-time payment with no subscription or in-app purchases, and the iPhone and iPad apps require iOS or iPadOS 18 or later.

What the iPad app does in version 4.5.0:

- On a wide screen it uses a three-column layout: a sidebar with Notes (recent ones), All Notes, your folders and Trash, a note list, and the note itself.
- A note opens in a reading view. Tap the edit button to type in a Markdown editor and tap "Done" to finish. The editor shows a save state, "Saving" then "Saved".
- Notes, folders, rename, move to folder, pin, share and Trash are in the app. Search looks through titles and note bodies locally.
- Settings has an Appearance section for font and size, and a Library section with "Choose Folder…". Its text says MiaoYan reads and writes Markdown files in the folder and that iCloud Drive or your cloud drive app keeps it in sync with Mac.
- The reader renders tables, footnotes, strikethrough and task lists, highlights code with highlight.js, and draws Mermaid diagrams. `[[Title]]` wikilinks open the target note.

What it does not do in 4.5.0: the iPad app has no keyboard shortcuts of its own, and it has no step that renders LaTeX math, PlantUML or Markmap, so those show as source text in the iPad reader even though the Mac app renders them. If you write formulas on the iPad, check a sample note first. The syntax is covered in the [Markdown cheat sheet](/blog/markdown-cheat-sheet/) and [LaTeX math in Markdown](/blog/latex-math-in-markdown/).

## How the iPad finds your notes

The Mac app reads a folder you choose in Preferences. The iPad app finds the library in one of two ways. On first launch it checks iCloud Drive and, when it is available, uses the app's own iCloud Drive folder, which the app declares as public so it shows in the Files app under the name MiaoYan. Otherwise, or if you want a different folder, you pick one with "Choose folder". The app then reads and writes plain files there.

So the sync path is: the Mac saves a `.md` file in iCloud Drive, iCloud uploads it, the iPad sees the file appear and lists it. MiaoYan has no sync of its own. That is why the folder on the Mac must be the same iCloud Drive folder the iPad opens. The details are in [Sync Markdown notes across devices](/blog/sync-markdown-notes-across-devices/).

One more detail: the iPad app first reads the catalog of notes iCloud reports and then their contents. During a first launch it shows "Found N notes…", and until the files arrive search says how many "iCloud notes still downloading; results will improve as they sync." A list that looks short right after install is usually this, not data loss.

## When a note does not show up on the other device

Work down this list.

1. **Check the Mac saved it.** The Mac app writes the file about a second and a half after you stop typing. Open the folder in Finder and confirm the `.md` file is there.
2. **Check both devices point at the same folder.** On the Mac, Preferences > "Note Location". On the iPad, Settings > Library. A different folder on either side means two separate libraries.
3. **Look for a sync status.** In Settings > Library the iPad app shows Syncing, Synced, Offline or "Sync issue". Offline means the app could not reach its iCloud container, so check that iCloud Drive is on for the iPad.
4. **Wait for the first launch to finish.** The app says "Downloading your iCloud notes. Next launch will be instant." on a large library.
5. **Pull down on the note list** to reload it if a note exists on disk but not in the list.
6. **Open Files.** If the note is in iCloud Drive in Files, the problem is the app. If it is not, the problem is iCloud.

When the same note is edited on two devices, the iPad shows "This note changed elsewhere" with "Reload" and "Keep Mine". Choosing "Keep Mine" saves your text over the other version, so read the other one first if you are unsure. The Mac keeps unsaved text in a hidden `.miaoyan-conflicts` folder when an external change arrives.

## Other iPad Markdown editors

MiaoYan is one choice. These are worth knowing about, from their own pages.

- **iA Writer** writes in plain text with Markdown and lets you switch to a styled Preview. The iPad and iPhone version is a one-time payment, and Mac and Windows have free trials.
- **1Writer** has inline Markdown preview and a full preview, a customizable extra keyboard row, multiple windows and drag and drop, and syncs Dropbox and WebDAV folders and iCloud Drive.
- **Obsidian** on mobile adds an editing toolbar at the bottom and a Quick Action gesture, and its help page says it works similarly to the desktop app.

1Writer is the one of these three that lists Dropbox and WebDAV folders, and Obsidian is the choice if your notes already live in an Obsidian vault. MiaoYan fits when your notes are a folder you share with a Mac and you mostly read and make short edits on the iPad. If you want an overview of the Mac side, see [Choosing a Markdown editor for Mac](/blog/markdown-editor-for-mac/).

## FAQ

### Can I edit the same Markdown files on a Mac and an iPad?

Yes, as long as both open the same iCloud Drive folder. Let the sync finish before you switch devices, and avoid editing one note on both at once.

### Does MiaoYan on iPad have a keyboard shortcut for bold?

Version 4.5.0 of the iPad app has no shortcuts of its own, so type the Markdown markers yourself.

### Does the iPad app need a subscription?

The site says it is a one-time purchase with no subscriptions or in-app purchases, and the same purchase covers Mac, iPhone and iPad.

### Are my notes stored in the app?

No. They are `.md` files in the folder you chose, visible in the Files app.
