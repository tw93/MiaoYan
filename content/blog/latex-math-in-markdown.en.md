Write inline math between single dollar signs, like `$E = mc^2$`, and block math between double dollar signs on their own lines. Markdown itself has no math syntax, so the app's renderer finds those delimiters and typesets the contents with a TeX engine, usually KaTeX or MathJax. In MiaoYan the engine is KaTeX 0.16.0, bundled inside the app, so formulas render without a network connection. The common failures are a dollar sign read as math, an environment that needs a wrapper, and an underscore eaten by Markdown before the engine sees it.

## Inline and block math

```markdown
The energy is $E = mc^2$ in the rest frame.

$$
\int_0^1 x^2 \, dx = \frac{1}{3}
$$
```

Inline math sits in the sentence and uses compact layout. Block math is centered on its own line with full-size operators, so sums and integrals show their limits above and below. If a formula is part of a sentence, use inline. If it should stand on its own, use a block.

MiaoYan accepts four delimiter pairs: `$...$`, `$$...$$`, `\(...\)` and `\[...\]`. The last two are the LaTeX-native forms. You can mix them, but picking one pair for inline and one for block makes notes easier to move between apps.

## Constructs you will use most

| You want | Write |
|---|---|
| Fraction | `\frac{a}{b}` |
| Square root, nth root | `\sqrt{x}`, `\sqrt[3]{x}` |
| Superscript, subscript | `x^2`, `x_i`, and braces for more than one character: `x^{10}`, `x_{ij}` |
| Sum with limits | `\sum_{i=1}^{n} x_i` |
| Integral | `\int_a^b f(x)\,dx` |
| Greek letters | `\alpha`, `\beta`, `\pi`, `\Omega` |
| Text inside math | `\text{if } x > 0` |
| Limit | `\lim_{t \to \infty}` |

`\frac`, `\sum`, `\int`, `\sqrt` and `\text` are all listed as supported in the KaTeX documentation. The `\,` before `dx` adds a thin space, which matches how integrals are usually typeset.

### Matrices, cases and aligned equations

```markdown
$$
\begin{pmatrix} a & b \\ c & d \end{pmatrix}
$$

$$
f(x) = \begin{cases} x^2 & x \ge 0 \\ 0 & x < 0 \end{cases}
$$

$$
\begin{aligned}
a &= b + c \\
  &= d
\end{aligned}
$$
```

Use `&` to separate columns and `\\` to end a row. KaTeX lists `matrix`, `pmatrix`, `bmatrix`, `cases`, `align`, `aligned` and others as supported environments. In MiaoYan, wrap `aligned` inside `$$`. KaTeX's auto-render extension can pick up bare `\begin{align}` blocks by default, but MiaoYan's delimiter list has only the four pairs above, so a bare `\begin{align}` is not recognized as a math block. The wrapped form works across more tools anyway.

## How it actually works

A Markdown parser has no idea what a formula is. If it sees `a_b_c`, it may read the underscores as emphasis. If it sees `\\`, it may read one backslash as an escape. So an app has to protect the math before the Markdown pass, then hand the original text to the TeX engine afterwards.

MiaoYan does this in two steps. First, a pre-pass finds math ranges outside code spans and fences, ignores escaped delimiters, and shields their contents from the parser. Second, the rendered HTML loads into a web view, where KaTeX's auto-render script scans the page for the four delimiter pairs and replaces them with typeset output. KaTeX's default ignored tags include `code` and `pre`, so math inside a code fence is never rendered.

Engines also differ in speed and LaTeX coverage. KaTeX is fast and renders synchronously, but supports a subset of LaTeX. MathJax is the other common engine, and Typora's site says it supports most MathJax extensions, including mhchem and AMSmath. If your formulas come from a paper using exotic packages, test them in the editor before relying on them. MiaoYan's bundled KaTeX 0.16.0 runs entirely from files inside the app.

## Dollar signs and prices

A single `$` is also a currency symbol, which is the most common pitfall. MiaoYan has a guard for it: a dollar sign followed by digits and then something that is not a math continuation is treated as currency. So `It costs $5 today` stays text, while `$2+2$` is still math, because a `+` after the digits counts as math. Other editors may not have this guard, so escape the dollar sign if the note has to look right everywhere:

```markdown
The ticket costs \$5, and the upgrade costs \$10.
```

A backslash before the dollar sign tells the renderer to leave it alone. MiaoYan enables escape processing for this, and its pre-pass skips escaped delimiters.

## What goes wrong and how to check

1. **Nothing renders and the dollar signs show.** The closing delimiter is missing or crosses a code span. Math cannot start in a code span and end outside it.
2. **The formula is cut after an underscore.** The text was read as Markdown. In MiaoYan this is already protected, but in other apps use `\_` or switch to a block.
3. **A block formula stays in a paragraph with stray line breaks.** Put `$$` on its own lines with a blank line before and after. MiaoYan also cleans line breaks inside single-paragraph `$$` blocks.
4. **Unbalanced braces.** Every `{` needs a `}`. The engine will not typeset a formula with unbalanced braces.
5. **A command does nothing.** It may be outside KaTeX's supported list. Check the KaTeX "Supported Functions" page before assuming a bug.

To test your setup, put these three lines in a new note and open the preview with `⌘3`, or split mode with `⌘\`:

```markdown
Inline: $\sqrt{2}$

$$
\sum_{i=1}^{n} i = \frac{n(n+1)}{2}
$$

Price: \$5
```

If you see a root sign, a sum with limits, and a literal `$5`, the engine and the escape both work. Math also works inside MiaoYan's presentation mode, covered in [Markdown to slides](/blog/markdown-to-slides/). For the rest of the syntax, see the [Markdown cheat sheet](/blog/markdown-cheat-sheet/).

## Limits to know

- KaTeX covers most of what notes need, but not all of LaTeX. Packages and macros defined with `\newcommand` in a preamble are not part of a Markdown note.
- Math is rendered in the preview. The editor pane shows raw source.
- PDF, HTML and image exports are produced from the rendered preview. Check an exported file once to verify any formulas you care about; [Markdown to PDF on Mac](/blog/markdown-to-pdf-mac/) covers the PDF route.

## FAQ

### Does MiaoYan need an internet connection for math?

No. KaTeX is bundled inside the app. The exception in this family of features is PlantUML, which is sent to a public server.

### KaTeX or MathJax, which should I pick?

If you need a specific MathJax-only extension, use an editor that offers it. For ordinary algebra, calculus, matrices and aligned equations, KaTeX is enough and renders quickly.

### How do I write a literal dollar sign?

Put a backslash before it, as in `\$5`, or put it in inline code.

### Can I number equations?

Typora's site says it can auto-number equations when enabled. MiaoYan has no equation numbering setting. KaTeX supports `\tag{1}` on lines in some environments, which gives you manual labels.
