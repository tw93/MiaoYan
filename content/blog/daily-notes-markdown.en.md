A daily note in Markdown is one plain file per day, named with the ISO date, such as `2026-11-14.md`, kept in a folder per year. That name sorts correctly in any file browser, becomes the note title in MiaoYan, and works as a wikilink target, so one choice does three jobs. Add a short template with a `date` in front matter, create today's file with a few lines of shell, and rely on search for everything older. MiaoYan has no daily-note command or template setting at V4.9.0, so what follows is a convention plus a script, not a built-in feature.

## Name the file for the day

Use `YYYY-MM-DD.md`. Year first, then month, then day, each zero-padded to a fixed width, means alphabetical order and chronological order are the same order. Names like `14-11-2026` or `Nov 14` sort by day or by month name and scatter your entries.

The shell can produce the name. `date +%F` prints the current date as `2026-11-14`, and it works with the `date` that ships with macOS. For yesterday, macOS uses `date -v-1d +%F`, while GNU `date` on Linux uses `date -d yesterday +%F`.

In MiaoYan the note title is the file name without the extension, so `2026-11-14.md` shows in the list as "2026-11-14". Nothing inside the file has to repeat it.

## Put them in folders by year

One folder per year keeps every list short:

```text
MiaoYan/
  Journal/
    2025/
      2025-12-31.md
    2026/
      2026-11-13.md
      2026-11-14.md
```

Month folders are possible, but they add a level you rarely need when search is one keystroke away. The [local-first notes post](/blog/local-first-markdown-notes/) makes the same case for a shallow library. Obsidian's Daily notes plugin supports the idea directly: its help page says a date format such as `YYYY/MMMM/YYYY-MMM-DD` makes the plugin create the subfolders for you.

## A small template

Keep the template short enough that you never skip it:

```markdown
---
date: 2026-11-14
---

## Plan

## Log

## Links
```

The `date` is redundant with the file name, which is the point: a script that reads metadata does not have to parse the name, and a note that is renamed or moved still says which day it is. MiaoYan hides a leading front matter block in the preview and in exports, while the editor still shows it; the rules are in [Markdown front matter](/blog/markdown-front-matter/). `Plan` holds tasks as `- [ ]` items (see [task lists](/blog/markdown-task-lists/)), `Log` is free writing, and `Links` holds the day's wikilinks. If a section stays empty for a week, delete it from the template.

## Create today's file from the terminal

This script creates today's file only if it does not exist, then prints the path:

```bash
#!/bin/bash
NOTES="${MIAOYAN_PATH:-$HOME/Documents/MiaoYan}"
today=$(date +%F)
file="$NOTES/Journal/$(date +%Y)/$today.md"
mkdir -p "$(dirname "$file")"
[ -e "$file" ] || printf -- '---\ndate: %s\n---\n\n## Plan\n\n## Log\n\n## Links\n\n' "$today" > "$file"
echo "$file"
```

Save it as `today`, make it executable and put it on your `PATH`. `MIAOYAN_PATH` is the variable the `miao` CLI reads, so set it once in your shell profile if your library is elsewhere. The `[ -e ]` test makes a second run harmless: it leaves the existing file alone. MiaoYan watches the folder through macOS file system events, so the new file appears in the list on its own, and `open -a MiaoYan "$(today)"` opens it.

### With the miao command

`miao` can create a note too:

```bash
miao new "$(date +%F)" "## Plan"
```

Two behaviours matter. `miao new` hands the title and text to the app through a `miaoyan://new/` address, and the app creates the file in the folder currently selected in its sidebar; the command has no folder argument, so it lands in `Journal/2026` only if that folder is selected. And when a file with that name exists, MiaoYan does not open it: it creates `2026-11-14 1.md`, then `2026-11-14 2.md`. Run it twice in a day and you have two files. The text argument becomes the whole body, with no heading added.

So the script is the better tool for creating the day, and `miao` is better for the rest: `miao open 2026-11-14` opens a day by title, `miao cat 2026-11-14` prints it, and `miao list Journal/2026` lists the year. The commands are covered in [Markdown notes from the terminal](/blog/markdown-notes-from-terminal/).

