A Markdown task list is an ordinary list item that starts with `[ ]` for an open task or `[x]` for a done one, written as `- [ ] Buy milk`. The syntax comes from GitHub Flavored Markdown (GFM), not from core CommonMark, so a parser without the GFM extension prints the brackets as literal text. Nothing in the format stores state apart from the characters in the file, which makes the list easy to search and diff, and also means that "clicking a checkbox" is always an editor feature that rewrites a line of text.

## The syntax

````markdown
- [ ] Draft the post
- [x] Pick a title
- [ ] Add screenshots
  - [ ] Crop the second one
  - [x] Compress the first one
````

The GFM specification defines a task list item as a list item whose first block is a paragraph that begins with the marker and at least one whitespace character before any other content. The marker is a left bracket, either a whitespace character or the letter `x` in lowercase or uppercase, and a right bracket. If the character between the brackets is whitespace the box is unchecked, otherwise it is checked. The spec also states that it does not define how the checkbox is interacted with, which is why behavior differs between apps.

Two details cause most failures. The space after the closing bracket is required, so `- [ ]Buy milk` is not a task. And `[]` with nothing inside is not the marker either, so write exactly one space for an open task.

Nesting works as it does for any list: indent the child by two spaces under a hyphen, as in the spec's own nested example. A parent task does not check itself when its children are done; in the file, each box is independent.

## Bullets, numbers and ordered tasks

The list marker can be `-`, `*` or `+`, and the spec's wording about a list item also covers an ordered item such as `1. [ ] Step one`. cmark-gfm, the parser behind MiaoYan's preview, draws that as a numbered list with checkboxes, which suits a runbook where order matters.

That is the standard. A specific editor can be stricter about what it writes back, and this is where hyphens matter. MiaoYan's own toggle logic, described below, only recognises `- [ ] ` and `- [x] `, so use a hyphen and a lowercase `x` if you want clicking to be reliable. The [Markdown cheat sheet](/blog/markdown-cheat-sheet/) lists the other GFM additions.

## What renders where

- **GitHub.** GitHub's formatting guide uses this exact syntax. In issues and comments, GitHub's docs say the tasks render with a clickable checkbox. Treat that click as a GitHub feature, not as part of Markdown.
- **CommonMark without the GFM extension.** The item is a normal bullet whose text begins with `[ ]`. You see the brackets.
- **Other editors.** Whether a rendered box can be clicked is not part of the spec, so each editor decides for itself. Test a click once before relying on it.

MiaoYan's preview uses a Swift build of cmark-gfm with four extensions turned on: table, footnotes, strikethrough and tasklist (`Business/Markdown.swift` at the V4.5.0 tag). So task lists render as real `input` checkboxes in the preview.

## How clicking a checkbox works in MiaoYan

In the V4.5.0 preview, the page script (`common.js`) enables every checkbox and numbers them in document order. A click sends that number to the app, and the app (`HandlerCheckbox` in `MPreviewHandlers.swift`) walks through the note's text, finds the matching occurrence of `- [ ] ` or `- [x] `, swaps it for the other form and saves the note.

This mechanism explains the edge cases. The app matches by position: the Nth checkbox in the preview is assumed to be the Nth `- [ ] ` or `- [x] ` in the source text. If your note contains task syntax the regex does not count, such as `* [ ]`, `+ [ ]`, `1. [ ]` or a capital `X`, the preview still draws a box, but the numbering drifts and a click may change a different line. The same thing can happen if `- [ ] ` appears in a place that is not rendered as a task, for example inside a fenced code block or a blockquote, because the text match does not know about code fences or quotes. If a click toggles the wrong line, look for those two causes first.

In the editor, the Format menu has a "Todo" item (`⌘T`, labeled 「待办」 in the Chinese interface). On a line that is not a task it inserts `- [ ] `, and on a task it switches between `- [ ] ` and `- [x] `. It rewrites the first six characters of the line, so on an indented sub-task it breaks the marker; click the box in the preview for those. Typing `/task` and pressing `Tab` inserts a three-line template, two open tasks and one done, with Chinese placeholder text; the Tab Quick Input menu lists it as "/task - Task List".

## Tasks inside blockquotes

````markdown
> - [ ] Ask about the deadline
> - [x] Send the draft
````

The cmark-gfm version in MiaoYan V4.5.0 does not turn these into checkboxes. The quote holds a normal bulleted list whose items start with the text `[ ]` and `[x]`, and that stays the same with `>` on every line and a blank `>` line before the list. Other renderers may treat this differently, so test the one your notes end up in. In MiaoYan there is a second cost: the click toggle still counts `- [ ] ` inside the quote, so every checkbox after it in the note changes the wrong line. Keep tasks outside blockquotes, and put the quoted context in a paragraph above the list.

## Finding open tasks across notes

Because a task is plain text, a search tool can list what is left. In a folder of Markdown notes, ripgrep shows every open item with its file and line:

````bash
rg -n -F -- '- [ ]' ~/Notes
````

`-F` treats the pattern as a fixed string, so the brackets are not read as a regex character class, and `--` stops the leading hyphen being read as an option. Indented sub-tasks match too, since the string can appear anywhere on a line. For done items use `'- [x]'`. With plain `grep`:

````bash
grep -rn --include='*.md' -F -- '- [ ]' ~/Notes
````

To count open tasks per file, add `-c`, which prints a number per file. This is also the best argument for sticking to one spelling: if some notes use `* [ ]`, one search will miss them. More ways to work with notes from the shell are in [Markdown notes from the terminal](/blog/markdown-notes-from-terminal/).

## Limits and when to use something else

A task list is a checklist, not a task manager. It has no due dates, no reminders and no recurrence, and the only state is open or done. For a shopping list, a release checklist or a daily plan inside a note, it is the right size. For deadlines and reminders, use a dedicated tool and keep the note as the reference.

## FAQ

### Why does my checkbox show as `[ ]` text?

The renderer does not have the GFM tasklist extension, or the syntax is slightly off. Check for a space after the hyphen and after the closing bracket, and for exactly one character between the brackets.

### Can I check a box in the file without clicking?

Yes. Change the space between the brackets to `x`. That is all a click does in any editor.

### Is `[X]` with a capital letter valid?

The GFM spec accepts both cases, and MiaoYan's preview draws a checked box for it. MiaoYan's click toggle only matches a lowercase `x`, so lowercase is safer.

### Do task lists work in exported PDF or HTML?

Exports are made from the preview, so check one exported file if it matters. A checkbox in an exported file is a snapshot of the note, not a way to change it.
