There is no highlight syntax in Markdown. Neither CommonMark nor GitHub Flavored Markdown defines one, so the portable way is the HTML tag `<mark>text</mark>`, which GitHub, MiaoYan and many other renderers keep. The shorter `==text==` form only works where the app or converter has switched on an extension, such as Obsidian, Pandoc or markdown-it with a plugin. In a renderer without that extension the equals signs show up as literal text. Pick the form by where the note will be read, and use bold when you only need emphasis.

## Why `==text==` is not standard

CommonMark has emphasis, strong emphasis and code spans, and GFM adds strikethrough, tables, task lists and autolinks on top. Highlighting is in neither list. The [CommonMark vs GFM](/blog/commonmark-vs-gfm/) post covers what each one adds. Everything else is a tool-specific extension, and `==` is the most common one. It is popular because it reads well in plain text, but a parser that does not know it passes the characters through unchanged.

GitHub's formatting guide lists headings, bold, italic, strikethrough, quotes, code and so on, and has no entry for highlighting. A file with `==important==` in a README shows the equals signs on github.com.

## Where `==text==` works

| Tool | Status | Source of the claim |
| --- | --- | --- |
| Obsidian | Built in: `==Highlighted text==` | Obsidian Help, Basic formatting syntax |
| Pandoc | The `mark` extension, which is switched on explicitly | Pandoc User's Guide, extension `mark` |
| markdown-it | Plugin `markdown-it-mark` | The plugin's README |
| GitHub | Not supported | GitHub Docs, Basic writing and formatting syntax |
| MiaoYan | Not supported, stays literal | See below |

Obsidian's help page lists highlight in its table of formatting syntax, next to bold and strikethrough, and adds one thing most people miss: highlights support six colours, chosen by putting a colour emoji right after the opening `==`, as in `==🔴Important==`. Without an emoji the highlight uses the theme colour. That colour trick is Obsidian's own, and it will not mean anything in another app.

Pandoc's manual describes the `mark` extension in one sentence: to highlight a section of text, begin and end it with `==`. The manual files it under non-default extensions, so you name it yourself, as in `pandoc -f markdown+mark`. The `markdown-it-mark` README says `==marked==` becomes `<mark>inserted</mark>` and that the markup follows the same conditions as CommonMark emphasis. The practical meaning is that the delimiters have to touch the text, so `== spaced ==` does not highlight, for the same reason `** spaced **` does not make bold. The [bold, italic and strikethrough](/blog/markdown-bold-italic-strikethrough/) post explains those flanking rules.

Notice what all three extensions produce: an HTML `<mark>` element. The short syntax is a shortcut for the tag, which is why the tag is the better thing to learn first.

## The portable option: `<mark>`

```markdown
Remember to <mark>back up the folder</mark> before you rename it.
```

`<mark>` is a standard HTML element for text marked or highlighted because it is relevant in its context, which is exactly what a highlighter pen does. Because it is inline, you can put it inside a sentence, a list item or a table cell without blank lines around it.

The catch is renderers that strip HTML. What survives depends on the renderer. Sending a sample to GitHub's Markdown API shows this:

- `<mark>` is kept, so the highlight shows on GitHub.
- `<mark style="background:red">` keeps the tag but loses the `style` attribute, so the colour you asked for is gone. The README of GitHub's markup library says GitHub sanitizes the rendered HTML and removes inline styles and `class` and `id` attributes.
- `<span style="background:yellow">` keeps the text and loses both the tag and the colour.
- `==hi==` stays as literal text.

On a site or app with a stricter sanitizer, the tag may disappear and leave plain text, which is a reasonable failure: the sentence still reads correctly, only the emphasis is gone. If highlighting must survive anywhere, put a second cue in the text itself, such as bold.

## Changing the colour with CSS

The colour of a highlight is CSS, and Markdown has nothing to say about it. Where the renderer keeps inline styles, you can set the background yourself:

