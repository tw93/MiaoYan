Every math symbol in LaTeX is a backslash command: `\alpha` gives α, `\leq` gives ≤, `\sum` gives ∑. Put the command between `$...$` for inline math or `$$...$$` for a block. The tables below group the commands people look up most, and each one was run through KaTeX 0.16.0, the engine bundled in MiaoYan V4.9.0. Setup, delimiters and environments such as matrices are in [LaTeX math in Markdown](/blog/latex-math-in-markdown/).

## How to read the tables

Each row pairs a command with the symbol it produces, written as a plain character so it shows up on this page. Wrap the command in dollar signs in your note and KaTeX draws its own glyph, which can differ a little in shape (compare `\epsilon` and `\varepsilon`).

MiaoYan's preview runs KaTeX's auto-render extension with four delimiter pairs: `$$...$$` and `\[...\]` for display math, `$...$` and `\(...\)` for inline math. The KaTeX files ship inside the app, so no network is needed.

## Greek letters

| Symbol | Command | Symbol | Command |
| :-- | :-- | :-- | :-- |
| α | `\alpha` | β | `\beta` |
| γ | `\gamma` | δ | `\delta` |
| ϵ | `\epsilon` | ε | `\varepsilon` |
| ζ | `\zeta` | η | `\eta` |
| θ | `\theta` | ϑ | `\vartheta` |
| ι | `\iota` | κ | `\kappa` |
| λ | `\lambda` | μ | `\mu` |
| ν | `\nu` | ξ | `\xi` |
| π | `\pi` | ϖ | `\varpi` |
| ρ | `\rho` | ϱ | `\varrho` |
| σ | `\sigma` | ς | `\varsigma` |
| τ | `\tau` | υ | `\upsilon` |
| ϕ | `\phi` | φ | `\varphi` |
| χ | `\chi` | ψ | `\psi` |
| ω | `\omega` | | |

Capitals exist only where they differ from a Latin letter.

| Symbol | Command | Symbol | Command |
| :-- | :-- | :-- | :-- |
| Γ | `\Gamma` | Δ | `\Delta` |
| Θ | `\Theta` | Λ | `\Lambda` |
| Ξ | `\Xi` | Π | `\Pi` |
| Σ | `\Sigma` | Υ | `\Upsilon` |
| Φ | `\Phi` | Ψ | `\Psi` |
| Ω | `\Omega` | | |

Capital alpha and beta, and omicron, have no command in classic LaTeX, so you type `A`, `B`, `O` and `o`, though KaTeX also accepts `\Alpha`, `\Beta` and `\omicron`. Slanted capitals are `\varGamma`, `\varDelta` and so on.

## Operators and relations

| Symbol | Command | Meaning |
| :-- | :-- | :-- |
| ± | `\pm` | plus or minus |
| ∓ | `\mp` | minus or plus |
| × | `\times` | multiplication, cross product |
| ÷ | `\div` | division |
| ⋅ | `\cdot` | centered dot, dot product |
| ∗ | `\ast` | asterisk operator, convolution |
| ⋆ | `\star` | star |
| ∘ | `\circ` | composition |
| ⊕ | `\oplus` | direct sum, exclusive or |
| ⊗ | `\otimes` | tensor product |
| ∪ | `\cup` | union |
| ∩ | `\cap` | intersection |
| ∧ | `\wedge` | logical and (also `\land`) |
| ∨ | `\vee` | logical or (also `\lor`) |
| ∖ | `\setminus` | set difference |

| Symbol | Command | Meaning |
| :-- | :-- | :-- |
| ≠ | `\neq` | not equal (also `\ne`) |
| ≈ | `\approx` | approximately equal |
| ≡ | `\equiv` | identical, congruent |
| ∼ | `\sim` | similar, distributed as |
| ≃ | `\simeq` | asymptotically equal |
| ≅ | `\cong` | isomorphic, congruent |
| ∝ | `\propto` | proportional to |
| ≤ | `\leq` | less than or equal (also `\le`) |
| ≥ | `\geq` | greater than or equal (also `\ge`) |
| ≪ | `\ll` | much less than |
| ≫ | `\gg` | much greater than |
| ≺ | `\prec` | precedes |
| ≻ | `\succ` | succeeds |
| ∥ | `\parallel` | parallel |
| ⊥ | `\perp` | perpendicular |
| ∣ | `\mid` | divides, such that |
| ⊢ | `\vdash` | proves |
| ⊨ | `\models` | models, entails |

