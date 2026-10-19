Markdown is a way of writing formatted text in a plain text file, using a few ordinary characters as marks: `#` for a heading, `*` around a word for emphasis, `-` for a list item. A program reads those marks and turns them into HTML, but the file itself stays readable without any program, which is the main reason people use it. It is good for notes, documentation and articles, and poor for anything that depends on precise page layout. You can learn the ten marks that cover most writing in about ten minutes.

## Where it came from

John Gruber released Markdown in 2004, and his [project page](https://daringfireball.net/projects/markdown/) describes it as two things: a plain text formatting syntax, and a Perl tool that converts that syntax to HTML. The marks were chosen from conventions people already used in email and Usenet posts, so the source looks like what you would have typed in a plain message anyway.

The original description was loose in places, and implementations disagreed. Around 2014 the [CommonMark project](https://commonmark.org/) wrote an unambiguous specification, and GitHub later published GitHub Flavored Markdown (GFM), a superset of it with tables and task lists. The [CommonMark spec](https://spec.commonmark.org/0.31.2/) notes that Reddit, StackOverflow and GitHub had millions of people using Markdown, which is a fair summary of where you will meet it. Because of that history, "Markdown" today means a core that is well defined plus extensions that vary by app, as [CommonMark vs GFM](/blog/commonmark-vs-gfm/) explains.

## The ten marks that cover most writing

````markdown
# Heading
## Subheading

A paragraph with *italic* and **bold** text and `inline code`.

- A bullet item
- Another item

1. A numbered item
2. The next one

[Link text](https://example.com)
![Alt text](photo.png)

> A quoted line.

```python
print("a code block")
```
````

Reading it top to bottom: `#` characters start a heading, and the number of them sets the level, up to six. A blank line separates paragraphs. Single asterisks or underscores make italic, double make bold, and backticks mark code. A hyphen at the start of a line makes a bullet; a number and a period make a numbered list. A link is square brackets for the text followed by parentheses for the address, and an image is the same with a leading `!`. A line starting with `>` is a quote. Three backticks open and close a code block, and a word after the opening three names the language so the code can be colored.

Two more you will use soon are tables, written with `|` between columns and a row of hyphens under the header, and task lists, written `- [ ]` and `- [x]`. Both come from GFM, not from the original Markdown. The [Markdown cheat sheet](/blog/markdown-cheat-sheet/) lists them all with the details that trip people up.

## How a renderer turns it into HTML

A Markdown file does nothing by itself. A program called a parser reads it, finds the marks and builds a structure of headings, paragraphs and lists, and a renderer writes that structure out, usually as HTML. The line `# Heading` becomes `<h1>Heading</h1>`, and `**bold**` becomes `<strong>bold</strong>`. A browser or web view then draws the HTML with a stylesheet, which decides the fonts, spacing and colors.

[[figure:what-is-markdown|A Markdown file is read by a parser, a renderer writes the resulting structure out as HTML, and a browser draws that HTML with a stylesheet to produce the rendered page.|The file never changes; the parser decides what your marks mean and the stylesheet decides how the result looks.]]

This split explains two things beginners notice. First, the same file can look different in different apps, because the parser, the extensions it supports and the stylesheet are all the app's choice. Second, formatting problems are almost always one of two kinds: the parser did not understand your mark, which you can see as literal asterisks or hash signs on the page, or the stylesheet made it look the way it does, which you can change without touching the file.

## Why the file stays readable

Compare `**Important:** back up first` with the same sentence in a word processor's file format. The Markdown version is plain text you can open in any editor, search with any tool, keep in a git repository and read in ten years even if the app is gone. A word processor document is a packaged format that needs the right program. Because a Markdown file is only text, it is also small, easy to diff, and easy to copy into an email or a chat when you do not care about rendering.

That is also the case for keeping notes as ordinary files in a folder you own, covered in [Local-first Markdown notes](/blog/local-first-markdown-notes/).

## Where you will use it

GitHub renders Markdown in READMEs, issues and comments, and for many people that is the first place they meet it. Documentation sites, notes apps and other tools also read it. Check each tool's own documentation for which extensions it supports, because the core is shared and the extras are not.

## What it is bad at

Markdown describes structure, not appearance. It has no way to say that a figure should sit 2 cm from the margin, to make a column layout, to set an exact font size, or to place text on a specific page. Tables are limited to simple rows and columns, and merged cells need HTML. If you need precise page layout, use a layout tool and export, or write Markdown and convert it through a program that handles the styling. For a printable file from a note, see [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/).

Markdown can also embed raw HTML in many apps, which is a way out for the odd case but makes the file less portable.

## Getting started in MiaoYan

MiaoYan is a Mac Markdown editor that stores each note as a plain `.md` file. Three steps get you a first rendered note.

1. Choose File > New, or press `⌘N`, to create a note, and type a title and a few lines using the marks above.
2. Choose View > Toggle Preview, or press `⌘3`, to switch the editor to the rendered view. Press it again to go back to the source. View > Toggle Split View (`⌘\`) shows source and preview side by side.
3. Look for leftover marks such as stray `**` or `#` on the preview page. They show where the parser did not understand the syntax.

MiaoYan 4.5.0 renders CommonMark plus tables, task lists, strikethrough and footnotes through the cmark-gfm parser, and adds math, callouts and diagrams in the preview. When the library is empty on first launch it also creates sample notes, including a MiaoYan Markdown Syntax Guide, that you can read as examples. To pick an editor, compare options in [Choosing a Markdown editor for Mac](/blog/markdown-editor-for-mac/).

## FAQ

### Is Markdown a programming language?

No. It is a markup syntax for text. It has no variables or logic, only marks that a parser converts to HTML.

### Do I need to learn HTML first?

No. You only meet HTML if you want something Markdown cannot express, and most notes never need it.

### Which file extension should I use?

`.md` is the common one, and it is what MiaoYan creates for new notes.
