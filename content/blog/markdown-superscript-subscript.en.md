Markdown has no syntax for superscript or subscript, so the dependable way is HTML: `x<sup>2</sup>` and `H<sub>2</sub>O`. It works anywhere raw HTML is allowed, GitHub included, and in MiaoYan's preview. The shorter forms, `^2^` and `~2~`, belong to Pandoc and some extensions, and in MiaoYan the tilde form turns into strikethrough instead. For real formulas, use LaTeX math (`$x^2$`) rather than either.

## The four ways to write it

| Method | Superscript | Subscript | Works where |
| --- | --- | --- | --- |
| HTML tags | `x<sup>2</sup>` | `H<sub>2</sub>O` | Any renderer that keeps raw HTML |
| Extension syntax | `2^10^` | `H~2~O` | Pandoc, markdown-it with plugins |
| Unicode characters | `x²` | `H₂O` | Anywhere, for a limited set of characters |
| LaTeX math | `$x^2$` | `$H_2O$` | Renderers with math support |

Core Markdown and the GFM spec define none of the first two rows as syntax. CommonMark has no superscript or subscript, and GFM adds tables, strikethrough, task lists, extended autolinks and a filter for a few raw HTML tags on top of it, with nothing for either. Everything below is a workaround that depends on the tool reading your file, which is why the same note can look right in one app and broken in another. The [CommonMark vs GFM](/blog/commonmark-vs-gfm/) post lists what the two specs do cover.

## HTML tags

`<sup>` and `<sub>` are plain inline HTML, and Markdown passes inline HTML straight through to the output:

```markdown
E = mc<sup>2</sup>

Water is H<sub>2</sub>O.

The 26<sup>th</sup> of March.
```

GitHub's formatting guide lists exactly these two tags for superscript and subscript, so they work in READMEs, issues and comments. Other places differ. A site generator or a note-sharing service that strips HTML will show the tags as text or drop them. When the file will be read somewhere you do not control, this is still the best choice, because a reader who sees the tags unrendered can at least still read `x<sup>2</sup>` as "x squared".

The tags can sit inside a table cell, a list item or a heading. They cannot contain block-level Markdown, which you would not want in an exponent anyway.

## The ^ and ~ extension syntax

Pandoc's Markdown writes superscript between carets and subscript between tildes: `H~2~O is a liquid. 2^10^ is 1024.` The manual adds a rule: the text between the markers may not contain spaces or newlines, and a space has to be escaped with a backslash, so a subscripted "a cat" is written `P~a\ cat~`. The manual gives the reason as preventing accidental superscripting through ordinary use of `~` and `^`.

The markdown-it project has plugins for the same notation: `29^th^` becomes `29<sup>th</sup>` with `markdown-it-sup`, and `H~2~O` becomes `H<sub>2</sub>O` with `markdown-it-sub`. Both say the markup follows Pandoc's definition. They need to be installed and registered, so a tool built on markdown-it does not have them unless its authors added them.

This is where the single tilde becomes a trap. The GFM spec defines strikethrough as text wrapped in a matching pair of one or two tildes, so `~there~` is struck through in a parser that implements GFM strikethrough. A renderer that follows GFM and a renderer that follows Pandoc therefore read `H~2~O` in opposite ways: one produces a subscript, the other produces `H`, a struck-through 2 and `O`. GitHub's documentation also lists `~ ~` next to `~~ ~~` for strikethrough. The [bold, italic and strikethrough](/blog/markdown-bold-italic-strikethrough/) post covers the tilde rules and the `3~5` range problem.

## What MiaoYan's preview renders

MiaoYan's preview in V4.9.0 turns Markdown into HTML with cmark-gfm. In `Business/Markdown.swift` the parser is created with only the footnotes option, and four extensions are attached by name: `table`, `footnotes`, `strikethrough` and `tasklist`. The HTML is rendered with `CMARK_OPT_UNSAFE`, which tells cmark to keep raw HTML instead of replacing it. From that, here is what each form does:

| You write | MiaoYan preview |
| --- | --- |
| `x<sup>2</sup>`, `H<sub>2</sub>O` | Superscript and subscript, drawn by the web view |
| `2^10^` | Literal text, the carets stay |
| `H~2~O` | `H`, a struck-through 2 and `O` |
| `$x^2$`, `$H_2O$` | Typeset by KaTeX |

