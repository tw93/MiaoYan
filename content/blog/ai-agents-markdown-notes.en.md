A folder of plain Markdown files is the easiest notes format for a coding agent such as Claude Code or Codex, because the agent already knows how to work with files: it lists a directory, searches with grep, reads a file and edits it. There is no API, no export step and no sync token to set up. The sensible way to start is to give the agent a copy of the folder, or a folder under git, ask it to read first, and review what it changed with a diff before you keep it.

## Why plain files suit agents

Coding agents are built around a working directory. The tools they reach for are the ones developers use every day: list files, search text, open a file, write a file, run a command. A notes folder fits that loop without translation.

- **Reading is cheap.** `grep -rn "pricing" .` finds every note that mentions pricing, with the line. The agent does not need a database client or a search endpoint, and it can read only the three files that matter instead of the whole library.
- **Writing is a file write.** Appending a section to `Project plan.md` is the same operation as editing source code. Nothing has to be re-imported afterwards.
- **Structure is already text.** Headings, lists, tables, front matter and `[[wikilinks]]` are all characters in a file, so an agent can see them and keep them intact. See [Markdown front matter](/blog/markdown-front-matter/) for the metadata block at the top of a note.
- **Changes can be reviewed.** A text file has a line diff. With git, or even `diff -r` against a copy, you can see exactly which lines an agent touched.

Notes locked in an app database usually need an export, a vendor API or a plugin before an agent can read them. This is the same argument [local-first Markdown notes](/blog/local-first-markdown-notes/) make for people: the files outlive the app, and the agent is one more tool that benefits.

## Point an agent at the folder safely

An agent with file access can change files. That is the feature, and it is also the risk, so set it up in a way that makes every change visible and reversible.

### 1. Work on a copy first

Before the first session, copy the library somewhere else and point the agent at the copy:

```bash
cp -R ~/Notes ~/Notes-agent-test
cd ~/Notes-agent-test
```

Run your agent from that directory. If something goes wrong, delete the copy. Once you trust a type of task, you can move to the real folder.

### 2. Put the real folder under git

If the folder is not a repository yet, make it one before an agent touches it:

```bash
cd ~/Notes
git init
git add -A
git commit -m "notes before agent session"
```

Now `git status` shows which files an agent changed, `git diff` shows the lines, and `git restore <file>` or `git checkout -- .` puts a note back. Commit again after you have reviewed the diff and are happy with it.

### 3. Ask for read-only work first

Start with tasks that should not write anything: "summarize the notes tagged `project-x`", "list notes that mention a contract but have no date in the front matter", "find notes that link to a title that does not exist". If the answers are useful, move on to edits. When you do ask for edits, name the files, and say what must stay unchanged, such as front matter, code fences and links.

### 4. Know what an agent can break

- **Front matter.** A careless rewrite can reformat or drop the YAML block at the top of a note.
- **Links.** Renaming a file or changing a heading can break `[[wikilinks]]` and anchors that point to it, and the agent will not see backlinks unless it searches for them.
- **Fences and tables.** An unclosed code fence swallows the rest of the note in the preview, and a table with a mismatched header and divider row stops being a table.
- **Attachments.** Moving a note without its images leaves broken image paths.
- **Many files at once.** A "tidy up all my notes" request is a bulk edit that is hard to review, so ask for one folder at a time.

## What MiaoYan gives an agent at V4.9.0

MiaoYan stores each note as a `.md` file in the folder you choose, so the folder above is simply your library. Two pieces in the open-source repository help an agent.

### The `miao` command

`miao` is a Bash script that lists, searches, prints, opens and creates notes. Besides `help`, its commands are `list [folder]`, `search <query>`, `open <title|path>`, `cat <title|path>`, `new <title> [text]` and `update`. None of them edits an existing note, so an agent edits the file directly. How the CLI finds your library, with examples, is in [Markdown notes from the terminal with the miao CLI](/blog/markdown-notes-from-terminal/).

### The MiaoYan Agent Skill

The repository ships a skill in `skills/miaoyan`, with a `SKILL.md`. The README describes it as a way to teach your agent MiaoYan syntax, attachments, PPT patterns and CLI workflows, and gives this install command:

```bash
npx skills add tw93/MiaoYan/skills/miaoyan -g
```

The skill is a set of instructions, not a plugin that connects to the app. Read at that tag, it tells an agent to:

- identify whether you want a note, a PPT presentation, note organization or a CLI operation, and keep your language without translating;
- preserve existing front matter, fenced code, inline code, math, links, wikilinks and attachment paths when editing;
- fall back to standard GitHub Flavored Markdown when no MiaoYan-specific feature is needed, with tables, task lists, strikethrough and footnotes as supported extensions;
- link notes with `[[Exact title]]`, without the `.md` suffix, and not invent alias, heading or block-reference syntax;
- keep local images in an `i/` folder under the note's folder and reference them as `/i/<filename>`, not as `file://` URLs or absolute paths;
- use fenced `mermaid`, `plantuml` and `markmap` blocks for diagrams, `$...$` and `$$...$$` for math, GitHub alert markers such as `> [!NOTE]` for callouts, and `<details>` for collapsible sections;
- separate slides with a standalone `---` line, and never use `---` as a plain rule inside a slide;
- use only the real `miao` commands, not invent `miao edit` or `miao append`, run `miao update` only when you ask for it, set `MIAOYAN_PATH` if the CLI cannot find the library, and never guess a private folder or write outside the library you approved;
- finish by checking for closed fences, valid paths, exact wikilink targets and standalone PPT separators.

Next to `SKILL.md`, `skills/miaoyan/agents/openai.yaml` holds a display name, a short description and a default prompt for the skill.

Claude Code's own documentation describes skills as a `SKILL.md` with YAML front matter inside a skill folder, kept in `~/.claude/skills/<skill-name>/` for all projects or `.claude/skills/<skill-name>/` inside one repository. Claude uses the `description` to decide when a skill is relevant, and loads the full body only when it is used.

## What happens when the app is open

If an agent edits a note that MiaoYan is showing, the app watches the folder and reloads the file from disk. If the text in your editor differs from the file at that moment, MiaoYan first writes your version to a hidden `.miaoyan-conflicts` folder in the library root, shows a toast saying "Changed on disk. Your version was backed up", and then loads the disk version.

The practical habit is simple: do not type in a note while an agent is rewriting it, and switch to a different note first. MiaoYan also keeps earlier versions of notes as a safety net, covered in [Markdown note version history](/blog/markdown-note-version-history/), but those snapshots live in the app's support folder, not in your notes folder, so git is still the history you control.

## What goes wrong

- **The agent writes outside the library.** Run it from the notes directory, and for the CLI set `MIAOYAN_PATH` explicitly rather than letting a script guess.
- **Duplicate titles.** `miao cat` and `miao open` resolve an exact title to the first match, so give the agent a path such as `Projects/Plan` when titles repeat.
- **A rewrite changed more than you asked.** Run `git diff`, restore the file, and repeat with a narrower instruction.
- **Sensitive notes.** Anything the agent reads becomes part of the session, so keep private notes in a folder you do not point an agent at.

## FAQ

### Can Claude Code or Codex read my notes without any plugin?

Yes, if they can open the folder. Markdown notes are ordinary files, so file tools and `grep` are enough. The MiaoYan skill only adds knowledge of the app's syntax and CLI.

### Should I give an agent my whole notes folder?

Not at first. Start with a copy or a git repository, read-only tasks and one folder at a time.

