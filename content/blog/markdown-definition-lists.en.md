Standard Markdown has no definition list. Neither CommonMark nor GitHub Flavored Markdown defines one, so the common `Term` followed by `: Definition` syntax only works in processors that add it, such as Pandoc, kramdown, PHP Markdown Extra, Python-Markdown with the `def_list` extension (which MkDocs can load) and markdown-it with the `markdown-it-deflist` plugin. Where you cannot rely on that, write the HTML yourself with `<dl>`, `<dt>` and `<dd>`, or switch to a bold term followed by a paragraph, or a two-column table. MiaoYan's preview renders the HTML form and shows the colon syntax as plain text.

## What a definition list is

A definition list pairs terms with their definitions: a glossary, a list of command-line flags, a set of config keys. HTML has had an element for it for a long time. The list is a `<dl>`, each term is a `<dt>`, and each definition is a `<dd>`. A term can have several definitions, and several terms can share one.

The reason it feels like a Markdown feature is that several well-known processors read a plain-text shorthand for it. That shorthand is an extension, not part of the language, which is why the same note renders as a tidy glossary in one tool and as a jumble of colons in another. The [CommonMark vs GFM](/blog/commonmark-vs-gfm/) post covers the wider question of what counts as standard.

## CommonMark and GFM have no definition list

The CommonMark spec has no definition list construct, and neither does the GFM spec, which adds tables, task lists, strikethrough, extended autolinks and a tag filter on top of CommonMark. The `<dl>` element is not on the tag filter's list either, so GFM does not block it.

Given this input:

```markdown
Apple
: A fruit.
```

a CommonMark or GFM parser reads one paragraph, with the colon line as its second line. Pandoc 3.13, run as `pandoc -f gfm -t html`, gives `<p>Apple : A fruit.</p>`, the two lines joined. The text is not lost, it is just not structured.

## The colon syntax

The syntax most people mean comes from PHP Markdown Extra, and Pandoc and kramdown follow it with their own details. A term goes on a line by itself, and each definition starts on the next line with a colon:

```markdown
Apple
:   Pomaceous fruit of plants of the genus Malus.
:   An American computer company.

Pear
:   A fruit that is not an apple.
```

The rules, from the processors' own documentation:

- **Multiple definitions.** Each extra definition gets its own colon line, as in the Apple example. In PHP Markdown Extra, several terms can also share one definition: write the terms on consecutive lines, then the colon line.
- **Blank lines.** Terms need a blank line between them and the previous definition in Markdown Extra. A blank line between a term and its definition changes the output: Markdown Extra wraps such a definition in `<p>` tags, and Pandoc says the definition is then treated as a paragraph. In Pandoc, `Pear`, a blank line, then `: Also fruit.` produces `<dd><p>Also fruit.</p></dd>`, while the version with no blank line produces a plain `<dd>`.
- **Marker position.** The colon sits at the left margin or is indented. Markdown Extra allows up to three spaces and requires a space or tab after it. Pandoc accepts a colon or a tilde, indented one or two spaces. kramdown allows up to three spaces and at least one space or tab.
- **Longer definitions.** Indent continuation blocks so they line up with the text after the marker. Markdown Extra and Pandoc both allow several paragraphs, code blocks and lists inside a definition. Both accept a paragraph that wraps onto an unindented line, which Pandoc calls lazy; kramdown accepts it too but advises against relying on it.
- **One-line terms.** Pandoc says each term must fit on one line. In kramdown, each line of the preceding paragraph is a separate term.

## Where the colon syntax renders

It renders where the processor has the feature turned on:

- **Pandoc** has it in its own Markdown as the `definition_lists` extension, on by default. With `-f gfm` or `-f commonmark` it is off, as the output above shows.
- **kramdown** documents definition lists in its syntax reference.
- **Python-Markdown** ships a `def_list` extension, enabled with `markdown.markdown(text, extensions=['def_list'])`. MkDocs uses Python-Markdown and lists only `meta`, `toc`, `tables` and `fenced_code` as defaults, so a MkDocs site adds `def_list` under `markdown_extensions` in `mkdocs.yml`.
- **markdown-it** needs the separate `markdown-it-deflist` plugin, loaded with `.use(require('markdown-it-deflist'))`. Its README describes the syntax as largely compatible with Pandoc definition lists in `commonmark_x`.

