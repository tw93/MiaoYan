Write a footnote as a marker in the text, `[^1]`, and a definition on its own line, `[^1]: The note text.`. The renderer collects the definitions at the bottom of the page and numbers them in the order the markers appear. Footnotes are not part of CommonMark, so whether they work depends on the app: MiaoYan V4.5.0, GitHub and Pandoc render them, and some other Markdown processors print the brackets as plain text.

## The syntax

A footnote has two parts that share a label.

```markdown
Markdown has no official size syntax.[^size] Most apps accept HTML instead.[^html]

[^size]: The CommonMark spec defines images as links with a description.
[^html]: See the images post for `<img width>`.
```

The marker `[^size]` goes right after the word or punctuation it explains. The definition `[^size]: ...` can sit anywhere on its own line, and the usual habit is to put it directly under the paragraph or at the end of the note. GitHub's documentation states that the position of a definition does not change where the footnote is rendered, so you can write it right after the reference and it still appears at the bottom.

The label is only a key that connects the two parts. A number works, and so does a word such as `[^size]`. Pandoc's manual says the identifier may not contain spaces, tabs, newlines, or the characters `^`, `[` and `]`, and that in the output the footnotes are numbered sequentially whatever the label was. A named label is easier to keep straight once a note has more than five footnotes, because inserting a new one in the middle does not force you to renumber anything.

## Longer footnotes

A footnote can run over more than one line. GitHub's syntax page says to add two spaces at the end of a line to break a line inside a footnote. Pandoc goes further, and later paragraphs of a footnote are indented, and the manual compares this to multi-paragraph list items.

```markdown
[^longnote]: First paragraph of the note.

    Second paragraph, indented by four spaces.
```

That multi-paragraph form is documented for Pandoc. GitHub's page does not cover it. MiaoYan V4.5.0's cmark-gfm keeps an indented second paragraph inside the same note, and a paragraph that is not indented goes back to the body. For any other renderer, test one long footnote before writing a whole chapter that depends on it.

Pandoc also has inline notes, `^[text of the note]`, which need no label and no separate definition. It is a Pandoc extension, so it only helps if Pandoc is in your pipeline.

## Where footnotes render

| Where | Footnotes |
| --- | --- |
| CommonMark spec | Not defined. The spec only mentions footnotes as something some implementations added. |
| GitHub `.md` files, issues and pull requests | Supported, definitions render at the bottom. |
| GitHub wikis | Not supported, according to GitHub's syntax page. |
| Pandoc | Supported, with indented multi-paragraph notes and inline notes. |
| MiaoYan V4.5.0 | Supported in the preview and the exports that use the preview renderer, see below. |

The common mistake is moving a note between these. A note written for MiaoYan or Pandoc and pasted into a GitHub wiki page leaves `[^1]` visible in the text.

## What MiaoYan V4.5.0 does

MiaoYan renders Markdown with a Swift package of cmark-gfm. In `Business/Markdown.swift` at V4.5.0, the parser is created with the footnotes option and then four syntax extensions are attached by name: `table`, `footnotes`, `strikethrough` and `tasklist`. Footnotes are therefore on by default, with no setting to turn on. The parser output goes to HTML with raw HTML allowed, and the web view shows it. HTML export and PDF export build on the same render, so a footnote that works in the preview works there too. cmark-gfm turns each marker into a superscript number linking to the note, and collects the definitions into a numbered list in a `footnotes` section at the end, each with a link back to the text. Clicking a marker in the preview scrolls to its note.

The bundled syntax guide that ships with the app also has a Footnotes section with five definitions, which you can open to copy a working pattern. The preview bundle ships no footnote-specific styling, so expect the default look of the page.

One place is different. In slide mode, MiaoYan hands the note to reveal.js's Markdown plugin, which uses the `marked` library, not cmark-gfm. The plugin source at V4.5.0 has no footnote handling, so do not count on footnotes in a deck. If you need citations on slides, put the source in small text under the point, as described in [Markdown to slides](/blog/markdown-to-slides/).

## When a footnote does not render

- **The brackets show as text.** The processor has no footnote extension, or you are on a GitHub wiki. Check the table above.
- **A definition is printed as a paragraph.** The definition probably does not start at the beginning of the line, or the label differs from the marker by a character. Pandoc treats `[^Size]` and `[^size]` as different keys, while MiaoYan's cmark-gfm matches them regardless of case, so copy the label to stay safe in both.
- **The text after a long footnote is swallowed.** In Pandoc, a paragraph that is not indented ends the note. Put a blank line before the next paragraph and keep the indent consistent.
- **Numbers do not match the labels.** Pandoc numbers footnotes sequentially whatever the labels were, so `[^7]` can appear as 1. Treat the label as a key, not as the printed number.

For a PDF, MiaoYan prints its preview, so footnotes land in the list at the end of the document. If you need a different PDF layout, Pandoc is the alternative route, covered in [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/).

For the rest of the syntax that depends on the app, such as callouts and math, see the [Markdown cheat sheet](/blog/markdown-cheat-sheet/).

## FAQ

### Do GitHub README files support footnotes?

Yes. GitHub's syntax page documents `[^1]` markers with definitions, rendered at the bottom of the file. It states that footnotes are not supported in wikis.

### Can I put a footnote inside a table cell or a list item?

Pandoc's manual says footnote definitions may appear anywhere except inside other block elements such as lists, block quotes and tables. The marker itself is inline text. In MiaoYan V4.5.0 a marker inside a table cell renders as a normal footnote; elsewhere, check the result in your renderer before relying on it.

### Is there a limit on how many footnotes a note can have?

The GitHub and Pandoc documentation and the MiaoYan parser setup state no limit. Named labels make a long list easier to maintain.