The single-tilde result follows from the settings, not from a quirk. cmark-gfm's strikethrough extension accepts one tilde on each side unless a separate double-tilde option is set, and the parser here sets only the footnotes option, so `~2~` is struck through. The bundled syntax guide in MiaoYan's Examples folder writes `H<sub>2</sub>O` and `26<sup>th</sup>` for the same reason, and the Chinese guide writes `16<sup>世纪</sup>`. The [cheat sheet](/blog/markdown-cheat-sheet/) and the [underline and color](/blog/markdown-underline-and-color/) post make the same recommendation.

Because the preview does not sanitize HTML, a tag that works there may be removed elsewhere. That matters less for `<sup>` and `<sub>`, which GitHub allows, than for styles and colors.

## Unicode superscripts and subscripts

You can also type the characters directly: `x²`, `m³`, `H₂O`, `10⁻⁶`. They are ordinary text, so they survive every renderer, copy and paste into a chat or a spreadsheet cell, and show up in plain text search. There are three limits.

First, coverage. The digits 0 to 9, the plus, minus and equals signs and parentheses exist in both forms. Superscript lowercase letters exist for all 26 in Unicode 16, though superscript `q` only arrived in Unicode 14 and some fonts lack it. Subscripts are thinner. In Unicode 16 the Latin subscript letters are a, e, h, i, j, k, l, m, n, o, p, r, s, t, u, v and x, so a subscript `b`, `c`, `d` or `g` does not exist as a character.

Second, appearance. These characters come from different Unicode blocks, and a font may draw some of them from a fallback font, so a run such as `x¹²ⁿ` can show uneven sizes and heights. Third, searching: a search for `x2` will not match `x²`, because they are different characters. For a one-off exponent in a chat message they are fine. For a document, use tags or math.

## Math: the right tool for formulas

If the exponent is part of an equation, write it as math. Inside `$...$`, `^` and `_` are LaTeX operators, with braces for more than one character:

```markdown
$x^2$, $x_i$, $x^{10}$, $x_{ij}$

Water is $\text{H}_2\text{O}$.
```

Math gets the right size, spacing and italics for variables, and it combines both on one symbol (`x_i^2`). MiaoYan protects the contents of math ranges from the Markdown parser before it runs, so `_` and `^` inside `$...$` are not mistaken for emphasis. The [LaTeX math in Markdown](/blog/latex-math-in-markdown/) post has the delimiters and the supported functions. For a chemical formula in running text, `H<sub>2</sub>O` is lighter, and math is better when the formula sits next to equations. Plain `$H_2O$` makes the letters italic, as variables are, which is why the example above wraps them in `\text`.

## Footnote markers are a different thing

A footnote marker looks like a superscript but is a link. `[^1]` in the text plus a `[^1]: note` definition produces a small raised number that jumps to the note, with a link back. MiaoYan's cmark-gfm turns each marker into a superscript number automatically, so you never write `<sup>` for it. Typing `<sup>1</sup>` by hand gives a raised 1 that links nowhere. Use footnotes when the reader needs the note, and `<sup>` when the raised text is itself the content, as in `26<sup>th</sup>`. See [Markdown footnotes](/blog/markdown-footnotes/).

## Common problems and how to check

- **The tags appear as text.** The viewer escapes HTML. Switch to Unicode characters, or move the note to a viewer that allows the tags.
- **A struck-through digit where a subscript should be.** You wrote `H~2~O` in a GFM renderer. Replace it with `H<sub>2</sub>O`.
- **Carets stay visible.** The renderer has no `^` extension, which includes MiaoYan. Use `<sup>`.
- **A formula looks italic where you wanted upright.** Wrap words in `\text{}` inside math.
- **Tags work in the preview and not after publishing.** Open the published page and look for the raised text before assuming the file is wrong.

The fastest check is to type all four forms in one note, open the preview and compare. Anything that shows carets, tildes or tag text is not supported by that renderer.

## FAQ

### Does GitHub support superscript and subscript?

Yes, through `<sup>` and `<sub>`, which its formatting guide documents. That guide lists no caret syntax.

### Can I use ^ and ~ in MiaoYan?

No. `^text^` stays literal and `~text~` is struck through. Use `<sup>`, `<sub>` or math.

### How do I write 10 to the power of minus 6?

`10<sup>-6</sup>` in HTML, `10⁻⁶` in Unicode, or `$10^{-6}$` in math. The braces matter in math, because `^-6` would raise only the minus sign.

### Which should I use for a chemical formula?

`H<sub>2</sub>O` in running text, math when the formula appears with equations.