GitHub's basic writing and formatting syntax page does not mention definition lists, so do not expect the colon syntax to work in a README. Test with a throwaway note before you build on it.

## The HTML fallback

HTML is the portable route. A Markdown processor that allows raw HTML passes `<dl>` through:

```markdown
<dl>
  <dt>Apple</dt>
  <dd>A fruit.</dd>
  <dt>Pear</dt>
  <dd>Another fruit.</dd>
</dl>
```

The catch is how CommonMark treats Markdown inside HTML. A line that starts with a block-level tag such as `<dl>`, `<dt>` or `<dd>` opens an HTML block that runs until the next blank line, and the spec says the contents of a block like that are passed through as-is. So this does not format:

```markdown
<dl>
<dt>Pear</dt>
<dd>**not parsed**</dd>
</dl>
```

The asterisks stay literal. The spec's own `<div>` examples show the way out: put the inner content on its own lines, separated from the tags by blank lines, and it is parsed as Markdown again.

```markdown
<dl>
<dt>Apple</dt>
<dd>

*Fruit* with `code`

- a list

</dd>
</dl>
```

With Pandoc's `-f gfm` this gives emphasis, a code span and a real list inside the `<dd>`, while a `<dd>**not parsed**</dd>` on one line stays literal. Do not indent the inner content by four spaces, or it becomes a code block.

It is more typing than the colon syntax, so use it when the structure matters, such as a glossary that other tools or a stylesheet will read.

## What MiaoYan does

MiaoYan's preview parses Markdown with cmark-gfm, created with the footnotes option and four extensions attached by name: `table`, `footnotes`, `strikethrough` and `tasklist`. No definition list extension is among them, and cmark-gfm's own core does not include one, so a term line followed by a `: A fruit.` line stays a single paragraph. With the default `Every Newline` line-break setting the colon line still sits on its own line, because each newline becomes a `<br>`; with `GitHub Style` the two lines join with a space. The renderer is called with the option that lets raw HTML through, so `<dl>` blocks render as written, and the blank-line trick above gives emphasis, code and lists inside a `<dd>`, while `<dd>**not parsed**</dd>` on one line stays literal.

In practice, in MiaoYan write the HTML form if you want a real glossary, and expect colon syntax from a note written for Pandoc to show as text. If you export to HTML with MiaoYan, the `<dl>` travels with it, as covered in [Markdown to HTML](/blog/markdown-to-html/).

## Alternatives that work everywhere

If the note has to read well in several places, skip the extension and use plain Markdown.

**Bold term, then a paragraph.** The simplest and the most portable:

```markdown
**Apple**
A fruit.

**Pear**
Another fruit.
```

Make the line break explicit with a backslash or two trailing spaces if you want the term on its own line, as [Markdown line breaks](/blog/markdown-line-breaks/) explains. Bold itself is covered in [bold, italic and strikethrough](/blog/markdown-bold-italic-strikethrough/).

**A two-column table.** Good for short, uniform entries such as flags or keys:

```markdown
| Flag | Meaning     |
| ---- | ----------- |
| `-s` | Standalone  |
| `-o` | Output file |
```

Tables allow one line per cell and no lists, so they suit short definitions. See [Markdown tables](/blog/markdown-tables/) for the rules. For long definitions with paragraphs and lists, a heading per term is often cleaner than any list.

## FAQ

### Does GitHub support Markdown definition lists?

The GFM spec defines no such syntax and GitHub's formatting documentation does not mention it, so use an alternative or HTML and check the result where it will be read.

### Is the colon syntax Pandoc-only?

No. PHP Markdown Extra originated it, and kramdown, Python-Markdown and markdown-it-deflist read it with their own small differences.

### How do I make a definition list in MkDocs?

Add `def_list` to `markdown_extensions` in `mkdocs.yml`, then write the Term and `: Definition` form.

### Why is my bold text inside a dd not formatting?

A line starting with `<dd>` is part of an HTML block, which CommonMark passes through unparsed. Put the content on its own lines with blank lines around it.
