MiaoYan ships a small command-line tool called `miao` that lists, searches, prints, opens and creates notes from the terminal. It has six commands (`open`, `new`, `search`, `list`, `cat`, `update`), and it does not edit existing notes. That is deliberate. Because your notes are plain Markdown files, a script or an AI coding agent can edit them directly, and MiaoYan picks the change up from disk.

## Install and check

The installer is a single script from the MiaoYan repository:

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/MiaoYan/main/scripts/install.sh | bash
```

As with any piped installer, you can download the script first and read it. It does four things: resolves the latest GitHub release tag, downloads the `miaoyan` script from that tag into `~/.local/bin` as `miao`, makes it executable, and creates a `miaoyan` symlink next to it. If `~/.local/bin` is not on your `PATH`, it appends an `export PATH` line to `~/.zshrc`, `~/.bashrc` or `~/.bash_profile` (the first that exists) and asks you to reload the shell.

Check the install with `miao help`, which prints the command list. The CLI is a Bash script and runs only on macOS. The `new` and `open` commands call the macOS `open` command, and the encoding of titles uses `python3`, so both need to be available.

## The commands

```bash
miao list [folder]        # top-level folders, or the Markdown files in a folder
miao search <query>       # search notes in the terminal
miao cat <title|path>     # print a note
miao open <title|path>    # open a note or folder in MiaoYan
miao new <title> [text]   # create a note
miao update               # update the CLI
```

**`miao list`** with no argument prints the top-level folders of your library that contain Markdown notes. `miao list Projects` prints the Markdown files directly inside that folder, as paths relative to the library root. Notes at the root of the library are hidden by default, and the CLI prints a tip to run `miao list .` to show them.

**`miao search`** prints matches as `path:line:text`, relative to the library root. If ripgrep (`rg`) is installed, it is used with a fixed-string match, so special characters in your query are not treated as a pattern. Without ripgrep, the CLI falls back to `grep`. Files under a `Trash` folder are excluded. When nothing matches, it prints "No matches found" to standard error and exits with a non-zero status.

**`miao cat`** prints the whole file, including front matter, to standard output. It accepts a path, a path relative to the library, or a title. A title is matched against file names, without the `.md` extension, and an exact title resolves to the first match found.

**`miao open`** opens a resolved file or folder in MiaoYan. If the argument is not a path, it falls back to the `miaoyan://goto/<title>` address, the same route that wikilinks use (see [Wikilinks and backlinks](/blog/wikilinks-and-backlinks/)).

**`miao new`** builds a `miaoyan://new/` address with the title and the optional text, and hands it to the app, so MiaoYan has to be installed. The text is the second argument, so quote it.

**`miao update`** downloads the current `miao` script from the main branch of the MiaoYan repository and replaces the installed one. Run it when you want to update the CLI, not as a routine step in a script.

## How it finds your notes

The CLI does not need configuration, but knowing how it finds the library helps when something does not work.

1. If the `MIAOYAN_PATH` environment variable is set, it uses that.
2. Otherwise it reads the `storageUrl` preference that MiaoYan saved when you picked a folder, with `defaults read com.tw93.miaoyan`.
3. If that gives no folder, it tries `~/Documents/MiaoYan`, `~/Save/MiaoYan` and `~/MiaoYan`.

If none of them exist, it prints "Error: Notes directory not found." and tells you to set `MIAOYAN_PATH`. Set it in your shell profile if you keep the library somewhere unusual, including MiaoYan's own iCloud Drive folder, which the CLI does not look for:

```bash
export MIAOYAN_PATH="$HOME/Notes"
```

## Examples

Create a dated journal note with a first line:

```bash
miao new "Journal $(date +%F)" "Morning plan: finish the draft."
```

List files that mention a phrase, once each:

```bash
miao search "release checklist" | cut -d: -f1 | sort -u
```

Print every note in a folder, for example to hand to another tool:

```bash
miao list Projects | while read -r f; do
  echo "## $f"
  miao cat "$f"
done
```

Count the words in one note:

```bash
miao cat "Project plan" | wc -w
```

Open the first search hit in the app:

```bash
miao open "$(miao search 'quarterly review' | head -1 | cut -d: -f1)"
```

Search output is relative to the library root, and the path forms of `open` and `cat` resolve against that same root, so the commands fit together.

## Using it with AI coding agents

Because the library is a folder, an agent that can read files can already read your notes. The CLI helps in two ways: `miao search` and `miao list` give an agent a cheap map of the library without crawling the whole tree, and `miao open` shows a result to you in the app.

MiaoYan also publishes an agent skill that teaches an agent MiaoYan's syntax: wikilinks by exact title, local images as `/i/<filename>` in an `i/` folder, math and diagram fences, PPT slide separators, and the CLI commands. Install it with:

```bash
npx skills add tw93/MiaoYan/skills/miaoyan -g
```

The skill tells agents to use only the real commands, not to invent `miao edit` or `miao append`, and to set `MIAOYAN_PATH` when the CLI cannot find the library. It also instructs them never to guess a private folder or write outside the approved library.

Editing is a file operation. If an agent changes a note that is open in MiaoYan, the app reloads it from disk. If you have unsaved text in the editor that differs, MiaoYan first writes your text to the hidden `.miaoyan-conflicts` folder and notifies you, so nothing is lost silently. Even so, switch to another note before letting an agent rewrite the current one, because MiaoYan snapshots a note's version history when you leave it. See [Markdown note version history](/blog/markdown-note-version-history/).

## What goes wrong

- **"Notes directory not found."** Set `MIAOYAN_PATH`, or open MiaoYan once and choose a folder in Preferences.
- **Two notes with the same title.** `miao cat` and `miao open` resolve an exact title to the first match, so use a path such as `Projects/Plan` when titles repeat.
- **`miao search` finds too much or too little.** With ripgrep, it uses a fixed-string match. Without it, `grep` treats the query as a pattern.
- **`miao new` seems to do nothing.** It hands off to the app, so check that MiaoYan is installed and allowed to open.
- **Command not found.** `~/.local/bin` is not on your `PATH` in the current shell. Start a new shell.

The CLI is a convenience layer over a folder of files. For the rationale behind this design, read [Local-first Markdown notes](/blog/local-first-markdown-notes/). MiaoYan for Mac is open source on [GitHub](https://github.com/tw93/MiaoYan), and the [App Store](https://apps.apple.com/app/id6759252269) version covers Mac, iPhone and iPad.

## FAQ

### Can the CLI edit or append to an existing note?

No. There is no edit or append command. Edit the file directly with any tool and MiaoYan reloads it.

### Does the CLI work with the App Store version?

Yes, the commands work the same way. It finds the library through the `storageUrl` preference or the default folders. If it picks the wrong folder or none at all, set `MIAOYAN_PATH` to the folder you chose in the app.

### Does it work on Linux?

No. The script calls macOS-only tools, and the app is a Mac app.
