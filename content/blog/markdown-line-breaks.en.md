A single newline inside a paragraph is not a line break in CommonMark. It is a soft break that renders as a space, so two lines typed one under the other come out as one line. To force a break, end the line with a backslash (or two spaces, or a `<br>`), or leave a blank line to start a new paragraph. The trap is that apps disagree about what a plain newline means, and MiaoYan's own default is not the CommonMark rule.

## Soft breaks, hard breaks and paragraphs

CommonMark defines three things that look similar in the editor. A regular line ending that is not preceded by two or more spaces or a backslash is a soft break, and the spec says a renderer may output it as either a line ending or a space; in a browser both look like a space. A hard break is a backslash at the end of the line, or two or more spaces at the end of the line, and it renders as `<br />`. A blank line ends the paragraph and starts a new one with its own block spacing.

```markdown
Soft break: this line
continues on the same line.

Backslash break: this line ends here\
and this one starts below it.

Two-space break: this line ends here··
and this one starts below it.

Raw HTML break: this line ends here<br>
and this one starts below it.
```

In the example, the two dots stand for two real spaces. Raw HTML also works because Markdown passes inline HTML through, which is why `<br>` is the usual way to break a line inside a table cell (see [Markdown tables](/blog/markdown-tables/)). A paragraph break differs from a hard break in spacing: a blank line adds the full gap between paragraphs, while `<br>` stays inside one paragraph with normal line height.

The spec also notes that a renderer may provide an option to render soft breaks as hard breaks. That option is the root of most "my line breaks disappeared" complaints, because different tools pick different defaults.

## Why the same file looks different in different places

GitHub documents two behaviors. In issues, pull requests and discussions, a single newline renders as a line break automatically. In an `.md` file the same text renders on one line, and you need two trailing spaces, a backslash or a `<br />` to break it. So a comment you drafted in an issue looks wrong once pasted into a README, and the reverse.

Other editors choose their own side. Some preview panes follow the strict rule, some break at every newline to feel closer to a chat box, and some expose a switch. If you move notes between tools, the text file is identical and only the renderer's flag changes. That is also why a spec-conforming parser and a note app can disagree about the same file without either being buggy.

## MiaoYan's Line Break setting

MiaoYan exposes the switch. Open Preferences, choose the Editor tab, and find the row labeled `Line Break:` (in Chinese, 「偏好设置」 then 「编辑器」 and the row 「换行方式」). It is a pop-up with two values, `MiaoYan` and `Github`. In the Chinese interface the first reads 「妙言」 and the second stays `Github`. The default is `MiaoYan`.

The values map to two cmark-gfm render flags in the v4.5.0 source. `MiaoYan` renders every newline as a `<br>`, so lines typed one under the other stay on separate lines and a blank line still starts a new paragraph. `Github` renders a soft break as a space, which is the `.md` file rule from the previous section. In both modes a trailing backslash, two trailing spaces and a raw `<br>` still produce a break, because those are hard breaks or inline HTML rather than soft breaks.

The label is easy to misread. `Github` does not mean "behave like GitHub comments". Comments break at every newline, which is closer to MiaoYan's default. `Github` means "behave like a GitHub `.md` file", the strict rule.

The setting is read whenever the preview or an HTML export is rendered, and PDF export prints the rendered preview, so all three follow it. Nothing is written into your note; the file keeps exactly the text you typed. Only how that text is turned into HTML changes. The editing pane is unaffected, since it shows raw text, which is also why a soft break is invisible there.

## Which mode should you use

Match the place the text will end up. If notes stay inside MiaoYan, the default is the more forgiving choice: you type a line, press Return and see a new line, with no invisible characters to manage. If the note becomes a README, a docs page, a static-site post or anything rendered by CommonMark, switch to `Github` while you write so the preview shows what the reader will get, and use a blank line between paragraphs or a backslash where you want a break inside one.

A note that reads well in the default mode but has no blank lines between paragraphs will run together everywhere else. The quick fix is a blank line, which behaves the same in every renderer. When you edit a note someone else wrote, ask which mode they assumed; the file itself does not say.

## Which break to put in a file you share

Prefer a blank line when you mean a paragraph, and a backslash when you mean a break inside one. Two trailing spaces are valid but fragile: they are invisible, and many tools remove them. EditorConfig defines `trim_trailing_whitespace`, which removes all whitespace before each newline when set to true, and an editor or formatter that applies it will quietly turn your hard breaks into soft ones. A backslash is visible, survives trimming and is part of the CommonMark spec. Use `<br>` when the break must work inside a table cell, and accept that it is HTML and shows literally in tools that do not render it.

One boundary applies. The CommonMark spec says neither hard-break syntax works at the end of a paragraph or another block such as a heading, because there is no following line to break into, and a backslash inside code is just a backslash.

## How to check which mode a file assumes

You cannot tell from the file, so test the renderer. Put three short lines in a scratch note with no blank lines between them:

```markdown
one
two
three
```

If the preview shows three lines, the renderer breaks at every newline. If it shows `one two three`, it follows the strict rule. In MiaoYan, switch `Line Break:` between the two values and compare the preview. To test a break marker, add a backslash after `one` and see whether `one` and `two` split in strict mode.

If a shared file looks wrong, check for these causes in order: the viewer's newline rule, trailing spaces removed by a formatter or a save hook, and a backslash typed with a space after it, which is a literal backslash and not a break. For other syntax differences between GFM and CommonMark, the [Markdown cheat sheet](/blog/markdown-cheat-sheet/) covers the extensions MiaoYan renders, and [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/) shows what the export includes.

## FAQ

### Why does my Markdown line break not show up?

Your renderer treats a single newline as a soft break, which becomes a space. End the line with a backslash or leave a blank line.

### Is the backslash or two spaces better?

The backslash. Both are valid CommonMark hard breaks, but trailing spaces are invisible and often stripped when a file is saved or formatted.

### Does MiaoYan's Line Break setting change my file?

No. It only changes how the preview, HTML export and PDF export are rendered. The note keeps the text you typed.

### Do GitHub comments and README files behave the same?

No. GitHub renders a single newline as a line break in issues, pull requests and discussions, and as a space in an `.md` file.
