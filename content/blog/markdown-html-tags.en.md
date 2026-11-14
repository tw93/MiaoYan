Yes, you can use HTML in Markdown. CommonMark defines raw HTML as part of the language, in two forms: a tag inside a paragraph is passed through, and a tag at the start of a line can begin an HTML block that is copied through untouched. What differs is the viewer. GFM filters nine tags, GitHub sanitizes much more, and MiaoYan's preview passes everything through, so a note can look right in one place and lose its HTML in another.

## Two kinds of raw HTML

The [CommonMark spec](https://spec.commonmark.org/0.31.2/) treats HTML in two places. Section 6.6, Raw HTML, covers inline HTML: text between `<` and `>` that looks like a tag is rendered without escaping. Tag names are not limited to real HTML elements, so `<Warning>` counts. The grammar covers open and closing tags, comments, processing instructions, declarations and CDATA. The content between two inline tags is still Markdown, so `<span>**bold**</span>` on one line gives bold text inside the span.

Section 4.6, HTML blocks, covers HTML that begins a line. There are seven start conditions, each with its own end condition, and the line may be indented by up to three spaces:

| Type | Starts with | Ends at |
|---|---|---|
| 1 | `<pre`, `<script`, `<style` or `<textarea` | a line containing `</pre>`, `</script>`, `</style>` or `</textarea>`, which need not match the start tag |
| 2 | `<!--` | a line containing `-->` |
| 3 | `<?` | a line containing `?>` |
| 4 | `<!` and an ASCII letter | a line containing `>` |
| 5 | `<![CDATA[` | a line containing `]]>` |
| 6 | `<` or `</` and one of 62 block names such as `div`, `p`, `table`, `details`, `summary`, `ul`, `h1` to `h6` | a blank line |
| 7 | any other complete open or closing tag, alone on its line | a blank line |

Types 1 to 5 can contain blank lines, which is why a comment or a `<script>` can span paragraphs. Types 6 and 7 cannot. A type 7 block also cannot interrupt a paragraph (Example 187), so a tag on the line after text stays inline HTML.

## Why a blank line ends the block, and why the inside is not parsed

Inside an HTML block, Markdown is switched off. The spec says everything up to the end condition is passed through as raw HTML, and Example 161 shows a fenced code block that stays literal because it sits in the block. This is the rule that bites:

```markdown
<div>
**not bold**
</div>

<div>

**bold**

</div>
```

The first `<div>` starts a type 6 block that runs to the first blank line, so the asterisks stay as typed. In the second, the blank line after `<div>` closes the block, `**bold**` becomes a normal paragraph, and the blank line before `</div>` lets the closing tag start its own block. Spec Example 152 has the same shape.

The spec says these rules are designed for tags that can work as either block-level or inline-level elements, and uses `<del>` to show it. On a line by itself, `<del>` starts a block and `*foo*` stays literal (Example 166). With blank lines around the content, only the tag lines are raw and the content is Markdown (Example 167). On one line, `<del>*foo*</del>` is inline HTML and the content is parsed (Example 168).

Two traps follow. A tag the spec does not list as a block name, such as `<a href="foo">` or `<kbd>`, starts a block only when it is complete and alone on its line (Examples 162 to 165). And a `<div>` never needs its closing tag, because the block ends at the next blank line either way (Example 155). [Collapsible sections](/blog/markdown-collapsible-sections/) shows how this rule shapes `<details>` and `<summary>`.

## What GFM filters

The [GFM spec](https://github.github.com/gfm/) adds an extension in section 6.11, Disallowed Raw HTML, usually called tagfilter. These tags are filtered when HTML is rendered:

```text
<title> <textarea> <style> <xmp> <iframe> <noembed> <noframes> <script> <plaintext>
```

Filtering replaces the leading `<` with `&lt;`, so the tag shows up as visible text and does not run. The spec picks them because they change how the HTML nested inside them is interpreted, and leaves every other tag untouched. Matching is case-insensitive: the spec's own example disallows both `<xmp>` and `<XMP>`.

A parser decides whether to attach the extension, and a renderer that skips it passes `<script>` through.

## What GitHub removes on top

GitHub applies the filter and then sanitizes the result. The [github/markup README](https://github.com/github/markup) says the HTML is sanitized, "aggressively removing things that could harm you and your kin", and lists `script` tags, inline styles, and `class` or `id` attributes. A check on 2026-11-14 with GitHub's Markdown API, `gh api markdown -f text='...' -f mode=gfm`, gave the results below, which differ from that sentence in one place.

| Input | GitHub returned |
|---|---|
| `<script>alert(1)</script>` | `&lt;script&gt;alert(1)&lt;/script&gt;`, shown as text |
| `<style>p{color:red}</style>`, `<iframe ...>` | the same, shown as text |
| `<span style="color:red">red</span>` | `<span>red</span>`, style gone |
| `<div style="color:red" class="foo" onclick="alert(1)" id="d1">` | `<div id="user-content-d1">`, style, class and onclick gone |
| `<img src="a.png" width="120" style="border:1px solid red">` | `width` kept, the `style` attribute gone, GitHub adds its own `max-width` style and wraps the image in a link |
| `<a href="javascript:alert(1)">js</a>` | the text `js`, no link |
| `<a name="top"></a>` | `<a name="user-content-top"></a>` |
| `<u>`, `<small>`, `<abbr>`, `<center>`, `<font>` | the tags are removed, the text stays |
| `<kbd>`, `<sup>`, `<sub>`, `<mark>`, `<details open>`, `<br>`, `<p align="center">` | kept |

So `id` is kept with a `user-content-` prefix rather than removed. GitHub's [basic formatting guide](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax) documents `<sub>`, `<sup>` and `<ins>`, custom anchors written as `<a name="...">`, and `<br/>` for line breaks. The rest comes from the API output, which may change, so treat it as a snapshot and test a file in the repository you care about.

## Tags that work widely

This table lists the HTML most notes actually need and where each one is explained. "GitHub" is the API result above.

| Tag | Use | GitHub | MiaoYan preview | More |
|---|---|---|---|---|
| `<kbd>` | A key such as `Cmd` | kept | passes through, no preview CSS rule for it | |
| `<sup>`, `<sub>` | Footnote marks, `H<sub>2</sub>O` | kept | passes through | [underline and color](/blog/markdown-underline-and-color/) |
| `<mark>` | Highlight | kept | passes through, yellow background | [underline and color](/blog/markdown-underline-and-color/) |
| `<details>`, `<summary>` | Collapsible block | kept | passes through | [collapsible sections](/blog/markdown-collapsible-sections/) |
| `<br>` | Line break, also inside a table cell | kept | passes through | |
| `<img width="...">` | Image size | width kept, style dropped | passes through, width capped at the column | [images](/blog/markdown-images/) |
| `<a name="...">` | Jump target | kept, name prefixed | passes through, but in-note links look up `id` | [links and anchors](/blog/markdown-links-and-anchors/) |

Prefer semantic tags over `style` attributes. `<mark>` survives on GitHub; `<span style="color:red">` keeps its text and loses the color.

## What MiaoYan does with HTML

In V4.9.0 the preview parses with cmark-gfm and attaches four extensions by name, `table`, `footnotes`, `strikethrough` and `tasklist` (`Business/Markdown.swift`, line 22). Tagfilter is not among them. The render call passes `CMARK_OPT_UNSAFE`, and cmark's default would instead replace raw HTML with a placeholder. So every tag and every attribute reaches the preview, `style` and `iframe` included.

Apart from rewriting image addresses, nothing between the parser and the screen changes it. The rendered HTML is substituted into the `DOWN_HTML` slot of the preview template, written to a temporary `index-<uuid>.html` and opened with `loadFileURL`, with read access set to `/`, in a web view whose configuration sets `allowsContentJavaScript` to true. The template declares no Content-Security-Policy, and no step on that path removes `script` tags.

The same renderer feeds PDF and HTML export, as [Markdown to HTML](/blog/markdown-to-html/) explains.

## When the HTML does not show up

- **Markdown inside a block stays literal.** Add the blank lines from the section above, or move the tag and its content onto one line.
- **The tag appears as text.** A tagfilter renderer replaced the `<`. Use a tag outside the list of nine.
- **The tag disappears but the text stays.** A sanitizer, as on GitHub, removed it. Switch to a tag the target keeps.
- **The style is gone.** Inline styles are removed on GitHub. Use `<mark>`, `<ins>` or `align` instead.
- **It works in MiaoYan and nowhere else.** The preview allows everything. Check the file where readers will see it.

## FAQ

### Can you use HTML in Markdown?

Yes. CommonMark allows inline HTML and HTML blocks. Whether a given tag appears is up to the renderer.

### Why is my Markdown inside an HTML tag not rendering?

The tag started an HTML block, and the block runs to the next blank line with Markdown switched off. Put a blank line after the opening tag.

### Why does GitHub show `<script>` as text?

GFM's tagfilter replaces the `<` of nine tags with `&lt;`, and GitHub sanitizes the output further.

### Does MiaoYan strip HTML from notes?

No. The preview keeps raw HTML and attributes. It is a good place to try a tag and a poor place to learn what other readers will see.
