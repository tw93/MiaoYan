Obsidian keeps your notes as Markdown files in a folder on your own disk, and Notion keeps them as blocks in a cloud workspace you open through its apps. Choose Notion when the work is shared: team wikis, project databases, pages you send to other people. Choose Obsidian when the notes are yours and you want them as files, with plugins and links between notes. The decision mostly comes down to where the data lives, because offline use, sync cost and lock-in all follow from it.

## Where the data lives

Obsidian's help says it stores notes as Markdown-formatted plain text files in a vault, which is a local folder that can contain subfolders. Because they are ordinary files, other editors and file managers can open them, and Obsidian refreshes the vault when files change outside the app. Each vault also has a hidden `.obsidian` folder holding settings such as hotkeys, themes and community plugins.

Notion is a hosted workspace. A page is a set of blocks, and a database is a collection of pages with properties, shown through views. You work with them in Notion's desktop, mobile and web apps, and the export options exist to get a copy out, not to be the working format. Notion's help also says you cannot restore a workspace by re-uploading an export.

That one difference explains most of the rest of this comparison. A folder of files can be searched with `rg`, backed up with Time Machine and read in any editor. A workspace gives you things files do not: live editing by several people, permissions, and database views that every member sees.

## Offline use and speed

Obsidian notes are local files, so they are available without a connection. Obsidian also keeps a metadata cache in IndexedDB that powers Graph view and Outline view, and you can rebuild it in settings if it drifts from the files. Neither company publishes speed figures, so the useful difference is structural: Obsidian reads files from disk, while Notion is built around a server copy.

Notion's pricing page lists offline behavior by plan. On Free you can choose pages to download. On Plus, Business and Enterprise, Recents and Favorites are downloaded automatically. If you need every note readable on a plane without having prepared anything, a local vault is the safer design.

## Sync and price

As of November 2026, Obsidian's app is described on its pricing page as free without limits and with no sign-up required. Paid add-ons are optional:

| Obsidian item | Price (USD) |
| --- | --- |
| Sync | $5 per user per month billed monthly, $4 billed annually |
| Publish | $10 per site per month billed monthly, $8 billed annually |
| Catalyst | $25 one time |
| Commercial license | $50 per user per year |

Sync includes end-to-end encryption, version history and collaboration on shared vaults. The pricing page also says you are not required to pay for a commercial license. Because the vault is a folder, you can sync it with a cloud drive instead, but Obsidian's help warns that Dropbox, Google Drive and OneDrive can conflict with Sync and says to back up your files to avoid sync conflicts. Use one sync method per vault. The same trade-offs apply to any notes folder, and [Sync Markdown notes across devices](/blog/sync-markdown-notes-across-devices/) goes through them.

Notion's pricing is per member per month. As of November 2026, its pricing page lists Free at $0, Plus at $10 billed annually or $12 billed monthly, Business at $20 billed annually or $24 billed monthly, and Enterprise at custom pricing, all in USD. Page history is 7 days on Free, 30 on Plus and 90 on Business. File uploads are up to 5 MB per file on Free and up to 5 GB on paid plans. Business adds SAML SSO, granular database permissions and private teamspaces. A Free workspace with several members has a limit on blocks, which the page does not quantify; a solo Free workspace has unlimited pages and blocks.

## Collaboration and sharing

This is where Notion is simply stronger. Its tiers revolve around teamspaces, guests, permissions and collaborative blocks. The pricing page lists an external guest limit of 10 without clearly assigning it to a plan, so check which plan you need before inviting clients.

Obsidian can do shared vaults through Sync, and Publish puts notes on the web as a site, with a customizable theme, graph and full-text search. That covers a small group working on the same set of notes or a public notebook. It is not a team wiki with page-level permissions, and the pricing page gives no guest limits or storage figures for it.

## Databases and plugins

Notion's databases are built in: multiple views over the same pages, properties, relations and formulas. For project trackers, content calendars and CRMs, nothing in a plain notes folder matches that without extra work.

Obsidian answers with plugins. Its help lists 29 core plugins, including Bases, which creates database-like views of your notes. Bases stores no separate data: everything stays in your Markdown files and their properties, and a base can be saved as a `.base` file or embedded in a note. The layouts are table, list, cards, kanban and map, and formulas can calculate from other properties. Community plugins can add more layouts and cover what the core set lacks. The cost is that plugins and themes live in `.obsidian`, so a vault can come to depend on setup that only Obsidian understands.

Graph view is a core Obsidian feature too, and it visualizes relationships between notes.

## Export and lock-in

Obsidian has little to export, since the vault is already the export. Moving away means pointing another app at the folder; [Local-first Markdown notes](/blog/local-first-markdown-notes/) covers what that format gives you and costs you.

Notion's help describes three export formats. PDF works for any page or database. HTML produces a zip with a page per file, subpages in their own folders and assets saved separately. Markdown and CSV turns ordinary pages into Markdown and databases into CSV files. Details that matter:

- Callout blocks are exported as HTML in the Markdown output, because there is no Markdown equivalent.
- Exporting a database covers only the current view or the default view, not all views at once, and form views cannot be exported.
- Relation properties become plain-text URLs in CSV, and that CSV cannot be imported back to restore the relations.
- Subpages are nested in folders, and long paths can break extraction on Windows.
- A workspace export can take up to 30 hours, and the download link expires after 7 days.

Obsidian's own Notion import guide goes further. It recommends the Importer plugin with a Notion integration token, which turns each database into a folder with a `.base` file, and for the file route it says to export HTML and avoid Markdown export because it omits important data. Even then the API import brings over only board views, drops their filters and sorts, and skips linked data sources. In short, the text of your pages leaves Notion easily, while the database structure leaves only partly.

## Mobile apps

Obsidian has mobile apps for iOS and iPadOS and for Android, with a customizable toolbar at the bottom of the screen while you edit and a quick action you trigger by pulling down from the top. Notion has desktop, mobile and web apps. Editing quality on a phone is best judged by trying both with your own notes.

## When you need neither

If what you actually do is write notes and find them again, both tools are more than the job needs, and a plain-Markdown folder app is enough. [MiaoYan](https://github.com/tw93/MiaoYan) is a native Mac app of that kind. Notes are `.md`, `.markdown` or `.txt` files in a folder you choose, with a split editor and preview, wikilinks with backlinks, version history, and LaTeX, Mermaid, PlantUML and Markmap rendering. It has no plugins, no graph view and no databases. The Mac source is MIT-licensed on GitHub, and the [App Store](https://apps.apple.com/app/id6759252269) version covers Mac, iPhone and iPad with one purchase. If you already use Obsidian and want something lighter on the same folder, [Obsidian alternative for Mac](/blog/obsidian-alternative-mac/) lists what carries over.

## FAQ

### Is Obsidian free to use?

Its pricing page says the app is free without limits and needs no sign-up. Sync, Publish and the commercial license are paid, and as of November 2026 the commercial license is not required.

### Can I move from Notion to Obsidian?

Yes. Use the Importer plugin; Obsidian recommends the API route with an integration token because it keeps databases as Bases, and recommends HTML over Markdown for the file route.

### Does Notion work offline?

Partly. Free workspaces can choose pages to download, and paid plans download Recents and Favorites automatically.

### Which is better for a team?

Notion, for shared pages, permissions and databases. Obsidian Sync with a shared vault suits a small group on one set of notes.