Many relations negate with a leading `n`, as in `\nless`, `\nleq` and `\nsim`, or with `\not` in front, as in `\not =`.

## Arrows

| Symbol | Command | Meaning |
| :-- | :-- | :-- |
| → | `\to` | maps to (also `\rightarrow`) |
| ← | `\leftarrow` | left arrow (also `\gets`) |
| ↔ | `\leftrightarrow` | both directions |
| ⇒ | `\Rightarrow` | implies, double arrow |
| ⇐ | `\Leftarrow` | double left arrow |
| ⇔ | `\Leftrightarrow` | if and only if |
| ⟹ | `\implies` | implies, with extra spacing |
| ⟺ | `\iff` | if and only if, with extra spacing |
| ↦ | `\mapsto` | function maps element to |
| ⟶ | `\longrightarrow` | long arrow |
| ⟼ | `\longmapsto` | long maps-to arrow |
| ↑ | `\uparrow` | up |
| ↓ | `\downarrow` | down |
| ↕ | `\updownarrow` | up and down |
| ↗ | `\nearrow` | north-east |
| ↘ | `\searrow` | south-east |
| ↪ | `\hookrightarrow` | inclusion, embedding |
| ⇌ | `\rightleftharpoons` | reversible reaction |

An arrow that stretches to fit a label is `\xrightarrow{text}`, and with a label below too, `\xrightarrow[under]{over}`. `\xleftarrow`, `\xRightarrow` and `\xmapsto` work the same way.

## Sets, logic and number systems

| Symbol | Command | Meaning |
| :-- | :-- | :-- |
| ∀ | `\forall` | for all |
| ∃ | `\exists` | there exists |
| ∄ | `\nexists` | there does not exist |
| ¬ | `\neg` | not (also `\lnot`) |
| ∈ | `\in` | element of |
| ∉ | `\notin` | not an element of |
| ∋ | `\ni` | contains as element |
| ⊂ | `\subset` | subset |
| ⊆ | `\subseteq` | subset or equal |
| ⊊ | `\subsetneq` | proper subset |
| ⊃ | `\supset` | superset |
| ⊇ | `\supseteq` | superset or equal |
| ∅ | `\emptyset` | empty set (also `\varnothing`) |
| ∴ | `\therefore` | therefore |
| ∵ | `\because` | because |
| ℕ | `\mathbb{N}` | natural numbers |
| ℤ | `\mathbb{Z}` | integers |
| ℚ | `\mathbb{Q}` | rationals |
| ℝ | `\mathbb{R}` | real numbers |
| ℂ | `\mathbb{C}` | complex numbers |
| ∞ | `\infty` | infinity |
| ∂ | `\partial` | partial derivative |
| ∇ | `\nabla` | gradient |
| ℵ | `\aleph` | aleph, cardinality |
| ⊤ | `\top` | true, top element |

## Big operators and limits

| Symbol | Command | With limits |
| :-- | :-- | :-- |
| ∑ | `\sum` | `\sum_{i=1}^{n} a_i` |
| ∏ | `\prod` | `\prod_{k=1}^{n} k` |
| ∐ | `\coprod` | `\coprod_{i \in I} X_i` |
| ∫ | `\int` | `\int_a^b f(x)\,dx` |
| ∬ | `\iint` | `\iint_D f\,dA` |
| ∮ | `\oint` | `\oint_C \vec{F} \cdot d\vec{r}` |
| ⋃ | `\bigcup` | `\bigcup_{i \in I} A_i` |
| ⋂ | `\bigcap` | `\bigcap_{i \in I} A_i` |
| ⨁ | `\bigoplus` | `\bigoplus_{i=1}^{n} V_i` |
| ⨂ | `\bigotimes` | `\bigotimes_{i=1}^{n} V_i` |

