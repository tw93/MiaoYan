If Obsidian feels like more tool than your notes need, MiaoYan is a lighter Mac app that opens the same format, a folder of Markdown files. It provides a three-column library, split editor and preview, wikilinks with backlinks, version history and PPT mode, and it deliberately leaves out plugins, a graph view and the extra link syntax Obsidian adds. Plain notes and ordinary `[[Title]]` links move across without conversion, while aliases, heading links and embeds need a small cleanup.

## Why people look for something lighter

Obsidian is a deep tool. Its documentation describes a vault with a hidden `.obsidian` folder that holds hotkeys, themes and community plugins, and a core Graph view plugin that visualizes the relationships between notes. That power is the reason many people use it. It is also why others stop. Every setting, plugin and theme is one more thing to maintain, and a vault can end up depending on plugins that only one app understands.

MiaoYan takes the opposite position. It has no plugin system, and its site comparison notes that it favors a smaller set of built-in writing features and local Markdown files, without an Electron runtime. If you mostly write, link and find notes, fewer parts can mean less friction.

## What MiaoYan has

- **A folder of files.** Notes are `.md`, `.markdown` or `.txt` files in a folder you choose. See [Local-first Markdown notes](/blog/local-first-markdown-notes/).
- **Split editor and preview.** Press Command Backslash to toggle it. MiaoYan keeps Markdown source and preview separate and does not use a WYSIWYG editor.
- **Wikilinks and backlinks.** `[[Title]]` links with a backlinks list in the document properties panel. See [Wikilinks and backlinks](/blog/wikilinks-and-backlinks/).
- **Built-in rendering.** LaTeX math, Mermaid, PlantUML and Markmap diagrams, GitHub-style alerts such as `> [!NOTE]`, task lists, footnotes and tables.
- **Version history.** Snapshots per note, covered in [Markdown note version history](/blog/markdown-note-version-history/).
- **PPT mode.** Turn a note into slides with `---` separators.
- **A command line tool.** `miao` supports list, search, cat, open and new, covered in [Markdown notes from the terminal](/blog/markdown-notes-from-terminal/).
- **iPhone and iPad.** The App Store purchase covers Mac, iPhone and iPad, all opening the same iCloud Drive folder.

## What MiaoYan does not have

Consider these limitations before you migrate.

- **No plugins.** There is no plugin or theme marketplace. Features either ship in the app or do not exist.
- **No graph view.** The Mac app does not include graph visualization. Connections appear as backlinks in a list.
- **Title-only wikilinks.** `[[Note|alias]]`, `[[Note#Heading]]` and block references are not implemented.
- **No embeds.** Obsidian's `![[Note]]` and `![[image.png]]` embeds are not supported in MiaoYan.
- **No Obsidian-specific features that live in plugins or in `.obsidian`.** Anything stored in hotkey, theme or plugin settings stays behind.

If you rely on one of these, MiaoYan is not a drop-in replacement, and staying with Obsidian is the right call. The two can also coexist on one folder, which is covered below.

## Migrating a vault

An Obsidian vault is a folder, so migration mostly means pointing MiaoYan at it. Obsidian's documentation notes that notes are plain text Markdown files in the vault and settings live in `.obsidian`.

1. **Copy first.** Duplicate the vault folder in Finder. Work on the copy until you are satisfied. Notes are files, so this is the whole backup.
2. **Point MiaoYan at it.** Open Preferences with Command comma, click "Change" next to "Note Location", choose the copy, then click "Confirm" when MiaoYan asks to restart.
3. **Check the library.** Folders become sidebar folders and `.md` files become notes. The hidden `.obsidian` folder is ignored, because MiaoYan skips hidden folders.

### What carries over

- Note text, headings, lists, tables, code, task lists and footnotes.
- Plain wikilinks such as `[[Project plan]]`, because MiaoYan links by file name, which is also how Obsidian resolves simple links.
- Leading YAML front matter. MiaoYan hides a leading block between two `---` lines in the rendered output and keeps it in the file. Obsidian stores properties in YAML at the top of the file, so these stay intact.
- Standard Markdown links and images.
- Callouts in the `> [!note]` form. MiaoYan recognizes five markers (`NOTE`, `TIP`, `IMPORTANT`, `WARNING`, `CAUTION`) in upper or lower case. Other Obsidian types such as `[!faq]` are not recognized and render as a plain quote.

### What does not carry over

- **Aliases, heading and block links.** In MiaoYan the whole text between the brackets becomes the title to look up, so the link points at a note that does not exist. Find them with:

```bash
rg -n --glob '*.md' '\[\[[^]]*[|#^]' .
```

  Replace each with a plain title link or a normal Markdown link.
- **Embeds.** Find `![[...]]` with `rg -n --glob '*.md' '!\[\[' .` and replace them with a link or a standard image.
- **Images.** MiaoYan expects images as `![name](/i/name.png)` with the files in an `i/` folder inside the note's folder. Obsidian-style image references need to be converted and the files moved.
- **Plugin content.** Blocks written for community plugins render as ordinary code or text.
- **Notes with the same title in different folders.** In MiaoYan a link to a duplicated title starts a search instead of opening one note, so rename duplicates.
- **Settings.** Hotkeys, themes and plugin choices do not move.

### Keeping both

Because both apps use the same files, you can keep Obsidian for the notes that need plugins and open the same folder in MiaoYan for fast reading and writing. Avoid editing the same note in both at once. If MiaoYan has the note open when another app changes it, MiaoYan reloads from disk and backs up your unsaved text to `.miaoyan-conflicts`, but it is cleaner not to rely on that.

## A fair comparison

| | Obsidian | MiaoYan |
| --- | --- | --- |
| Storage | Folder of Markdown files (vault) | Folder of Markdown files |
| Plugins | Community plugins | None |
| Graph view | Core plugin | Not in the Mac app |
| Link syntax | Wikilinks with aliases, headings, blocks | Wikilinks by title |
| Embeds | `![[note]]`, `![[image.png]]` | Not available |
| Editing | Not compared here | Source editor with split preview |

Obsidian's cells come from its help pages checked on 2026-10-18, MiaoYan's from its README and source. Prices and licensing change, so check each vendor's page rather than a table.

## When to stay with Obsidian

Stay if you use community plugins you cannot replace, if the graph view is central to how you organize notes, if you depend on embeds and block references, or if you work across platforms MiaoYan does not run on. Move if you want a native Mac app that stays out of the way and a library that is only ever files.

The Mac app is open source on [GitHub](https://github.com/tw93/MiaoYan), and the [App Store](https://apps.apple.com/app/id6759252269) version covers Mac, iPhone and iPad with one purchase.

## FAQ

### Can I open my Obsidian vault in MiaoYan without converting it?

Yes, for the notes themselves. The folder opens as is, and the `.obsidian` folder is ignored. Aliases, heading links and embeds will not resolve.

### Will MiaoYan change my vault files?

It saves an opened note when you switch to another note, even without edits. This updates its modification date and stores a non-UTF-8 note as UTF-8, so test on a copy first. It does not touch `.obsidian`, and if a conflict backup is ever needed it writes a hidden `.miaoyan-conflicts` folder in the library root.

### Does MiaoYan have tags or a graph?

Neither feature is present in the app. Notes are organized by folders and found with search, and links are shown as backlinks.

### Can I switch back?

Yes. The notes are still plain Markdown in the same folder.
