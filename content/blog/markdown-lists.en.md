A Markdown numbered list is lines that start with a number, a period and a space, such as `1. First`, and a bullet list is lines that start with `-`, `*` or `+` and a space. Only the first number of a numbered list matters, the renderer counts up from it, so a list written as `1.` on every line prints as 1, 2, 3. Changing the marker character, or switching between `.` and `)`, starts a new list. A blank line between items makes the list loose, which wraps each item in a paragraph and changes the spacing.

## Bullet lists

```markdown
- Buy milk
- Buy bread
- Buy eggs
```

The CommonMark spec defines a bullet list marker as `-`, `+` or `*`, and all three render the same list. At least one space or tab has to follow the marker, so `-one` is plain text, not an item. A marker can be indented by up to three spaces and still start an item; at four spaces the line is indented code, or a continuation line when it follows a paragraph or item.

The marker is part of the list's identity. The spec says two markers are the same type only if they use the same character, so this is two lists, not one:

```markdown
- foo
- bar
+ baz
```

The output is a `<ul>` with foo and bar, followed by a second `<ul>` with baz. Pick one marker per list and keep it. The same rule applies to numbered lists, where the `.` delimiter and the `)` delimiter count as different types.

## Numbered lists

```markdown
1. Preheat the oven
2. Mix the dough
3. Bake for 20 minutes
```

An ordered list marker is one to nine digits followed by `.` or `)`. Both delimiters are valid CommonMark, though GitHub's documentation uses the period in its examples. The limit of nine digits exists because longer numbers cause integer overflows in some browsers, so `1234567890. text` is a plain paragraph.

### Only the first number counts

The spec says the start number of an ordered list is set by its first item and the numbers of later items are disregarded. These three lists produce the same HTML:

```markdown
1. one
2. two
3. three
```

```markdown
1. one
1. two
1. three
```

```markdown
1. one
7. two
2. three
```

All three render as 1, 2, 3. If you begin with `5.`, the HTML gets `<ol start="5">` and the list reads 5, 6, 7. Zero is allowed, so `0.` starts a list at zero, and leading zeros are fine, `003.` starts at 3. A negative number is not a marker.

This is why many people write `1.` on every line. Moving or inserting an item never forces a renumber, and a diff shows one changed line instead of the whole list. The cost is that the source reads worse, and any viewer that does not render Markdown, such as a plain-text email, shows a column of ones. Sequential numbers are easier to read in the raw file; all-ones is easier to maintain.

### A list that interrupts a paragraph must start at 1

CommonMark lets a list start without a blank line before it, so `Foo` followed directly by `- bar` is a paragraph and then a list. For ordered lists the spec adds a guard: only a list that starts with 1 can interrupt a paragraph. The reason is hard-wrapped text. In

```markdown
The number of windows in my house is
14.  The number of doors is 6.
```

the line starting with `14.` stays part of the paragraph. The spec admits a leftover case: if the wrapped line happens to begin with `1.`, it still becomes a list. When a numbered list begins at another number right after a paragraph and renders as text, put a blank line before it. After a blank line the restriction does not apply.

## Tight and loose lists

A list is tight when its items follow each other with no blank lines. It is loose if any two items are separated by a blank line, or if an item directly contains two blocks with a blank line between them. The HTML difference is that a loose list wraps item text in `<p>` tags and a tight list does not.

```markdown
- a
- b

- c
```

This is one loose list, not a tight list with a gap. One blank line anywhere between items makes every item a paragraph, because looseness belongs to the whole list. The usual fix for unwanted spacing is to delete the stray blank line, or to add blank lines between all items.

Blank lines inside a fenced code block or inside a blockquote in an item do not make a list loose, per the spec's examples.

## Paragraphs and code inside an item

An item continues as long as the following lines are indented to the column where the item's text starts. That column is the marker's width plus the spaces after it:

```markdown
- First item

  A second paragraph of the same item.

1. Step one

   Explanation of step one.

   ```bash
   make build
   ```

2. Step two
```

Under `- ` the content column is 2, under `1. ` it is 3, and under `10. ` it is 4. A line indented less than that, as in the spec's `- one`, a blank line, then a line with a single space and `two`, leaves the list and becomes a paragraph of its own. Indenting more than needed is fine for a paragraph, but four extra spaces turn it into code. Deeper indentation of whole items is nesting, which has its own rules in [blockquotes and nested lists](/blog/markdown-blockquotes-and-nested-lists/).

A fenced block follows the same indentation rule, with the fence and its contents all indented to the content column. For more on fences themselves, see [Markdown code blocks](/blog/markdown-code-blocks/). To put an indented code block inside an item, indent it four spaces beyond the content column, six under `- `.

## Ending a list before a code block

The reverse problem is a list followed by code that is not part of it. If you write an indented code block right after a list and a blank line, the spec reads the indented lines as another paragraph of the last item. The spec's answer is to insert an HTML comment between them:

```markdown
- foo
- bar

<!-- -->

    code
```

The comment renders nothing and ends the list, so the indented block is real code. The same trick separates two lists of the same type that you want kept apart. A fenced block that starts at column 0 also ends the list, since it is not indented enough to belong to the last item. When in doubt, use a fence.

## Lists in MiaoYan

MiaoYan's preview is built with cmark-gfm, so the rules above are what you see. The editor adds list continuation on Return, from the V4.9.0 source:

- With the caret at the end of a line that starts with `- `, `* ` or `+ `, Return starts the next line with the same marker.
- On a numbered line like `1. ` or `10. `, Return starts the next line with the number plus one, so `1. a` becomes `2. ` and `10. item` becomes `11. `. This follows plain counting and does not copy a column of all ones. It recognizes the period form only, so a `1)` line is not continued.
- Return on an item that has only the marker removes the marker and leaves an empty line, which ends the list.
- Return with the caret in the middle of the line, or Shift-Return, gives a plain newline with no marker.

The same continuation also copies `- [ ]` for task lists, with the box reset to open; that is covered in [Markdown task lists](/blog/markdown-task-lists/).

## FAQ

### Do I have to number a Markdown list correctly?

No. Only the first number is used, the rest is counted by the renderer. Writing `1.` on every line is valid and common.

### Can a numbered list start at a number other than 1?

Yes. Start with `5.` and the list reads 5, 6, 7. If it comes right after a paragraph with no blank line, it will not render as a list, so leave a blank line before it.

### Why did my list split into two?

The marker changed. `-` and `+` are different list types, and so are `1.` and `1)`. Use one marker per list.

### Why is there extra space between my list items?

A blank line somewhere between items made the list loose. Remove the blank lines, or add them everywhere.

### How do I put a code block inside a list item?

Indent the fence to the item's content column, two spaces under `- ` and three under `1. `.
