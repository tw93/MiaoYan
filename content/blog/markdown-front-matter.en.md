Front matter is a block of metadata at the very top of a Markdown file, fenced by two `---` lines and written in YAML, so a static site generator can read the title, date and tags before it renders the body. Put it on the first line with nothing above it, close it with a `---` line of its own, and quote values that contain a colon. MiaoYan V4.5.0 hides a block like this in the preview and in exports, but only when the file starts with `---` and ends the block with another `---`; TOML front matter written with `+++` is not recognized.

## The syntax

```markdown
---
title: Markdown front matter
date: 2026-10-19
tags: [markdown, notes]
draft: false
---

The note starts here.
```

The opening `---` must be the first line. The keys are plain YAML, so lists can be written inline as above or as `- item` lines, and a value with a colon, such as `title: "Note: a test"`, needs quotes. Jekyll's documentation describes the same shape, a set of valid YAML between triple-dashed lines, and notes that a file with an empty pair of dashes is still processed by Jekyll. It also warns that a UTF-8 byte order mark at the start of the file breaks things, which is one reason a file that looks correct can fail.

Pandoc is slightly more flexible. Its manual says a YAML metadata block is delimited by `---` at the top and either `---` or `...` at the bottom, that the opening line must not be followed by a blank line, and that the block can appear later in the document if a blank line precedes it.

## Keys that generators use

There is no universal key list, because each generator defines its own.

| Generator | Format | Keys its docs name |
| --- | --- | --- |
| Hugo | YAML with `---`, TOML with `+++`, or JSON | `title`, `date`, `draft`, `weight`, `description`, and taxonomies such as `tags` |
| Jekyll | YAML between triple dashes | `layout`, `title`, `date`, `published` |
| Astro | YAML, or TOML | custom properties such as a title, description and tags |

Hugo's documentation says it determines the format by looking at the delimiters, so `+++` means TOML, and it lists `date`, `draft`, `title` and `weight` as the most common fields. Jekyll uses `layout` and `title` in its basic example, `date` as a post variable, and `published: false` to keep a post out of the generated site. Astro's Markdown guide says front matter defines custom properties such as a title, description and tags, which your own components then read.

TOML front matter looks like this:

```markdown
+++
title = "Markdown front matter"
date = 2026-10-19
tags = ["markdown", "notes"]
+++
```

Hugo reads each file's delimiters to pick the parser. A tool that only knows the `---` form shows a `+++` block as ordinary text, and MiaoYan V4.5.0 is one of them.

## How GitHub shows it

GitHub announced on its blog in 2013 (the post was updated in 2019) that it renders the YAML metadata at the top of a document as a horizontal table, for easier reading, aimed at the metadata that Jekyll sites on GitHub Pages depend on. The post says this applies to every prose document GitHub supports, not only Markdown. GitHub's writing and formatting docs do not cover front matter, so that announcement is the reference.

## How MiaoYan V4.5.0 treats it

The rule lives in `Note.cleanMetaData` in `Business/Note.swift`. The note is treated as having front matter only if its text begins with `---` followed by a newline, or `---` and a Windows line ending. The code then looks for the next line that starts with `---`, and if that line stands alone, everything up to and including it is dropped. The result is used for the preview, for HTML export and PDF export, which are built on the preview, and for the word count. The editor still shows the raw text, so you keep editing the metadata normally.

The same function has tests in `NoteFrontmatterTests`, which pin the edge cases:

- Any leading block is hidden, with or without a `title:` key.
- A file with no closing fence is left untouched and shows everything.
- A closing line of `----` is not a fence, so the whole note is shown, metadata included.
- A file that is only front matter produces an empty preview.
- Three dashes in the middle of a note stay an ordinary horizontal rule.

MiaoYan does not read the keys. The block is not parsed as YAML, which is why a file that merely has two `---` lines around some text also loses that text in the preview. There is no YAML validation either: a typo that breaks Jekyll will not show up in MiaoYan.

## Slide mode and the `---` separator

In slide mode `---` is also the slide separator. In V4.5.0 the front matter is removed before the text reaches the slide renderer, so a block at the top does not become a slide. The catch is a deck that opens with a `---` line meant as a separator, because if another `---` line follows, everything between the two is taken for front matter and vanishes. Start a deck with its title, and keep metadata in one clean block. The separators themselves are covered in [Markdown to slides](/blog/markdown-to-slides/).

## When it does not work

- **The metadata shows in the preview.** There is a blank line or a space before the first `---`, the closing line is `----` or `...`, or the block uses `+++`.
- **A heading appears above the body.** If the block is not recognized as front matter, a line of text directly followed by `---` is a setext heading in CommonMark, so one of your keys turns into a large heading.
- **A generator ignores the file.** Check for a byte order mark at the start of the file and for an unquoted colon in a value.
- **Text vanished.** Two `---` lines at the top of a note hide everything between them in MiaoYan, even a section that was meant to be body text.

For notes that you also publish elsewhere, see [Markdown cheat sheet](/blog/markdown-cheat-sheet/) for what each renderer adds beyond CommonMark.

## FAQ

### Is front matter part of Markdown?

No. CommonMark does not define it. It is a convention of static site generators and some editors, which strip it before they render the body.

### Can I use `---` as a divider at the top of a note?

Use `***` or put a title first. A note that starts with `---` and has another `---` line later is read as front matter in MiaoYan.

### Does GitHub show front matter in a README?

GitHub's 2013 announcement says YAML metadata at the top of a document is shown as a table. Its writing and formatting docs do not mention front matter.
