Markdown has no syntax for underline, text color, centering, font size, superscript, subscript or highlight, so you borrow HTML for all of them: `<u>` or `<ins>` for underline, `<sup>` and `<sub>` for the raised and lowered text, `<mark>` for highlight, `<span style="color:red">` for color, and `<p align="center">` for centering. The catch is that not every place your note is shown accepts every tag. GitHub, for example, keeps `<sup>`, `<sub>` and `<ins>` but drops `style` attributes, and MiaoYan's preview passes raw HTML through but does not understand `==highlight==` or `^sup^`. Pick the form that survives where the note will actually be read.

## Why Markdown leaves these out

John Gruber's original Markdown documentation says the syntax only covers what can be conveyed in plain text, that Markdown is a writing format while HTML is a publishing format, and that for any markup Markdown does not cover you simply use HTML itself. Bold and italic look like emphasis in a plain text email, so they got syntax. Color, size and alignment are presentation, and a note full of presentation stops being easy to read as source.

Underline has a second problem: on the web, underlined text is what a link looks like. MDN's page on the `<u>` element warns against using its default underline in a way that could be confused with a hyperlink, and notes that the element means a non-textual annotation, such as marking a misspelling, not general emphasis. If you want to stress a phrase, bold or italic is usually the better choice, and underline is for the cases where you really need it.

## The HTML fallbacks

| You want | Write | Notes |
|---|---|---|
| Underline | `<u>text</u>` or `<ins>text</ins>` | GitHub documents `<ins>` for underline |
| Superscript | `x<sup>2</sup>` | Works almost everywhere |
| Subscript | `H<sub>2</sub>O` | Works almost everywhere |
| Highlight | `<mark>text</mark>` | Marks text as highlighted |
| Color | `<span style="color:red">text</span>` | Needs a renderer that keeps `style` |
| Center | `<p align="center">text</p>` | `align` is old but widely accepted |
| Smaller text | `<small>text</small>` | Not a precise size |

Inline tags go inside a paragraph and need no blank lines. Block tags such as `<p>` and `<div>` start an HTML block, and that block ends at the next blank line, which matters for the next section.

## Centering and the blank line rule

```markdown
<p align="center">A centered line.</p>

<div align="center">

Markdown **works** in here because of the blank lines.

</div>
```

A line that starts with `<div` or `<p` begins an HTML block in CommonMark, and everything up to the first blank line is copied through as raw HTML without Markdown parsing. So `**bold**` directly after `<div align="center">` stays as literal asterisks. Put a blank line after the opening tag and before the closing one and the content in between is parsed as Markdown again. The [collapsible sections](/blog/markdown-collapsible-sections/) post explains the same rule for `<details>`.

In MiaoYan's preview, `<p align="center">` and the paragraphs inside `<div align="center">` are centered, and the same holds for `left` and `right`. The preview's stylesheet sets paragraphs to left-aligned and has explicit rules for those three `align` values. `<center>` and `<font>` are old HTML tags that GitHub removes, keeping only the text, so prefer `align` for centering.

## What MiaoYan renders

MiaoYan's preview turns Markdown into HTML with cmark-gfm and asks it to keep raw HTML (the `CMARK_OPT_UNSAFE` flag), so tags such as `<u>`, `<mark>`, `<sup>`, `<sub>` and `<span style="...">` reach the preview's web view and the browser engine draws them. The parser has four extensions turned on, which are table, footnotes, strikethrough and tasklist. None of them adds underline, highlight, superscript or subscript.

That has two consequences. `==highlight==` and `^sup^` stay as literal text. And the single-tilde subscript form from other editors, `H~2~O`, does not become a subscript either: the strikethrough extension accepts one tilde on each side as well as two, so it reads `~2~` as struck-through text. The syntax guide that V4.5.0 puts in its Examples folder writes `H~2~O` and `26^th^` (the Chinese guide writes `16^世纪^`), but the preview does not render them as subscript and superscript, and the [cheat sheet](/blog/markdown-cheat-sheet/) tells you to use `<sub>` and `<sup>` instead.

