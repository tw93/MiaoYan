Wrap code in a fence of three backticks (or three tildes), put the language name after the opening fence, and close with a fence of the same character that is at least as long. Use a longer outer fence when the code itself contains a fence. The language word is the only thing that tells a highlighter what to color, so the main trade-off is between a block that is portable everywhere and one that depends on what your preview happens to support.

## Fenced and indented blocks

A fenced block starts with a line of three or more backticks or tildes and ends with a matching line:

````markdown
```python
def greet(name):
    return f"hello {name}"
```
````

The text after the opening fence is the info string. Its first word is conventionally the language, and the CommonMark spec renders it as a `language-python` class on the `<code>` element, which is what highlighters key on. With backtick fences the info string may not itself contain a backtick. With tildes it can, which is one of the few reasons to prefer `~~~`.

An indented block is any run of lines indented by four spaces after a blank line:

```markdown
    make build
    make test
```

It works in every parser, but it has no info string, so no language can be named, and it is easy to trigger by accident, for example by indenting a continuation paragraph under a list item. Fences are the safer habit. The two styles also differ in how they end: an indented block stops at the first non-blank line that is not indented, while an unclosed fence runs to the end of the document, so a missing closing fence swallows everything below it.

Backtick and tilde fences behave the same, with one rule. The closing fence must use the same character as the opening one and be at least as long. A line of `~~~` does not close a backtick fence, and `` ``` `` does not close a tilde fence. Both CommonMark and GFM define both. Backticks are far more common, so they are the better default for notes other people will read in other tools.

## Putting a fence inside a fence

To show Markdown that contains a code block, make the outer fence longer than any fence inside it. The examples in this post use four backticks outside and three inside:

`````markdown
````markdown
```js
console.log("inner");
```
````
`````

The inner fence is shorter than the outer one, so it cannot close it. If you need to show the four-backtick version too, go to five on the outside. A tilde fence is another way out: `~~~` outside and backticks inside never conflict, because the closing character has to match.

## Inline code with backticks inside

A code span is a run of backticks around the text. If the text contains a backtick, use a longer run to open and close it, and pad with a space on each side so the delimiters do not touch the content:

```markdown
Use `` `git log` `` to show history.
```

Per the CommonMark spec, when the content both begins and ends with a space and is not all spaces, one space is removed from each end. That is why the padding does not show up in the rendered output. Backslash escapes do not work inside a code span, so a backslash followed by an asterisk shows both exactly as typed.

## Diff blocks

Name the language `diff` and lines that start with `+` and `-` are colored as additions and deletions:

````markdown
```diff
- timeout: 30
+ timeout: 60
```
````

This is highlighting of a text convention, not a Markdown feature, so it works wherever the highlighter includes a diff definition. `patch` is accepted as an alias in MiaoYan's bundled highlighter.

## How MiaoYan renders code blocks

MiaoYan parses Markdown with cmark-gfm, which turns a fenced block into `<pre><code class="language-...">`. The preview then loads highlight.js 11.5.1, the version recorded in the bundle's vendor manifest at V4.5.0, and colors every `pre code` element. Three behaviors follow from how that library works.

First, the bundle is a trimmed build, not the full highlight.js catalog. It registers 34 language definitions: Bash, C, C++, C#, CSS, Diff, Go, HTML and XML, INI and TOML, Java, JavaScript, JSON, Kotlin, Less, Lua, Makefile, Markdown, Objective-C, Perl, PHP, PHP template, plain text, Python, Python REPL, R, Ruby, Rust, SCSS, Shell Session, SQL, Swift, TypeScript, Visual Basic .NET and YAML. Common short names such as `js`, `ts`, `py`, `sh`, `yml`, `md`, `rs` and `rb` are aliases. There is no Dockerfile or GraphQL definition, for example.

Second, a language word the bundle does not know turns highlighting off for that block, and the code shows in plain monospace. A block with no language word is the opposite case: highlight.js guesses from the content, which saves typing but is unreliable when the code is very short. If colors look wrong, add the word.

Third, long lines wrap instead of scrolling. The stylesheet sets `white-space: pre-wrap` on code blocks, so a long shell command stays readable without a horizontal scroll bar, at the cost of wrapped lines being harder to tell from separate lines.

The editor pane colors code separately, using its own highlighter, and only for fences written with backticks. Tilde fences and nested four-backtick fences render correctly in the preview, but the editor's coloring may not match them. It also skips coloring for a block longer than 3000 characters, and for the whole note once it has more than 20 fenced blocks. The preview is the authority on how the note will export.

## Mermaid, PlantUML, Markmap and math

Some language words do more than color text. `mermaid`, `plantuml` and `markmap` are picked up by MiaoYan's diagram script and replaced with a drawing. Mermaid and Markmap run from bundled JavaScript. PlantUML builds a link to the public plantuml.com service, so it needs a network and the diagram text leaves your Mac. If Mermaid fails to parse, the preview keeps the source in the block instead of showing an error page. The details are in [Mermaid diagrams in Markdown](/blog/mermaid-diagrams-in-markdown/).

Math is different: it is not a fence. Dollar-delimited math is handled outside code, and MiaoYan's math pass skips code spans and fenced blocks, so a literal `$` inside a block is safe. See [LaTeX math in Markdown](/blog/latex-math-in-markdown/) for the syntax.

## Copying and exporting

The V4.5.0 preview has no copy button on code blocks, so you select the text and copy it as usual. In the other direction, when you paste structured HTML copied from a web page, MiaoYan converts it to Markdown, and a code block becomes a fence carrying the language class it found, with a longer fence if the code itself contains three backticks.

The Export submenu offers HTML, Image and PDF. PDF export is covered in [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/). An exported HTML file points at MiaoYan's CDN for the highlighter and diagram scripts, so colors and diagrams in that file need a network connection when it is opened.

## What goes wrong

- A missing closing fence turns the rest of the note into code. Look for text that suddenly appears in monospace.
- A fence inside a list item has to line up with the item text, or it ends the list.
- A language word the highlighter does not know gives no colors. Try the short alias, or check the list above.
- Colors differ between apps because each ships a different highlighter and theme. The Markdown is portable; the colors are not.

For the rest of the syntax, [the cheat sheet](/blog/markdown-cheat-sheet/) has short sections on each element.

## FAQ

### Do I need a language word?

No. The block still renders as code without one. Add it when you want predictable colors, since MiaoYan otherwise guesses from the content.

### Can I use tildes instead of backticks?

Yes, as long as the closing fence uses tildes too. Tildes are useful when the code contains backtick fences.

### Why does my code show without colors?

Either there is no language word and the guess failed, or the word is not one the highlighter knows. MiaoYan's bundle registers 34 languages, so a less common one such as Dockerfile shows as plain monospace.