The limits go after `_` (below) and `^` (above), with braces when they are longer than one character. Where they land depends on the mode:

```markdown
Inline: $\sum_{i=1}^{n} i$ keeps its limits beside the sign, while $\displaystyle\sum_{i=1}^{n} i$ moves them.

$$
\sum_{i=1}^{n} i = \frac{n(n+1)}{2} \qquad \int_0^\infty e^{-x}\,dx = 1
$$
```

Checked against KaTeX 0.16.0: in inline math `\sum` and `\lim` put limits beside the symbol, in display math above and below, and `\int` keeps them beside even in display math. `\limits` forces above and below, as in `\int\limits_a^b`, and `\nolimits` forces beside.

## Accents and decorations

| Command | What it does |
| :-- | :-- |
| `\hat{x}` | hat, estimates and unit vectors |
| `\widehat{xy}` | hat stretched over several letters |
| `\bar{x}` | bar, sample mean |
| `\overline{AB}` | long bar, complex conjugate |
| `\vec{v}` | arrow over one letter, vector |
| `\overrightarrow{AB}` | arrow stretched over a segment |
| `\dot{x}`, `\ddot{x}` | one and two dots, time derivatives |
| `\tilde{x}`, `\widetilde{xy}` | tilde |
| `\acute{a}`, `\grave{a}` | acute and grave |
| `\check{a}`, `\breve{a}` | caron and breve |
| `\underline{x}` | underline |
| `\overbrace{a+b}^{n}` | brace above, with a label |
| `\underbrace{a+b}_{n}` | brace below, with a label |

## Delimiters

Plain `( )` and `[ ]` need no command. The rest:

| Command | Produces |
| :-- | :-- |
| `\{ ... \}` | curly braces |
| `\langle x \rangle` | angle brackets |
| `\lvert x \rvert` | absolute value |
| `\lVert x \rVert` | norm |
| `\lfloor x \rfloor` | floor |
| `\lceil x \rceil` | ceiling |

`\left` and `\right` grow to fit what is between them, `\middle` adds a divider that grows too, and `\big`, `\Big`, `\bigg`, `\Bigg` pick a fixed size:

```markdown
$$
\left( \frac{a}{b} \right) \qquad
\left\{ x \middle\vert x > 0 \right\} \qquad
\Big( \sum_i x_i \Big)
$$
```

Every `\left` needs a `\right`, or KaTeX reports a parse error. When one side should show nothing, use the invisible delimiter `\left.` or `\right.`:

```markdown
$$
\left. \frac{df}{dx} \right\vert_{x=0}
$$
```

## Functions

`sin x` makes italic letters; `\sin x` sets an upright name with correct spacing.

| Group | Commands |
| :-- | :-- |
| Trigonometric | `\sin` `\cos` `\tan` `\cot` `\sec` `\csc` |
| Inverse | `\arcsin` `\arccos` `\arctan` |
| Hyperbolic | `\sinh` `\cosh` `\tanh` |
| Logarithm and exponent | `\log` `\ln` `\lg` `\exp` |
| Limits and bounds | `\lim` `\limsup` `\liminf` `\max` `\min` `\sup` `\inf` |
| Algebra | `\det` `\gcd` `\deg` `\dim` `\ker` `\arg` `\Pr` `\hom` |
| Modular arithmetic | `a \bmod b`, `a \equiv b \pmod n` |

For a name that has no command, use `\operatorname{rank}(A)`. KaTeX also has `\argmax` and `\argmin`, which take limits like `\lim` does.

## Fractions, roots and binomials

| Command | Produces |
| :-- | :-- |
| `\frac{a}{b}` | fraction, sized by the mode |
| `\dfrac{a}{b}` | full-size fraction, even inline |
| `\tfrac{a}{b}` | small fraction, even in display |
| `\cfrac{a}{1 + \cfrac{1}{b}}` | continued fraction |
| `\binom{n}{k}` | binomial coefficient |
| `\dbinom{n}{k}`, `\tbinom{n}{k}` | large and small binomial |
| `\sqrt{x}` | square root |
| `\sqrt[3]{x}` | cube root, any index |
| `{a \over b}`, `{n \choose k}` | older forms of `\frac` and `\binom` |

