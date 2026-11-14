A Markdown callout is a block quote whose first line is a marker such as `> [!NOTE]`, and the app turns it into a coloured box with an icon. There is no single standard behind it. GitHub defined five types (NOTE, TIP, IMPORTANT, WARNING, CAUTION), Obsidian has its own larger set with titles and folding, and documentation generators such as MkDocs Material and Docusaurus use entirely different syntax. The safe rule is to pick the dialect of the place where the note will be read, and to write it so the fallback, a plain quote, still makes sense.

This post is about the differences between those dialects. The basics of quotes and the short `[!NOTE]` section are in [Markdown blockquotes and nested lists](/blog/markdown-blockquotes-and-nested-lists/).

## GitHub alerts

GitHub calls them alerts and documents them on its basic writing and formatting syntax page as a Markdown extension built on blockquote syntax. There are five types, each written as a quote with the type on the first line:

```markdown
> [!NOTE]
> Useful information that users should know, even when skimming content.

> [!TIP]
> Helpful advice for doing things better or more easily.

> [!IMPORTANT]
> Key information users need to know to achieve their goal.

> [!WARNING]
> Urgent info that needs immediate user attention to avoid problems.

> [!CAUTION]
> Advises about risks or negative outcomes of certain actions.
```

The type is a fixed list, and anything else is not an alert. The docs describe the marker as its own quote line with the body in the lines after it, and GitHub's syntax as documented has no custom title and no folding. The docs add three rules of use. Use alerts only when they are crucial for the reader's success, keep them to one or two per article, and do not place them back to back. They also say that alerts cannot be nested within other elements, so a callout inside a list item or inside another quote is outside what GitHub promises.

The docs page does not list the surfaces where alerts render, only that they are displayed with distinct colours and icons on GitHub. If a note will end up in a README, an issue, a pull request or a wiki, paste a test alert there and look, rather than assuming.

## Obsidian callouts

Obsidian reads the same `> [!type]` opening but goes further, according to its Callouts help page. The type is case-insensitive and drawn from a longer list: `note`, `abstract`, `info`, `todo`, `tip`, `success`, `question`, `warning`, `failure`, `danger`, `bug`, `example` and `quote`, plus aliases. Among the aliases, `summary` and `tldr` map to `abstract`, `hint` and `important` map to `tip`, and `caution` and `attention` map to `warning`. A type Obsidian does not know falls back to `note`.

Text after the marker becomes the title, and a `+` or `-` directly after the marker makes the callout foldable, open or closed by default:

```markdown
> [!tip] Callouts can have custom titles
> Like this one.

> [!faq]- Are callouts foldable?
> Yes. The contents are hidden while it is collapsed.

> [!question] Can callouts be nested?
>
> > [!todo] Yes, they can.
```

Obsidian does nest callouts, and you can define your own types with a CSS snippet that sets `--callout-color` and `--callout-icon` on a `data-callout` value.

The overlap with GitHub is real but partial. `[!NOTE]`, `[!TIP]` and `[!WARNING]` mean roughly the same in both. `[!IMPORTANT]` is its own type on GitHub and an alias of `tip` in Obsidian, so the same note changes colour and icon when it moves. `[!CAUTION]` is its own type on GitHub and an alias of `warning` in Obsidian. Titles, folding and most Obsidian types do not exist on GitHub.

## MkDocs Material and Docusaurus

Documentation generators use their own syntax, and it is not block quotes at all.

MkDocs Material calls them admonitions. You enable the `admonition` extension in `mkdocs.yml` (with `pymdownx.details` for collapsible ones and `pymdownx.superfences` for nesting arbitrary content), and then write the content indented by four spaces:

```markdown
!!! note "Optional title"
    Content here.

??? tip
    Collapsed by default.

???+ tip
    Expanded by default.
```

An empty string after the type removes the title. Its types are `note`, `abstract`, `info`, `tip`, `success`, `question`, `warning`, `failure`, `danger`, `bug`, `example` and `quote`.

Docusaurus uses three colons, with a keyword from `note`, `tip`, `info`, `warning` and `danger`, and a title in square brackets:

```markdown
:::note[Your title]

Markdown works inside.

:::
```

The Docusaurus docs ask for blank lines around the opening and closing lines because Prettier can break the syntax, and a nested admonition needs more colons on the parent than on the child.

These are build-time features of a site generator. They are the right choice when you publish documentation through that tool, and a poor one for a note you open in an editor, because nothing outside the tool understands them.

## What each dialect looks like where it is not understood

Every one of these is plain text to a parser that does not know it, and the readable result differs:

| Written as | In a renderer without support |
| --- | --- |
| `> [!NOTE]` and a body line | A normal quote that starts with the literal text `[!NOTE]` |
| `> [!tip]- Title` | A normal quote with `[!tip]- Title` as its first line |
| `!!! note` and indented text | Ordinary text starting with `!!! note`; the indented body may show as plain text or as a code block, depending on the blank lines |
| `:::note` ... `:::` | Paragraphs containing the colons and the word |

The GitHub form degrades best, because the quote itself survives and the marker word is a readable label. That is the practical reason to prefer it for notes that travel. The admonition forms fail worse, since the four-space body can end up as a code block. For files read in several apps, see [CommonMark vs GFM](/blog/commonmark-vs-gfm/) for which features count as standard.

## What MiaoYan does with them

MiaoYan 4.9.0 supports the GitHub form and nothing else from this list. The source shows how. After cmark-gfm renders the note, a post-processing function looks for a `<blockquote>` whose first paragraph starts with `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` or `[!CAUTION]`, matched in any letter case, and rewrites it as a `div` with a title row and an icon. Because it runs on the rendered HTML, a marker inside a fenced code block never matches, and the test suite checks that. A quote nested inside an alert stays a quote. The five colours are blue, green, purple, amber and red.

Things the code does not do. An unknown word such as `[!DANGER]` stays an ordinary quote, as do Obsidian's `+` and `-` fold markers, because a marker followed directly by another character is not converted. There is no custom title and no folding, and the `!!!` and `:::` forms are not recognized, so they show as text. One edge worth knowing from the code: a space after the marker is accepted, so a line like `> [!tip] My title` becomes a Tip box whose body begins with "My title", not a box titled "My title". Write the body on the next line, which is the form GitHub documents.

If you need a fold in a note, use a `<details>` block as described in [Markdown collapsible sections](/blog/markdown-collapsible-sections/); it works in MiaoYan's preview and on GitHub.

## Choosing and checking

Pick by the destination. A README or a file in a repository wants the GitHub form. A vault that lives in Obsidian can use its full set, and you accept that other apps show the marker. A documentation site uses whatever its generator defines. For a note that moves between tools, use the five GitHub types and put the key sentence in the body, not in a title.

To check, open the note in each place it will be read. A box with an icon means the dialect is supported. A quote showing `[!NOTE]` as text means it is not, and nothing is broken. A stray character right after the marker, a misspelled type, or, on GitHub, a callout indented under a list item are the usual reasons one does not appear.

## FAQ

### What types does GitHub support?

Five: NOTE, TIP, IMPORTANT, WARNING and CAUTION. The marker goes alone on the first line of a block quote.

### Can I give a GitHub alert a custom title?

Not in GitHub's syntax as documented. The type word is the title. Obsidian and MkDocs Material allow custom titles.

### Why does my callout show as a plain quote with [!NOTE]?

The app does not implement the syntax, or the marker is not an exact match for a type it knows. Check the spelling and that the body follows on the next line.

### Do callouts work in every Markdown editor?

No. They are extensions, and each dialect is understood only by the tools built for it.
