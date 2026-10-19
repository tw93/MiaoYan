A Markdown link is `[text](destination)`. The destination can be a web address, a relative path to another file, or `#something` to jump inside the same document. The first two are standardized. The third is not: CommonMark says nothing about how a heading becomes an anchor, so `#my-heading` works on GitHub, depends on the tool elsewhere, and in MiaoYan's preview follows its own rule, covered below.

## The link forms

An inline link puts the destination right after the text, with an optional title in quotes:

```markdown
[MiaoYan on GitHub](https://github.com/tw93/MiaoYan "Source and releases")
```

The title may be in double quotes, single quotes or parentheses, and it must be separated from the destination by a space. Most renderers show it as a tooltip, so do not put anything the reader needs only there.

A reference link moves the destination out of the sentence, which keeps long URLs from cluttering a paragraph and lets several links share one address:

```markdown
Read the [spec][cm] and the [GFM spec][gfm].

[cm]: https://spec.commonmark.org/
[gfm]: https://github.github.com/gfm/ "GitHub Flavored Markdown"
```

Definitions are not rendered and may sit before or after the links that use them, so many writers collect them at the bottom of the note. An autolink wraps a URL in angle brackets, `<https://example.com>`, and uses the URL itself as the text.

## Bare URLs are not the same as links

GitHub turns a plain `https://example.com` into a link, because GFM adds an autolink extension on top of CommonMark. Not every renderer includes it. MiaoYan's renderer attaches four GFM extensions, tables, footnotes, strikethrough and task lists, and no autolink extension, so in the preview and in HTML export a bare address is plain text. The editor pane does turn it into a clickable link, so a URL that works while you type can lose its link once rendered. If a URL must be clickable everywhere, write `<https://example.com>` or `[text](https://example.com)`.

## Spaces and parentheses in destinations

A destination cannot contain a space unless it is wrapped in angle brackets, and it may contain parentheses only if they are balanced or backslash-escaped. Three ways to write the same file name:

```markdown
[Report](<Q3 report (final).md>)
[Report](Q3%20report%20%28final%29.md)
[Report](Q3%20report%20\(final\).md)
```

The angle-bracket form is the most readable. Percent-encoding works in every renderer but hides the name. Prefer file names without spaces or brackets in notes you plan to link, and the problem disappears.

## Linking to a heading

Headings have no anchor in the CommonMark spec; each tool decides. GitHub documents its rules: letters are converted to lower case, spaces become hyphens, other punctuation and whitespace are removed, markup is stripped, leading and trailing whitespace goes, and a repeated heading gets `-1`, `-2` and so on. Its own example links the heading "This'll be a _Helpful_ Section About the Greek Letter Θ!" as `#thisll-be-a-helpful-section-about-the-greek-letter-Θ`. The example keeps the Greek letter Θ in the anchor, so non-ASCII letters are not stripped, and a Chinese heading such as 快速开始 should be linked as `#快速开始`.

```markdown
## Install on Mac

[Jump to install](#install-on-mac)
```

To see the anchor GitHub generated, hover over the heading and click the link icon; the address bar then shows it. For a stable target that does not change when you reword a heading, GitHub also supports a custom anchor written as `<a name="unique-name"></a>`, which is linked with `#unique-name`. Custom anchors are not included in the generated table of contents.

## How MiaoYan's preview handles anchors

The preview does not use GitHub's slug. In the preview script, each heading gets an `id` equal to its visible text with the outer whitespace trimmed, and a repeated heading gets `-1`, `-2` and so on. Clicks on links that begin with `#` are intercepted, the fragment is URL-decoded, and the page scrolls smoothly to the element it selects.

Three consequences follow from that, read from the source at V4.5.0. A GitHub-style `#install-on-mac` does not match a heading whose id is `Install on Mac`. A fragment with a space in it, such as the decoded `#Install on Mac`, is read as a selector for nested elements and matches nothing, so a heading with several words has no reliable fragment link in the preview. A heading that is one word, or Chinese text with no spaces, works with the text exactly as written: `#Install` or `#快速开始`. If you need a multi-word target in MiaoYan's preview, write `<a id="install"></a>` above the heading and link to `#install`; raw HTML is passed through, and the id is what the preview selects. GitHub documents the `name` attribute for custom anchors, so write both attributes if the note must work in both places.

This is the one place where a note can look right in MiaoYan and break on GitHub, or the reverse. Test the links where the note will be read.

## Relative links and links to other notes

On GitHub a relative link such as `[Guide](docs/guide.md)` is resolved against the current file and rewritten for the branch you are viewing, and a path starting with `/` is relative to the repository root. That is why relative links are the right choice for files in a repository. The link text has to stay on one line.

MiaoYan's preview is a web view loaded from a copy of the app's preview files in its cache folder, not from your note's folder, and any clicked link is handed to macOS to open. Web addresses open in your default browser. A relative path to another `.md` file is not resolved against the note's folder in the preview, so it is not a reliable way to jump between notes. Local images are different: the preview rewrites them against the note's project folder, as described in [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/).

For jumping between notes, MiaoYan uses wikilinks: `[[Note title]]`. Clicking one in the editor pane opens the note with that exact title, and the preview rewrites each one into a `miaoyan://goto/` link before rendering, so it is clickable there too. They are not standard Markdown, so a viewer that does not know them shows the brackets. [Wikilinks and backlinks](/blog/wikilinks-and-backlinks/) covers the trade-offs. If the notes also have to work as files on GitHub, use relative Markdown links there and accept that they are for GitHub, not for clicking inside MiaoYan.

## Checking links

Open the rendered page and click each one. In MiaoYan, click a heading link in the preview; if nothing scrolls, the fragment does not match an id. On GitHub, copy the anchor from the heading's link icon instead of guessing the slug. For links that mix punctuation, spaces and non-ASCII text, encode the destination or use angle brackets, and prefer short headings so the slug is predictable. The [Markdown cheat sheet](/blog/markdown-cheat-sheet/) lists the other syntax MiaoYan renders.

## FAQ

### How do I link to a heading in Markdown?

Use `[text](#heading-slug)`. On GitHub the slug is the heading in lower case with hyphens for spaces and punctuation removed. Other tools differ, so check where the note is read.

### Why does my anchor link not work in MiaoYan?

The preview uses the heading text as its id, not a lower-case slug, and a fragment with a space cannot be selected. Link a one-word heading as written, or add `<a id="name"></a>` above it.

### How do I put spaces in a Markdown link?

Wrap the destination in angle brackets, `[text](<my file.md>)`, or write `%20` for each space.

### Do bare URLs become links?

On GitHub yes. In MiaoYan's preview no. Wrap them in angle brackets.
