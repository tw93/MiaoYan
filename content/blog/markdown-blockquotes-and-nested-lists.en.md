A blockquote is a line that starts with `>`, and a quote nests by adding another `>`. A nested list nests when the child's marker sits at or past the column where the parent's text begins: two spaces under `- `, three under `1. `, four under `10. `. Four spaces in the wrong place turn a line into a code block, and Markdown has no syntax for indenting a paragraph at all. MiaoYan V4.5.0 turns `> [!NOTE]` quotes into callouts like GitHub does, and its Tab key indents by two spaces, or three under a numbered line, which is enough until a number reaches 10.

## Blockquote syntax

```markdown
> A quoted line.
> Another line in the same quote.
>
> A second paragraph, still inside the quote.
```

The space after `>` is optional, and up to three spaces may come before it. With four leading spaces the line is indented code, so `    > text` prints the `>` literally. A blank line without `>` ends the quote, and a later `> ...` starts a separate one. For one quote with two paragraphs, keep a bare `>` on the blank line.

Headings, lists, fenced code and more quotes all work inside a quote, as long as every line, fence lines included, starts with `>`:

````markdown
> ## A heading in a quote
>
> 1. First step
> 2. Second step
>
> ```bash
> make build
> ```
````

## Lazy continuation

CommonMark lets you drop the `>` on later lines of a paragraph. `> a` followed by a bare `lazy` line is one quote holding the paragraph "a lazy". The rule only covers paragraph text: a blank line ends it, and in `> - foo` followed by a bare `- bar`, the quote ends after the first line.

The preview also depends on the Line Break setting. cmark-gfm joins lazy lines with a space, but MiaoYan's default renders every newline as a `<br>`, so the same two lines stay apart in MiaoYan and run together in a GitHub `.md` file. [Markdown line breaks](/blog/markdown-line-breaks/) covers the setting. For anything you publish, put the `>` on every line.

## Nested quotes and callouts

```markdown
> The outer quote.
>
> > The inner quote.
>
> Back in the outer one.
```

Each extra `>` adds a level, and `> >` and `>>` mean the same. The bare `>` before "Back in the outer one" matters, because without it that text would continue the inner paragraph.

A callout is a quote whose first line is a marker. MiaoYan V4.5.0 recognizes five, in any letter case:

```markdown
> [!NOTE]
> Useful context.

> [!WARNING]
> Check this before you delete anything.
```

The others are `TIP`, `IMPORTANT` and `CAUTION`. The preview draws a coloured box with an icon and a title row reading Note, Tip, Important, Warning or Caution. The marker must be alone on its line: `> [!NOTE]: text` and unknown words such as `[!DANGER]` stay ordinary quotes, a marker inside a fenced code block is left alone, and a plain quote nested inside a callout stays a quote. GitHub documents the same five types and adds two cautions that matter for notes headed there: limit them to one or two per article, and alerts cannot be nested inside other elements. Apps without callout support show a normal quote with `[!NOTE]` in it; the [cheat sheet](/blog/markdown-cheat-sheet/) files callouts under extensions. MiaoYan converts callouts after rendering, by finding any quote whose first paragraph starts with a marker, so it does not apply that nesting rule: a `> [!WARNING]` quote indented under a list item becomes a warning box in MiaoYan, while GitHub renders the same lines as a plain quote beginning with `[!WARNING]`. Keep callouts at the top level of a note that will also be read on GitHub.

## How nested list indentation works

A list item owns the following lines that are indented to its content column, the column where the text after the marker starts. A child list is nested when its marker begins at or after that column, so the indent you need depends on the parent's marker:

| Parent marker | Smallest nested indent |
| --- | --- |
| `- ` | 2 spaces |
| `1. ` | 3 spaces |
| `10. ` | 4 spaces |
| `100. ` | 5 spaces |

GitHub's guide gives the same method: count the characters before the item text and type that many spaces. These cases were run through cmark-gfm 0.29.0.gfm.3, the version bundled with MiaoYan V4.5.0, with the same extensions and options. `1. one` followed by `  - sub` with two spaces gave two separate lists, not a nested one. One space under `- a` made a sibling. Three spaces under `10. one` made a separate bullet list, and four nested it. So for bullets any indent from 2 to 5 spaces works (six or more is read as text or code), and the "2 or 4 spaces" argument only matters under numbers, where you need the marker width.

Markers also decide where lists start and end. Switching between `-`, `*` and `+`, or between `.` and `)`, starts a new list. The first number sets the start, so `3.` then `4.` renders as an ordered list starting at 3, `0.` is allowed, and later numbers are ignored, so `1.` on every line still counts up. A marker is one to nine digits, and only a list starting with `1` can interrupt a paragraph, which is why `2024. was a year` inside a paragraph stays text; [escape characters](/blog/markdown-escape-characters/) has the fix for the start of one.

To continue an item with a paragraph or code, indent it to the same column after a blank line:

````markdown
- Step one

  Second paragraph of step one.

  ```bash
  make build
  ```
- Step two
````

A fence written at column 0 would close the list instead.

## Why four spaces makes a code block

An indented code block is four or more spaces at the start of a line after a blank line. At the top level, `    text` after a blank line is code. Inside a list the four count from the content column, so code under `- ` needs six. After a line of ordinary text, indented lines do not start code, they continue the paragraph. Indent to the content column, not by four, and prefer fences for code, as in [Markdown code blocks](/blog/markdown-code-blocks/).

## Indenting a paragraph

Leading spaces are dropped in a paragraph, and four of them make code, so the trick is to start the line with a character that is not a space:

```markdown
&nbsp;&nbsp;&nbsp;&nbsp;An indented paragraph.

　　中文段落的首行缩进，用两个全角空格。
```

The `&nbsp;` entities render as real spaces, and the full-width space (U+3000) is an ordinary character to the parser, so it never starts a code block. The cost is that the indent lives in the text itself, so every paragraph needs its own.

## Indenting in MiaoYan's editor

In V4.5.0, `Tab` indents the current line, or every selected line, by two spaces, and `Shift+Tab` removes up to three leading spaces or one tab. The Format menu has the same pair as Shift Right (`⌘]`) and Shift Left (`⌘[`). If the line above is a numbered item, `Tab` indents by three spaces, and it rewrites the number on a numbered line to `1`, so `2. two` becomes `   1. two`, the start of a nested numbered list.

The width follows the line above, not the parent's marker, so under `10. item` you get three spaces, which the table above showed is a sibling list. Add a space and check the preview. `Return` at the end of a list or quote line starts the next with the same marker, with numbers counted up by one, and `Return` on an empty marker clears it. Only the first marker is copied, so in a `> >` quote you type the second `>` yourself.

## Checking the result

Look at the preview, not the editor. A child that sits at its parent's level was indented too little for that marker. A monospace line was indented too far after a blank line. A literal `>` had four or more spaces in front. A list that restarts at 1 changed its marker character.

## FAQ

### Can I put a blockquote inside a list item?

Yes. Indent the `>` lines to the item's content column, two spaces under `- `, and repeat the same indent on every line.

### Why does my quote lose its second line?

That line was not a paragraph continuation, for example it started a list or came after a blank line. Put `>` at the start of every line.

### Do callouts work in every Markdown app?

No. GitHub and MiaoYan V4.5.0 render them, and others show a plain quote that begins with `[!NOTE]`.
