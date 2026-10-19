Put a backslash in front of any ASCII punctuation character and Markdown treats it as plain text, so `\*not italic\*` shows asterisks and `\# not a heading` shows a hash. Inside code spans and code blocks you do not need it, because nothing is parsed there. The one place MiaoYan behaves differently from plain CommonMark is the dollar sign, which its math renderer also reads, so prices need extra care.

## What a backslash can escape

CommonMark allows a backslash before any of these 32 characters, and nothing else:

```text
! " # $ % & ' ( ) * + , - . / : ; < = > ? @ [ \ ] ^ _ ` { | } ~
```

A backslash before a letter, digit, space or non-ASCII character is just a backslash, so `\A` and `\3` print as typed. To print a backslash itself, double it: `\\`. A backslash at the very end of a line is not an escape at all, it is a [hard line break](/blog/markdown-line-breaks/). Escaped characters lose their Markdown meaning, which includes `\<` (not a tag), `\[` (not a link), ``\` `` (not code) and `\&` (not an entity).

## When you actually need one

Most punctuation is harmless in the middle of a sentence. The cases that bite are these.

**Asterisks.** `*` opens emphasis even inside a word, so `5*6*78` renders with an italic 6, per the spec. Write `5\*6\*78` for literal asterisks.

**Underscores.** CommonMark does not allow `_` emphasis inside words, so `snake_case_name` stays as typed. The spec itself says it is best to put such names in code spans. You need `\_` when two underscores sit at word edges on the same line, for example `_draft` and `final_` around other text, which can pair up as emphasis.

**A number followed by a dot at the start of a line.** `2024. was a good year` starts an ordered list, because a list marker is one to nine digits followed by `.` or `)`. Only a list starting with `1` can interrupt a paragraph, so this mostly bites at the start of a paragraph. Write `2024\. was a good year`.

**Hash, plus, hyphen and greater-than at the start of a line.** `\# not a heading`, `\- not a bullet`, `\+ not a bullet` and `\> not a quote` keep the line as text. Only the first character needs the backslash.

**Square brackets and angle brackets.** `\[not a link](/foo)` stays literal. `<div>` is raw HTML, and MiaoYan's renderer lets raw HTML through, so a bare `<div>` in your prose can vanish into the page. Write `\<div>` or `&lt;div&gt;`.

**Pipes in tables.** In a GFM table a `|` ends the cell, even inside backticks. Write `\|`, and GFM's spec example shows it working in plain text, code spans and bold. The [cheat sheet](/blog/markdown-cheat-sheet/) repeats this in its table section.

**Tildes.** `~~text~~` is strikethrough. For a literal double tilde, `\~\~`.

## HTML entities as an alternative

An entity such as `&amp;`, `&lt;` or `&#35;` also prints a literal character. Numeric references take one to seven decimal digits, or `&#x` plus one to six hex digits. The useful case is `&nbsp;` for a non-breaking space, or `&lt;` where you want to be sure a tag is not parsed.

There is a limit. The spec says entities cannot stand in for structural symbols, so `&#42;foo&#42;` prints literal asterisks and is not emphasis, and `&#42; foo` is not a list item. So an entity works as an escape for `*`. Inside code spans and code blocks entities are not recognized either, and `&ouml;` stays as typed.

## Code as an escape

A code span is the simplest escape. Inside backticks, every character is literal, backslashes included: `` `\*` `` shows a backslash and an asterisk. Use it for filenames like `my_file_name.md`, regexes, shell globs and prices. To put a backtick inside a code span, use a longer run of backticks around it. Fenced blocks do the same for several lines.

Escapes also do not work in autolinks (`<https://example.com?find=\*>`) or raw HTML attributes, but they do work in link destinations, link titles and the info string of a fenced block.

## Dollar signs in MiaoYan

MiaoYan renders math with KaTeX using `$...$` for inline and `$$...$$` for display, in every preview. A dollar sign in prose can therefore start a formula. Two layers protect ordinary prices. The Swift side treats `$` followed by digits, an optional decimal part, and then a character that is not a letter, digit or math operator as currency, and the preview script applies a similar rule. So `costs $5 or $10.` stays text.

The guard stops at letters and operators. `$5M and $10M` is read as a formula between the two dollars, and `$5-10` is also treated as possible math. A backslash does not help here: `\$` is an ordinary Markdown escape, so the parser turns it into a bare `$` before the preview script and KaTeX scan for dollar signs, and `\$5M and \$10M` still becomes a formula. Two reliable options: put the amount in a code span, such as `$5M`, or reword it as "5M dollars". Code spans and fenced blocks are skipped by the math pass. See [LaTeX math in Markdown](/blog/latex-math-in-markdown/) for how the formula side works.

## Differences between renderers

Escaping is defined by CommonMark, so the backslash rules above are the same in GitHub and any other conforming parser. The differences are in what counts as syntax. GFM adds tables and strikethrough, so `|` and `~` need escaping there but not in strict CommonMark. Math with dollar signs is not part of either standard: MiaoYan renders it, other tools may not, and a note that mentions `$` heavily may look different in each. Raw HTML is another split. MiaoYan passes it through, while some hosts strip it, so `\<div>` is the form that survives everywhere.

## Checking the result

Open the preview and look for backslashes you did not mean to show, and for syntax that disappeared. A missing word usually means an angle bracket was read as a tag; a stray list means a number and a dot. If a character still misbehaves, wrap it in a code span to confirm the parser is the cause.

## FAQ

### Do I escape characters inside a code block?

No. Backslash escapes do not work in code spans or code blocks, so a backslash would print.

### How do I show a literal backslash?

Type two: `\\`.

### Why does my numbered line turn into a list?

A line that starts with digits and a dot is a list marker. Escape the dot, as in `2024\.`.
