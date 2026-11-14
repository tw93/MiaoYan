Spaces at the start of a Markdown paragraph are thrown away, and four of them after a blank line turn the text into a code block, so a normal indent never survives. To indent the first line of a paragraph, start the line with something that is not a space: `&nbsp;`, `&emsp;` or a full-width space (U+3000). To indent a whole block, use a blockquote or an HTML `<div>`. Inside a list item, indent to the item's content column instead of by a fixed number. Markdown itself has no indent syntax, so every option is a workaround with a cost.

## Why leading spaces disappear

Two layers drop the indent, and it helps to know which one you are dealing with.

The first is the Markdown parser. The CommonMark spec says leading spaces or tabs on a paragraph line are skipped, so `  aaa` followed by ` bbb` is one paragraph, `aaa` and `bbb`, with no indent on either line.

The second is the browser. HTML and CSS treat sequences of spaces, tabs and line breaks as one space, which the CSS `white-space: normal` value describes as collapsing. The CSS Text specification limits this to spaces (U+0020), tabs (U+0009) and line breaks, so the non-breaking space and the full-width space are not collapsed, which is the basis of the first-line tricks below.

The one case where leading spaces matter is the four-space rule. A chunk of lines each preceded by four or more spaces is an indented code block, so `    text` after a blank line is code, shown in monospace with the four spaces removed. See [Markdown code blocks](/blog/markdown-code-blocks/) for the fenced alternative.

## First-line indent with a space character

Start the line with entities or a character that the parser does not count as a space:

```markdown
&nbsp;&nbsp;&nbsp;&nbsp;An English paragraph indented by four non-breaking spaces.

&emsp;&emsp;Two em spaces, each one em wide.

　　中文段落的首行缩进，用两个全角空格。
```

The line starts with `&`, or with U+3000, neither of which the spec treats as a space, so the parser sees ordinary text. The spec defines a space as U+0020 only, which is why four `&nbsp;` in a row do not start a code block and four typed spaces do.

| Choice | Width | Notes |
| --- | --- | --- |
| `&nbsp;` | one space | Non-breaking, so you need several. |
| `&emsp;` | one em (U+2003) | Two of them match the usual indent of two characters. |
| U+3000 | one full-width character | Typed directly, common for Chinese paragraphs. |

For Chinese text the convention is two characters, which two U+3000 characters give, since a full-width space is as wide as a Chinese character in CJK fonts.

The cost is that the indent lives in the text. Every paragraph needs its own, a copy pasted into another app carries the extra characters, and a search for a phrase at the start of a paragraph has to ignore them. For a long essay, typing U+3000 each time gets old.

Only the first line of a paragraph indents this way. A newline inside a paragraph is a soft break, and spaces at the start of the next line are ignored too; [Markdown line breaks](/blog/markdown-line-breaks/) covers forcing a break.

## CSS text-indent

In HTML, the property that does this properly is `text-indent`, which sets the empty space before the first line of a block container. Where raw HTML passes through, you can put it on a paragraph:

```markdown
<p style="text-indent: 2em">This paragraph is indented by two em.</p>
```

Two things limit it. A raw HTML block is not parsed as Markdown, so `**bold**` inside that `<p>` stays as asterisks. The block also ends at the first blank line, so each paragraph needs its own tag.

MiaoYan 4.9.0 renders with cmark-gfm in unsafe mode, so raw HTML and its `style` attribute reach the preview untouched. MiaoYan has no setting for a custom preview stylesheet, and the preview page does not load a user stylesheet, so you cannot indent every paragraph with one line of CSS. Its own typography does not indent paragraphs, so in MiaoYan the choices are the characters above or a per-paragraph `style`. For a real stylesheet, export to HTML and edit the file; see [Markdown to HTML](/blog/markdown-to-html/).

## Indenting a whole block

A blockquote indents text and changes its meaning:

```markdown
> This block is set in from the left.
```

It renders as a quote, which in MiaoYan means muted text beside a thin bar, so use it for quotes and not for layout. Nested quotes and callouts are covered in [Markdown blockquotes and nested lists](/blog/markdown-blockquotes-and-nested-lists/).

For plain indentation without quote styling, wrap the content in a `<div>` with a left margin and leave blank lines around the Markdown inside it:

```markdown
<div style="margin-left: 2em">

Any **Markdown** works here, because of the blank lines.

</div>
```

An HTML block that starts with `<div>` runs to the next blank line, so the blank line right after the opening tag hands the content back to the Markdown parser. Without it, the inside stays raw text.

## Indenting inside list items

A list item owns the lines indented to its content column, the column where the text after the marker starts. In the spec's terms, a marker of width W followed by N spaces gives a content column of W + N, and later lines need that many spaces to stay in the item. For `- item` that is 2 spaces, for `1. item` it is 3.

```markdown
- Step one

  A second paragraph, indented two spaces.

1. Step one

   A second paragraph, indented three spaces.
```

Get it wrong and the line leaves the item. After a blank line, two spaces under `1. item` end the list, and the line becomes a separate paragraph, because the content column is 3. One space under `- one` does the same. Going the other way, if the spaces reach four past the content column, the line is code: six spaces under `- item`, which is 2 plus 4, gives a code block inside the item. The spec adds that when indentation could be read as a code block or as list content, the list item reading wins.

[Markdown blockquotes and nested lists](/blog/markdown-blockquotes-and-nested-lists/) has the marker-width table for nested lists.

## Tabs and spaces

CommonMark does not expand tabs to spaces. Where indentation defines structure, a tab behaves as if it were spaces with a tab stop of 4. So a tab can replace four spaces in an indented code block, and a tab starts code just as four spaces do. Inside the text of a line, tabs stay literal.

A tab continuation under `- foo` is a second paragraph of that item, the same as spaces, and two tabs make code inside the item. A tab continuation under `1. foo` also stays in the item, because it lands past the content column of 3. The risk is mixing the two: a file that has a tab on one line and two spaces on the next looks aligned in your editor and parses as two different depths.

In MiaoYan, the Tab key inserts two spaces at the start of the line, or three when the line above is a numbered item, and Shift+Tab removes up to three spaces or one tab. The Format menu has the same pair as Shift Right (`⌘]`) and Shift Left (`⌘[`). Those are list indents. Pressing Tab on the first line of an ordinary paragraph adds two spaces that the preview drops, so use the characters from the section above there.

## Indented code blocks and fences

Four-space code blocks have no info string, so no language can be named, they cannot interrupt a paragraph, and they appear whenever pasted text carries four leading spaces. A fenced block states its intent. Prefer fences, as described in [Markdown code blocks](/blog/markdown-code-blocks/).

## What goes wrong

**An accidental code block.** Text pasted from an email, a PDF or another editor often carries leading spaces. After a blank line, four of them make a monospace block with the spaces stripped. Remove the indent, or use an entity if you want it.

**List item content falling out.** A continuation paragraph indented too little ends the list, and the next item starts a new list. Check the content column of the marker above it. Numbers that reach `10.` widen the marker by one character and move the column with it.

**A raw HTML block that swallowed Markdown.** If `**bold**` shows its asterisks, the text is inside an HTML block with no blank line around it.

Always judge the result in the preview, not the editor.

## FAQ

### Is there a Markdown syntax for first-line indent?

No. The CommonMark spec defines no syntax for it, so the options are characters, raw HTML or a stylesheet.

### How many `&nbsp;` make a Chinese two-character indent?

Two U+3000 characters, which are as wide as a Chinese character in CJK fonts. A `&nbsp;` is only as wide as a space in the current font, so `&emsp;&emsp;` is the closer match.