## Spacing

Math mode ignores the spaces you type, so spacing is a command.

| Command | Width |
| :-- | :-- |
| `\,` | thin, 3/18 em |
| `\:` | medium, 4/18 em |
| `\;` | thick, 5/18 em |
| `\!` | negative thin, pulls closer |
| `\quad` | 1 em |
| `\qquad` | 2 em |
| `\hspace{2em}` | any width you give |
| `\phantom{x}` | blank space the size of `x` |

A backslash followed by a space is an ordinary word space, and `~` is a non-breaking one. `f(x)\,dx` is the usual way to set `dx` off from the integrand.

## Text and fonts inside math

| Command | Produces |
| :-- | :-- |
| `\text{if } x > 0` | upright text, spaces kept |
| `\mathrm{d}x` | upright letters, as in a differential |
| `\mathbf{v}` | bold |
| `\boldsymbol{\alpha}` | bold Greek and symbols |
| `\mathbb{R}` | blackboard bold |
| `\mathcal{L}` | calligraphic |
| `\mathfrak{g}` | Fraktur |
| `\mathsf{T}`, `\mathtt{x}` | sans serif, monospace |

Dots between terms are `\ldots` on the baseline, as in `a_1, \ldots, a_n`, and `\cdots` centered, as in `a_1 + \cdots + a_n`. To print characters LaTeX treats as syntax, escape them: `\%`, `\#`, `\&`, `\_`, `\$`, `\{` and `\}`. An unescaped `%` starts a comment.

## Gotchas

1. **Braces.** `{` and `}` only group, so `{x}` prints `x`. To show them, write `\{` and `\}`, or `\lbrace` and `\rbrace`. In MiaoYan V4.9.0 the backslash forms are safe, because the Markdown pass shields math. In a renderer that does not, CommonMark's rule applies: a backslash before ASCII punctuation, including `{`, `|`, `,`, `;`, `!` and `\`, is dropped before KaTeX runs. For notes that travel between apps, the word forms (`\lbrace`, `\vert`, `\quad`) survive everywhere.
2. **`|` and `\|`.** A bare `|` is a single bar. `\|` is a double bar, the same as `\Vert`. For absolute value and norms, prefer `\lvert x \rvert` and `\lVert v \rVert`, which are proper left and right delimiters. Inside a Markdown table a literal pipe splits the column, so write `\vert`; MiaoYan masks pipes inside math, other tools do not, and [Markdown tables](/blog/markdown-tables/) covers the rest.
3. **Underscores and asterisks.** In plain Markdown, `_` and `*` start emphasis, which can chew up `a_i * b_j`. MiaoYan V4.9.0 shields math from that: it scans for the four delimiter pairs outside code spans and fences, skips escaped ones, and hands the formula text to KaTeX untouched, so `\\`, `\{`, `_` and `*` arrive intact. A formula with no closing delimiter is not protected, and neither is anything inside a code span.
4. **A command shows as plain text.** The name is either not in KaTeX or has a typo. KaTeX 0.16.0 rejects `\mathbbm{1}`, `\mathds{1}` and `\usepackage{amsmath}`, while `\mathbb{1}` and `\bm{x}` work. When MiaoYan cannot parse a formula it shows the source, dollar signs included.
5. **Dollar signs in prose.** Prices can start a formula; see the dollar section of [LaTeX math in Markdown](/blog/latex-math-in-markdown/).

## FAQ

### Why is my sum limit beside the symbol instead of above it?

Inline math keeps limits beside the sign. Use a `$$` block, or add `\displaystyle` or `\limits` inline.

### How do I write a vector or a bold letter?

`\vec{v}` draws an arrow over one letter, and `\mathbf{v}` makes it bold. For bold Greek, use `\boldsymbol{\alpha}`, because `\mathbf` leaves Greek letters unchanged.