```markdown
<mark style="background: #cdeccd; color: inherit">done</mark>
```

Where it removes them, as GitHub does, you are limited to the default. On a page whose stylesheet you control, such as an exported HTML file, you can style `mark` once for the whole page instead of every occurrence:

```css
mark {
  background: #cdeccd;
  color: inherit;
}
```

A pale background under light text is unreadable, so in a page that has a dark theme, set the text colour as well as the background. For coloured text and underline, which is the other half of this question, see [underline and colour in Markdown](/blog/markdown-underline-and-color/).

## How MiaoYan treats highlights

MiaoYan converts Markdown with cmark-gfm and asks it to keep raw HTML. The parser has four extensions on, which are table, footnotes, strikethrough and tasklist, and none of them handles `==`. So `==text==` is shown as typed in the preview, and `<mark>text</mark>` is turned into a highlight by the web view.

The preview styles `<mark>` itself. In the light theme it is a yellow background (`rgba(255, 247, 0, 0.88)`) with a pixel or two of padding and the surrounding text colour. In the dark theme it is a dark olive background (`rgba(77, 74, 0, 0.88)`), so light text stays readable. PDF export always uses the light yellow with the print ink colour, since the dark olive would otherwise come out as dark on dark. An inline `style` on the tag is not removed, and inline styles beat the stylesheet, so a `style="background: ..."` on a `<mark>` overrides the theme colour in the preview. It will not carry over to a stricter site later. The [Markdown to PDF](/blog/markdown-to-pdf-mac/) post covers the export steps.

A note moved from Obsidian will therefore show its `==text==` highlights as literal equals signs in MiaoYan, and they need to be changed to `<mark>` tags by hand or with a find and replace.

## Alternatives to a highlight

Often the right answer is to avoid the highlight.

- **Bold** is the portable choice and works everywhere, including in plain text. It also survives copy and paste.
- **A code span** such as `` `back up first` `` draws a grey box in most renderers. It is meant for code, so use it for commands, file names and keys, not as a general highlight.
- **A blockquote** sets a passage apart as a block, and a callout does it with a label: `> [!NOTE]` and four other types render as coloured boxes on GitHub and in MiaoYan, and appear as an ordinary quote with `[!NOTE]` in it elsewhere. See [blockquotes and nested lists](/blog/markdown-blockquotes-and-nested-lists/) for the rules.
- **Strikethrough** is the right marker for text that is removed, and works in GFM: `~~old~~`.

## Highlighting lines in a code block

A highlight inside a fenced code block is a different problem, because Markdown does not parse the inside of a fence. The common case is showing changes, and for that there is the `diff` language:

````markdown
```diff
- timeout: 30
+ timeout: 60
```
````

Lines that begin with `-` are drawn as removed and lines that begin with `+` as added. This is a convention of the syntax highlighter, not a Markdown feature, so it works wherever the highlighter ships a diff definition. GitHub renders it with its own diff colours, and MiaoYan's bundled highlight.js registers Diff and gives those lines its `addition` and `deletion` token colours, which are text colours without a background band. More on fence names is in [code blocks in Markdown](/blog/markdown-code-blocks/).

## FAQ

### What is the Markdown syntax for highlighting text?

None is defined by CommonMark or GFM. Use `<mark>text</mark>`, or `==text==` if the tool you use supports it, such as Obsidian.

### Why do I see ==text== instead of a highlight?

The renderer does not have the mark extension. Replace the equals signs with `<mark>` tags, or turn the extension on if the tool has one, as Pandoc does with `+mark`.

### Does GitHub support highlighted text in Markdown?

Not with `==`. The `<mark>` tag is kept, but a colour set with a `style` attribute is removed.

### Can I highlight text in a different colour?

Only through CSS, either an inline `style` or a stylesheet, and only where the renderer keeps it. Obsidian has its own colour emoji after `==`, which works only there.
