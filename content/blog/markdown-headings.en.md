A Markdown heading is one to six `#` characters, a space, and the heading text: `# Title`, `## Section`, `### Subsection`. The space is required, so `#Title` is just a paragraph. There is also an older underline style (setext) that only reaches two levels, and it has one trap: a `---` line directly under a paragraph turns that paragraph into a heading. The rest of the work is structure, because headings are what outline panels, tables of contents and screen readers read.

## ATX headings: the `#` form

The CommonMark spec calls the `#` form an ATX heading. The rules are short:

```markdown
# Heading level 1
## Heading level 2
###### Heading level 6
####### Seven is too many, so this is a paragraph
```

The opening run is one to six `#` characters, and it must be followed by a space or tab (or the end of the line). The spec's own examples show that `#5 bolt` and `#hashtag` are paragraphs, which is a handy fact when you write a note that begins with a hashtag. If a line must begin with a literal `#`, escape the first one with a backslash, `\## foo`; the [escape characters](/blog/markdown-escape-characters/) post lists the others.

You may indent a heading by up to three spaces. Four spaces make it a code block. Spaces and tabs around the text are stripped, and the text is parsed as normal inline Markdown, so emphasis, code spans and links work inside it.

A heading may also be closed with `#` characters, which some people use to make the source look symmetrical:

```markdown
## Install on Mac ##
```

The closing run must be preceded by a space or tab, only spaces or tabs may follow it, and its length does not have to match the opening run. `## Install #on Mac` keeps its `#`, because `#on Mac` is text, not a closing run. A backslash-escaped `#` at the end also does not count as a closer. Most notes leave the closing run out.

ATX headings do not need a blank line around them: the spec's example has `Foo bar`, then `# baz`, then `Bar foo` on consecutive lines and gets a paragraph, an `<h1>` and a paragraph. Leave the blank lines in anyway, because the file reads better.

## Setext headings: the underline form

```markdown
Heading level 1
===============

Heading level 2
---------------
```

A line of text followed by a line of `=` characters is a level 1 heading, and followed by a line of `-` characters is level 2. That is all; there is no level 3. The underline can be any length, may be indented up to three spaces, and cannot contain spaces between its characters (`= =` is not an underline). The text may span several lines, which then form one heading. Setext reads well in plain text, but it stops at two levels, so most notes use `#`.

### The `---` trap

```markdown
My shopping list
---
```

The author usually meant a horizontal line. CommonMark reads it as a level 2 heading, because the setext reading wins over the thematic break reading. With a multi-line paragraph it is worse: in the spec's example, `Foo` and `Bar` on two lines with `---` below become one `<h2>` containing both lines. The fix is a blank line before the dashes, or `***` if you want a rule that cannot be misread. The [horizontal line](/blog/markdown-horizontal-line/) post covers the three rule forms and what MiaoYan does with `---`.

The same effect happens with `===`, which makes a level 1 heading from the paragraph above it. On a line of its own, `===` is plain text.

## Levels and document outline

The heading level is a statement about structure, not size. W3C's accessibility tutorial on headings says the most important heading has rank 1 and the least important rank 6, and a heading of equal or higher rank starts a new section while a lower one starts a subsection. It also advises that skipping ranks, such as an `h2` followed directly by an `h4`, "can be confusing and should be avoided where possible", though it is fine when you close subsections and step back up. The W3C page does not demand a single `h1`; its examples simply use one.

A workable convention for notes and docs:

- One `#` heading as the note title, `##` for the main sections and `###` for subsections, going deeper only when the text really nests.
- Do not choose `###` because it looks smaller; the level is structure, not size.

Outline panels and heading navigation are built from the levels, so a skipped level shows up as a hole in each of them.

## Heading IDs and anchors

