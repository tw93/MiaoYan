Markdown has no syntax for a collapsible section, so you write it as raw HTML: a `<details>` element with a `<summary>` label, and a blank line after the label so the Markdown inside is still parsed. It works on GitHub and in MiaoYan's preview. The trade-off is that the source is half HTML, and any renderer that strips raw HTML shows only the text.

## The pattern

````markdown
<details>
<summary>Build steps</summary>

1. Install the dependencies.
2. Run `make build`.

```bash
make test
```

</details>
````

`<details>` is the container, `<summary>` is the label that stays visible, and everything after the label is hidden until the reader clicks. Add the `open` attribute, as in `<details open>`, to start expanded. MDN notes that `open` is a Boolean attribute, so `open="false"` still counts as open: remove the attribute entirely to close it.

GitHub documents the same shape for collapsed sections, with a blank line after `</summary>` and a code block inside. If you also write for GitHub, copy that form and it will behave the same in both places.

## Why the blank lines matter

The blank lines are not style. They come from how CommonMark treats HTML. A line that starts with `<details` or `<summary` begins an HTML block, and the spec lists both names among the tags that start one. That kind of block ends at the first blank line, and everything inside it is passed through as raw HTML, not parsed as Markdown.

So this does not work:

```markdown
<details>
<summary>More</summary>
**Not bold.** Shown as literal asterisks.
</details>
```

The bold text sits on lines that belong to the HTML block, so the asterisks are printed as they are. Add a blank line after `</summary>` and the HTML block ends there; the next paragraph is parsed as Markdown again. Add another blank line before `</details>` so the closing tag starts its own block instead of being glued to your last paragraph.

The same logic applies to the label. The `<summary>` line is part of an HTML block, so Markdown in it is not converted. Write `<b>Build</b>` or `<code>make</code>` instead of `**Build**` or backticks.

## Nesting and what can go inside

You can nest one `<details>` in another. Keep a blank line between the outer content and the inner opening tag, and keep each level on its own lines:

````markdown
<details>
<summary>Platform notes</summary>

Shared advice goes here.

<details>
<summary>macOS</summary>

Details for macOS.

</details>

</details>
````

Lists, tables, images and fenced code all work inside once the blank lines are right. Headings work too, with a caveat covered below. MDN also describes a `name` attribute that groups several `<details>` so only one is open at a time, which gives you an accordion without scripts. MiaoYan passes the attribute through to the system WebKit unchanged, and MDN's compatibility data lists Safari support from 17.2. GitHub's guide does not mention it, so keep the accordion to notes you read in MiaoYan.

## How MiaoYan renders it

MiaoYan parses Markdown with cmark-gfm and renders HTML with the option that allows raw HTML (`CMARK_OPT_UNSAFE`) in V4.5.0, so a `<details>` block reaches the preview unchanged and the WebKit view draws it as a native disclosure widget. The preview's stylesheet gives `summary` a pointer cursor and a small left padding, and nothing more elaborate than that.

In the editor, type `/fold` and press `Tab` to insert the block. The template it inserts is the one above: `<details>`, a `<summary>` line with selected placeholder text, a blank line, a body line and the closing tag. The placeholder text is Chinese in the shipped template, so replace it before sharing. The [cheat sheet](/blog/markdown-cheat-sheet/) lists this shortcut next to the other slash commands.

Two things are easy to trip over. A heading inside a closed block is hidden, and the preview's table of contents is built with an option that skips hidden headings, so such a heading may be missing from the outline until you open the block. And when you paste a collapsible section copied from a web page, MiaoYan's HTML-to-Markdown conversion treats `details` and `summary` as plain containers, so you get the label and the contents as ordinary paragraphs, without the folding. Type the HTML yourself if you want to keep it.

## Export and printing

Export offers HTML, Image and PDF, and in V4.5.0 the image and PDF exports both start from the preview as it is at that moment: Image takes a snapshot of the preview page, and PDF copies the preview's current HTML into the print step. Nothing in that path opens `<details>` blocks. When you click a summary, the browser adds or removes the `open` attribute on that element, so a block you opened in the preview exports open, and a closed block exports as its label alone. If you export while only the editor is showing, MiaoYan turns on the preview first, and blocks start closed unless they carry `open`.

If the content must appear on paper, write `<details open>` for those blocks. They then start expanded in the preview and in the export. [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/) covers the rest of the PDF settings.

## Accessibility

A native `<details>` is a disclosure widget. According to MDN, the reader can toggle it by clicking, or by focusing it and pressing the space bar, and the contents of the element provide the accessible description for the `<summary>`. That is better than a hand-made toggle, but only if the label is useful. Write a summary that says what is inside, such as "Build steps for Linux", not "Click here" or "More". Keep the label short, since it is the only text visible when the section is closed.

Do not hide information a reader must see to complete a task. A collapsed section is for optional detail, such as logs, long output or platform-specific notes.

## What goes wrong

- Markdown shows as literal symbols inside the block. A blank line is missing after `</summary>` or before `</details>`.
- The section works in MiaoYan but is flat text elsewhere. The other renderer strips or escapes raw HTML. Test in the place where readers will see it.
- The PDF is missing content. The block was closed at export time; open it in the preview first, or use the `open` attribute.
- A fenced code block inside the section breaks. Put a blank line before the opening fence and keep the fence at the same indentation as the surrounding text.

## FAQ

### Does GitHub support collapsible sections?

Yes. GitHub's documentation describes the `<details>` and `<summary>` pattern, using an issue comment as the example, with `open` to start expanded.

### Can I put a heading in the summary?

Markdown heading syntax in the label will not convert, because the label line belongs to an HTML block. Use plain text or an HTML tag. Headings in the body are fine.

### Is there a Markdown-only way to fold text?

Not in CommonMark or GFM, which is why every renderer relies on the HTML element.