## Link days together

In the `Links` section, write `[[2026-11-13]]` for yesterday or `[[Project plan]]` for something the day touched. A wikilink matches a note title exactly, and the match searches the whole library, so `[[2026-11-13]]` works from any folder and the year folder never appears in the link. Backlinks give the reverse view: open the document properties panel with Command Option I, and the "Backlinks" line lists every note that links to the current one, so a project note shows each day that mentioned it. Syntax and limits are in [Wikilinks and backlinks](/blog/wikilinks-and-backlinks/). If recurring ideas deserve their own notes, [Zettelkasten with Markdown notes](/blog/zettelkasten-markdown-notes/) covers that step.

## Find things later

Date names answer "what did I do on the 14th" and nothing else, so search carries the rest.

**In MiaoYan.** Command / jumps to the search field. Every word you type must appear in the title or the body, in any combination. Typing `2026-11` finds November's days through their titles, and `roadmap` finds the days that mention it, up to 100 results.

**Sort the list by title.** In the View menu, "Sort by" offers Modification date, Creation date and Title, with Ascending and Descending. For a journal, pick Title and Descending, so the newest date is on top. Modification date reshuffles the list whenever you touch an old day, and creation date comes from file metadata that a copy or a sync can change. Pinned notes stay above the sorted list either way.

**In the terminal.** ripgrep reads a whole journal quickly:

```bash
rg -n -F -- '- [ ]' Journal           # every open task, with file and line
rg -l -i roadmap Journal/2026         # days that mention a word
rg -l -F 'date: 2026-11' Journal      # every day in November, by front matter
```

`miao search <query>` searches the whole library and prints `path:line:text`; with ripgrep installed it is a fixed-string search, otherwise it falls back to `grep`.

## Keep the habit light

Journals mostly fail at the template, not the tooling. One line on a bad day is enough, since an empty file proves nothing and a line proves you showed up. Leave old days alone apart from typos, and move anything that deserves a future into its own titled note, linked from the day.

MiaoYan keeps up to 20 versions of each note, restorable with Command Shift H, which covers an accidental wipe of the day's text; [version history](/blog/markdown-note-version-history/) explains what it does not cover. A journal is also worth putting under Time Machine or git.

## When Obsidian fits better

The Obsidian help site describes a Daily notes core plugin that opens a note named after today's date, `YYYY-MM-DD` by default, and creates it if it does not exist, from a command palette command or a hotkey. It can fill a template file that uses `{{date:YYYY-MM-DD}}` and put notes in a folder you choose. If you want one keystroke to open today's page with the template ready, that is a convenience MiaoYan does not match. Both apps read plain Markdown files with `YYYY-MM-DD` names, so the same folder opens in either; see [Obsidian alternative for Mac](/blog/obsidian-alternative-mac/).

MiaoYan for Mac is open source on [GitHub](https://github.com/tw93/MiaoYan), and the [App Store](https://apps.apple.com/app/id6759252269) version covers Mac, iPhone and iPad.

## What goes wrong

- **Two files for one day.** You ran `miao new` twice, or a sync service made a conflict copy. Look for `2026-11-14 1.md`, merge the text and delete the extra.
- **A day link opens a search.** Two notes share the title, for example a work journal and a personal one that both contain `2026-11-14.md`. Keep one journal folder, or add a suffix such as `2026-11-14 work`.
- **Days sort in the wrong order.** One file has a single-digit month or day. Zero-pad everything.
- **The script writes to the wrong folder.** `MIAOYAN_PATH` is unset and `~/Documents/MiaoYan` is not your library. Set it to the folder you chose in the app.

## FAQ

### Does MiaoYan have a daily note feature?

No. There is no command that opens today's note and no template setting at V4.9.0. The naming convention and the script above give the same result with one extra step.

### Can I make the template appear when I press New?

Not directly. As a manual route, keep a note called Template, press Command D to duplicate it into "Template Copy", then rename it with Command R. The script is faster.

### Can I use weekly or monthly notes?

Yes, with the same pattern, such as `2026-W46.md` or `2026-11.md`, linking to the days from the summary. `date +%G-W%V` prints the ISO week.