To link to a heading you need its ID, and Markdown does not define one. CommonMark has no syntax for heading IDs and says nothing about how they are generated, so every tool decides for itself. GitHub documents its rule: letters are converted to lowercase, spaces become hyphens, other whitespace and punctuation are removed, formatting is stripped so only the text remains, and a duplicate heading gets `-1`, `-2` and so on appended. GitHub also warns that editing a heading, or reordering headings that share the same anchor, changes the anchors, so links to them must be updated.

The attribute-style syntax `## Install {#install}` comes from Pandoc's `header_attributes` extension, which the Pandoc manual says is compatible with PHP Markdown Extra. It is not CommonMark, and on GitHub or in MiaoYan the `{#install}` stays visible as text. If a note has to work in more than one place, put an HTML anchor above the heading instead, `<a id="install" name="install"></a>`. MiaoYan's preview looks the target up by `id`, and GitHub documents custom anchors with the `name` attribute, so writing both covers both places.

Because the ID rules differ, an anchor link can work in one app and break in another. [Links and anchors in Markdown](/blog/markdown-links-and-anchors/) walks through the differences and how to test them, so this post does not repeat them.

## Emphasis, links and code inside headings

Headings accept inline Markdown. `## The *fast* path`, ``## The `--force` flag`` and `## See [the spec](https://spec.commonmark.org/)` all render as expected. Because the anchor is made from the visible text, a heading with a link or code span still produces a plain-text anchor, and rewording the heading breaks links to it. Keep headings as plain labels where you can.

## How MiaoYan uses headings

MiaoYan renders notes with cmark-gfm, so both `#` and underline headings follow CommonMark. These details come from the V4.9.0 source.

- **Editor.** The editor pane colours `#` heading lines and treats the `#` markers as syntax; for underline headings it marks the `===` or `---` line as syntax.
- **Outline panel.** The preview has a table of contents panel that lists `h1`, `h2` and `h3` headings only, built with the tocbot library. It appears when a note has at least two such headings, and the hover trigger that opens it is hidden when the preview is narrower than 600 pixels. Toggle it with Toggle TOC in the View menu (切换目录 under 视图 in the Chinese UI) or `⌘5` while the preview or split view is showing; opening it that way pins it, and the same shortcut closes it. So a note with only a title and `####` sections has no outline, which is one more reason to keep the levels continuous.
- **Preview sizes.** The preview stylesheet sets `h1` to 1.76em, `h2` to 1.41em and `h3` to 1.18em, and `h4` to `h6` to the body size, so `h4`, `h5` and `h6` look identical: bold text at body size.
- **Anchors.** Each heading gets an ID equal to its text, with `-1`, `-2` for repeats, and a small link icon appears beside it on hover in the preview, linking to that fragment. This differs from GitHub's lowercase slug, as the links post explains.

MiaoYan V4.9.0 has no heading folding and no keyboard shortcut for setting a heading level, so you type the `#` characters. See the [Markdown cheat sheet](/blog/markdown-cheat-sheet/) for the other syntax.

## Checking your headings

Open the outline (`⌘5` in MiaoYan, or the Outline button on GitHub) and read it as a list; if it makes sense without the body text, the structure is good. Then look for jumps from `##` to `####`, a `#` at a line start with no space after it, and a stray `---` under a paragraph. Click each in-page link in every place the note is read.

## FAQ

### How many H1 headings should a Markdown file have?

One is the safe convention, as the title of the note. CommonMark allows several, and the W3C headings tutorial does not require just one, but a single `#` keeps the outline readable.

### Why is my `#Heading` not rendering as a heading?

There is no space after the `#`. CommonMark requires a space or tab, so `#Heading` is a paragraph. Write `# Heading`.

### Why did my paragraph turn into a big heading?

You put `---` or `===` directly under it, and it was read as a setext underline. Add a blank line above the dashes.

### Can I set a custom heading ID in Markdown?

Not in CommonMark. `{#id}` works in Pandoc and PHP Markdown Extra. For portable notes, put `<a id="name" name="name"></a>` above the heading.
