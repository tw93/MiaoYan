Markdown has no comment syntax of its own, so you borrow one. The common choice is an HTML comment, `<!-- note -->`, on its own line with blank lines around it. It disappears from the rendered page but stays in the source, in any exported HTML file and in "view source". The alternative is a link reference definition, `[//]: # (note)`, which produces no output at all, not even in the HTML. MiaoYan V4.5.0 hides both in the preview and in PDF export, and keeps the HTML comment inside exported HTML. Neither is private, so never put a password or a token in one.

## Two ways to write a comment

```markdown
Visible paragraph.

<!-- A comment on one line. -->

<!--
A comment on several lines.
Markdown here is not parsed:
- **not bold**
-->

[//]: # (A comment that leaves nothing in the HTML.)

Visible again.
```

The HTML form works because raw HTML is part of Markdown. CommonMark starts an HTML block at a line beginning with `<!--` and ends it at the first line containing `-->`, and everything between is passed through untouched. Blank lines inside do not end it, which is why a multi-line comment can hold lists and blank lines safely. Inside a paragraph, `Hello <!-- aside --> world` is treated as inline raw HTML and stays inline.

The reference form is a different mechanism. CommonMark defines a link reference definition as a label in brackets, a colon, a destination and an optional title in quotes or parentheses. A definition renders nothing, so `//` is just a label, `#` a destination and your comment the title. `[//]: <> (text)` and `[note]: # "text"` behave the same. The title may run over several lines but cannot contain a blank line, and the definition cannot interrupt a paragraph, so keep a blank line before it. In cmark-gfm 0.29.0.gfm.3, the version bundled with MiaoYan V4.5.0, `Para` followed directly by `[//]: # (x)` printed the definition as plain text. The comment text has its own limit: a title in parentheses may contain `(` or `)` only with a backslash in front, so `[//]: # (see (x) here)` is not a definition and prints as a paragraph, while `[//]: # (see \(x\) here)` stays hidden. Double quotes have the same rule for `"`, so pick the delimiter your comment does not contain.

## What each form leaves behind

| | HTML comment | `[//]: # (text)` |
| --- | --- | --- |
| Rendered page | hidden | hidden |
| HTML source | present | absent |
| Works where raw HTML is stripped | no | yes |
| Contents parsed as Markdown | no | no |

The HTML comment survives into the generated HTML, so anyone who opens "view source" on a page built from your note can read it. A renderer that strips raw HTML replaces it with a placeholder such as `<!-- raw HTML omitted -->`, and the contents are gone. The reference form leaves nothing, but it is a convention, not a feature: if another part of the note writes `[//]`, that text becomes a link to `#`, and a second definition with the same label is ignored. Use `//` once, or give each comment a unique label.

GitHub documents the HTML form, saying content placed in an HTML comment is hidden from the rendered Markdown. The text stays in the file, so it shows in the raw view and the editor, and anyone who can read the repository can read it.

## Where comments leak

- **Code.** Inside a fenced block or inline code, `<!-- -->` is shown literally, because nothing is parsed there. This is also how you display one.
- **An unclosed comment.** `<!--` at the start of a block with no `-->` swallows the rest of the document into the HTML block, and the browser then hides all of it.
- **Nesting.** A comment ends at the first `-->`. In a block that contains a second comment, `leaked text` after the inner `-->` shows up on the page, followed by a stray `-->`. Remove the inner comment markers instead of nesting.
- **Text after the closer.** On a line such as `<!-- c --> **text**`, the whole line belongs to the HTML block, so `**text**` is not bold. Put the comment on its own line.
- **Four spaces.** An indented `<!-- c -->` after a blank line is a code block, and it prints.
- **Front matter.** MiaoYan hides a `---` block only when the note starts with it, so a comment above it turns the block into a rule and a heading. Put comments below the closing `---`; the [front matter](/blog/markdown-front-matter/) article has the rule.

Table cells and headings take inline comments fine; in a list item, indent the comment to the item's text and it works.

## How MiaoYan V4.5.0 handles them

MiaoYan renders Markdown with cmark-gfm and the raw-HTML option on (`CMARK_OPT_UNSAFE`), so comments reach the preview as real HTML comments, which a web view never draws. That one renderer feeds the preview, PDF export and HTML export. The preview and PDF export show no comment text, because a PDF is the printed preview. File > Export > HTML renders the note again and saves the HTML to Downloads, and no step on that path removes comments, so the file contains them.

The editor's highlighter has no rule for comments, and V4.5.0 has no Format-menu command or slash shortcut for them, so type the markers yourself. Because the source keeps them, a search for `TODO` or for `<!--` finds them in every note, which is the main reason to prefer a comment over deleting a line: `grep -rn "<!--" notes/` lists them all.

## Comments or front matter

Both are hidden in rendered output and both are readable in the file. The difference is who consumes them. Front matter is metadata that generators such as Jekyll and Hugo read, like a title, date or `draft` flag, and a comment is ignored by every tool. Use front matter for fields a build needs, and a comment for a note to yourself or an editor. A draft flag also does something a comment cannot: a generator can leave the page out of the site. If a paragraph must not be published, move it to another note rather than hiding it in a comment.

## Never put secrets in a comment

A comment is plain text in a file you may sync, commit or export. The note folder may go through iCloud Drive, Dropbox or git, as in [syncing notes](/blog/sync-markdown-notes-across-devices/), and an exported HTML page carries the comment to whoever receives it. If it is sensitive, keep it out of any note you share or publish.

## FAQ

### Is there an official Markdown comment?

No. Neither CommonMark nor GFM defines one. The HTML comment is raw HTML that Markdown passes through, and `[//]: # (text)` is a link reference definition used as a convention.

### Which form should I use?

The HTML comment is more widely understood and supports several lines. Use the reference form when the output must stay clean, or when the renderer strips raw HTML.

### Does a comment show in GitHub?

Not in the rendered page, but it appears in the raw file and the edit view.