Because the preview does not sanitize HTML, it is a good place to try an idea and a poor place to learn what other readers will see. Anything that works only because the app lets it through will break when you publish the same file somewhere stricter.

## What GitHub keeps and strips

GitHub documents three of these in its basic formatting guide: `<sub>`, `<sup>` and `<ins>`, the last one for underline. Its markup project adds that rendered HTML is sanitized and that inline styles are removed. Rendering a sample through GitHub's Markdown API shows the rest:

- `<ins>`, `<sup>`, `<sub>` and `<mark>` are kept.
- `<u>` and `<small>` lose their tags, so the text stays but the underline or smaller size does not.
- `<span style="color:red">` keeps the text and loses the color.
- `align="center"` is kept, which is why centered README logos work.
- `H~2~O` becomes struck-through text there too, since GitHub also reads single tildes as strikethrough.

GitHub does give you one color feature of its own: in issues, pull requests and discussions, a HEX, RGB or HSL value in backticks, such as `#0969DA`, shows a small color swatch next to it. That marks a color; it does not tint text.

Typora's reference, by comparison, says plainly that you can use `<span style="color:red">` for color and `<u>` for underline.

## Extensions that exist elsewhere

Several editors define their own short syntax. They work only where the renderer enables them:

| Feature | Syntax | Where |
|---|---|---|
| Highlight | `==text==` | Pandoc `mark` extension, Typora (turn on in Preferences) |
| Superscript | `x^2^` | Pandoc, Typora (turn on in Preferences) |
| Subscript | `H~2~O` | Pandoc, Typora (turn on in Preferences) |
| Underline | `[text]{.underline}` | Pandoc, with the bracketed spans extension |

Pandoc's manual adds that spaces inside `^...^` or `~...~` must be escaped with a backslash, as in `P~a\ cat~`. These forms are tidy to type but unreadable to any tool that does not know them, which is a good reason to keep the HTML versions in notes you plan to move between apps.

## Math as a way to get superscripts

If your notes already use formulas, `$x^2$` and `$x_i$` give superscripts and subscripts without any HTML, and MiaoYan renders them with the bundled KaTeX. KaTeX also supports `\mathrm{}` for upright text and `\textcolor{blue}{...}` for color, so `$\textcolor{blue}{F=ma}$` colors a formula. This is the right tool for formulas and a clumsy one for ordinary words, because math mode uses math fonts and spacing. See [LaTeX math in Markdown](/blog/latex-math-in-markdown/) for the delimiters and pitfalls.

## Keeping notes portable

- Prefer semantic HTML (`<mark>`, `<sup>`, `<ins>`) over `style` attributes, since more renderers keep it.
- Avoid hard-coded colors if you read in both light and dark themes, since a dark red tuned for white can vanish on a dark background.
- Use bold or italic when the goal is emphasis, and reserve color for the rare case that needs it.
- Test a note in the strictest place it will appear, such as the GitHub preview, before relying on a tag.
- Escape literal characters you do not want parsed, as covered in [escape characters](/blog/markdown-escape-characters/).

## FAQ

### Is there a Markdown syntax for underline?

No. Neither CommonMark nor GFM defines one. Use `<u>` or `<ins>`, or Pandoc's `[text]{.underline}` when you convert with Pandoc.

### Why does my red text show as black on GitHub?

GitHub's sanitizer removes `style` attributes, so the span stays but its color is dropped. Use bold or a callout, or publish the note somewhere that keeps inline styles.

### Can I write H2O with a real subscript in MiaoYan?

Yes, with `H<sub>2</sub>O`, or with `$\mathrm{H_2O}$` if you are already in math mode. The `H~2~O` form is read as strikethrough in MiaoYan.
