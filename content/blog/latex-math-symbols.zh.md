LaTeX 里每个数学符号都是一条反斜杠命令，`\alpha` 是 α，`\leq` 是 ≤，`\sum` 是 ∑，把命令放在 `$...$` 里是行内公式，放在 `$$...$$` 里是块级公式。下面的表格按类别整理了最常查的命令，每一条都能在 KaTeX 0.16.0 里渲染，这也是妙言 V4.9.0 内置的引擎版本。定界符、矩阵这类环境的写法见 [Markdown 里写 LaTeX 公式](/zh/blog/latex-math-in-markdown/)。

## 表格怎么看

每一行把命令和它生成的符号放在一起，符号写成普通字符，在本页也能直接看到。把命令放进笔记的美元符号里，KaTeX 会画出它自己的字形，个别符号的形状会有细微差别，比如 `\epsilon` 和 `\varepsilon`。

妙言的预览使用 KaTeX 的 auto-render 扩展，识别四对定界符，`$$...$$` 和 `\[...\]` 是块级，`$...$` 和 `\(...\)` 是行内，KaTeX 文件随应用打包，不需要联网。

## 希腊字母

| 符号 | 命令 | 符号 | 命令 |
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

大写字母只有和拉丁字母长得不一样的才有命令。

| 符号 | 命令 | 符号 | 命令 |
| :-- | :-- | :-- | :-- |
| Γ | `\Gamma` | Δ | `\Delta` |
| Θ | `\Theta` | Λ | `\Lambda` |
| Ξ | `\Xi` | Π | `\Pi` |
| Σ | `\Sigma` | Υ | `\Upsilon` |
| Φ | `\Phi` | Ψ | `\Psi` |
| Ω | `\Omega` | | |

大写的 Alpha、Beta 和 Omicron 在经典 LaTeX 里没有命令，直接写 `A`、`B`、`O` 和 `o` 就行，不过 KaTeX 也认 `\Alpha`、`\Beta` 和 `\omicron`。倾斜的大写是 `\varGamma`、`\varDelta` 这一类。

## 运算符和关系符

| 符号 | 命令 | 含义 |
| :-- | :-- | :-- |
| ± | `\pm` | 加减 |
| ∓ | `\mp` | 减加 |
| × | `\times` | 乘号、叉积 |
| ÷ | `\div` | 除号 |
| ⋅ | `\cdot` | 居中的点，点积 |
| ∗ | `\ast` | 星号运算符，卷积 |
| ⋆ | `\star` | 星号 |
| ∘ | `\circ` | 复合 |
| ⊕ | `\oplus` | 直和、异或 |
| ⊗ | `\otimes` | 张量积 |
| ∪ | `\cup` | 并集 |
| ∩ | `\cap` | 交集 |
| ∧ | `\wedge` | 逻辑与，也可写 `\land` |
| ∨ | `\vee` | 逻辑或，也可写 `\lor` |
| ∖ | `\setminus` | 差集 |

| 符号 | 命令 | 含义 |
| :-- | :-- | :-- |
| ≠ | `\neq` | 不等于，也可写 `\ne` |
| ≈ | `\approx` | 约等于 |
| ≡ | `\equiv` | 恒等、同余 |
| ∼ | `\sim` | 相似、服从分布 |
| ≃ | `\simeq` | 渐近等于 |
| ≅ | `\cong` | 同构、全等 |
| ∝ | `\propto` | 正比于 |
| ≤ | `\leq` | 小于等于，也可写 `\le` |
| ≥ | `\geq` | 大于等于，也可写 `\ge` |
| ≪ | `\ll` | 远小于 |
| ≫ | `\gg` | 远大于 |
| ≺ | `\prec` | 先于 |
| ≻ | `\succ` | 后于 |
| ∥ | `\parallel` | 平行 |
| ⊥ | `\perp` | 垂直 |
| ∣ | `\mid` | 整除、使得 |
| ⊢ | `\vdash` | 推出 |
| ⊨ | `\models` | 蕴含、模型满足 |

很多关系符可以在前面加 `n` 取反，比如 `\nless`、`\nleq` 和 `\nsim`，也可以在符号前面加 `\not`，比如 `\not =`。

## 箭头

| 符号 | 命令 | 含义 |
| :-- | :-- | :-- |
| → | `\to` | 映射到，也可写 `\rightarrow` |
| ← | `\leftarrow` | 左箭头，也可写 `\gets` |
| ↔ | `\leftrightarrow` | 双向 |
| ⇒ | `\Rightarrow` | 推出，双线箭头 |
| ⇐ | `\Leftarrow` | 双线左箭头 |
| ⇔ | `\Leftrightarrow` | 当且仅当 |
| ⟹ | `\implies` | 推出，两侧留有间距 |
| ⟺ | `\iff` | 当且仅当，两侧留有间距 |
| ↦ | `\mapsto` | 把元素映射到 |
| ⟶ | `\longrightarrow` | 长箭头 |
| ⟼ | `\longmapsto` | 长映射箭头 |
| ↑ | `\uparrow` | 向上 |
| ↓ | `\downarrow` | 向下 |
| ↕ | `\updownarrow` | 上下 |
| ↗ | `\nearrow` | 东北 |
| ↘ | `\searrow` | 东南 |
| ↪ | `\hookrightarrow` | 包含、嵌入 |
| ⇌ | `\rightleftharpoons` | 可逆反应 |

会跟着标签变长的箭头是 `\xrightarrow{text}`，上下都要标签就写 `\xrightarrow[under]{over}`，`\xleftarrow`、`\xRightarrow` 和 `\xmapsto` 用法相同。

## 集合、逻辑和数集

| 符号 | 命令 | 含义 |
| :-- | :-- | :-- |
| ∀ | `\forall` | 对任意 |
| ∃ | `\exists` | 存在 |
| ∄ | `\nexists` | 不存在 |
| ¬ | `\neg` | 非，也可写 `\lnot` |
| ∈ | `\in` | 属于 |
| ∉ | `\notin` | 不属于 |
| ∋ | `\ni` | 包含元素 |
| ⊂ | `\subset` | 子集 |
| ⊆ | `\subseteq` | 子集或相等 |
| ⊊ | `\subsetneq` | 真子集 |
| ⊃ | `\supset` | 超集 |
| ⊇ | `\supseteq` | 超集或相等 |
| ∅ | `\emptyset` | 空集，也可写 `\varnothing` |
| ∴ | `\therefore` | 所以 |
| ∵ | `\because` | 因为 |
| ℕ | `\mathbb{N}` | 自然数 |
| ℤ | `\mathbb{Z}` | 整数 |
| ℚ | `\mathbb{Q}` | 有理数 |
| ℝ | `\mathbb{R}` | 实数 |
| ℂ | `\mathbb{C}` | 复数 |
| ∞ | `\infty` | 无穷 |
| ∂ | `\partial` | 偏导 |
| ∇ | `\nabla` | 梯度 |
| ℵ | `\aleph` | 阿列夫，基数 |
| ⊤ | `\top` | 真，最大元 |

## 大型运算符和上下限

| 符号 | 命令 | 带上下限的写法 |
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

上下限分别写在 `_`（下）和 `^`（上）后面，超过一个字符就加花括号，落在符号的哪里取决于公式的模式：

```markdown
行内：$\sum_{i=1}^{n} i$ 的上下限在符号旁边，$\displaystyle\sum_{i=1}^{n} i$ 则挪到上下方。

$$
\sum_{i=1}^{n} i = \frac{n(n+1)}{2} \qquad \int_0^\infty e^{-x}\,dx = 1
$$
```

在 KaTeX 0.16.0 里，行内公式里 `\sum` 和 `\lim` 的上下限在符号旁边，块级公式里在上下方，`\int` 即使在块级公式里也在旁边。`\limits` 强制放在上下方，比如 `\int\limits_a^b`，`\nolimits` 强制放在旁边。

## 重音和修饰

| 命令 | 作用 |
| :-- | :-- |
| `\hat{x}` | 帽子，估计量和单位向量 |
| `\widehat{xy}` | 盖在多个字母上的宽帽子 |
| `\bar{x}` | 横线，样本均值 |
| `\overline{AB}` | 长横线，复共轭 |
| `\vec{v}` | 单个字母上的箭头，向量 |
| `\overrightarrow{AB}` | 盖在线段上的长箭头 |
| `\dot{x}`、`\ddot{x}` | 一点和两点，对时间的导数 |
| `\tilde{x}`、`\widetilde{xy}` | 波浪线 |
| `\acute{a}`、`\grave{a}` | 锐音符和重音符 |
| `\check{a}`、`\breve{a}` | 抑扬符和短音符 |
| `\underline{x}` | 下划线 |
| `\overbrace{a+b}^{n}` | 上方花括号，带标签 |
| `\underbrace{a+b}_{n}` | 下方花括号，带标签 |

## 括号和定界符

普通的 `( )` 和 `[ ]` 不需要命令，其余的写法如下。

| 命令 | 效果 |
| :-- | :-- |
| `\{ ... \}` | 花括号 |
| `\langle x \rangle` | 尖括号 |
| `\lvert x \rvert` | 绝对值 |
| `\lVert x \rVert` | 范数 |
| `\lfloor x \rfloor` | 向下取整 |
| `\lceil x \rceil` | 向上取整 |

`\left` 和 `\right` 会随中间内容变大，`\middle` 加一条同样会变大的分隔线，`\big`、`\Big`、`\bigg`、`\Bigg` 则是固定的几档大小：

```markdown
$$
\left( \frac{a}{b} \right) \qquad
\left\{ x \middle\vert x > 0 \right\} \qquad
\Big( \sum_i x_i \Big)
$$
```

每个 `\left` 都要有对应的 `\right`，否则 KaTeX 会报解析错误，某一侧不想显示任何东西时，用不可见的定界符 `\left.` 或 `\right.`：

```markdown
$$
\left. \frac{df}{dx} \right\vert_{x=0}
$$
```

## 常用函数

直接写 `sin x` 得到的是斜体字母，写 `\sin x` 才是直立的函数名并带有正确的间距。

| 类别 | 命令 |
| :-- | :-- |
| 三角函数 | `\sin` `\cos` `\tan` `\cot` `\sec` `\csc` |
| 反三角函数 | `\arcsin` `\arccos` `\arctan` |
| 双曲函数 | `\sinh` `\cosh` `\tanh` |
| 对数和指数 | `\log` `\ln` `\lg` `\exp` |
| 极限和界 | `\lim` `\limsup` `\liminf` `\max` `\min` `\sup` `\inf` |
| 代数 | `\det` `\gcd` `\deg` `\dim` `\ker` `\arg` `\Pr` `\hom` |
| 模运算 | `a \bmod b`、`a \equiv b \pmod n` |

没有现成命令的名字用 `\operatorname{rank}(A)`，KaTeX 还有 `\argmax` 和 `\argmin`，上下限的放法和 `\lim` 一样。

## 分数、根号和二项式

| 命令 | 效果 |
| :-- | :-- |
| `\frac{a}{b}` | 分数，大小随模式变化 |
| `\dfrac{a}{b}` | 完整大小的分数，行内也一样 |
| `\tfrac{a}{b}` | 小号分数，块级里也一样 |
| `\cfrac{a}{1 + \cfrac{1}{b}}` | 连分数 |
| `\binom{n}{k}` | 二项式系数 |
| `\dbinom{n}{k}`、`\tbinom{n}{k}` | 大号和小号二项式 |
| `\sqrt{x}` | 平方根 |
| `\sqrt[3]{x}` | 立方根，次数可以任意 |
| `{a \over b}`、`{n \choose k}` | `\frac` 和 `\binom` 的旧写法 |

## 间距

数学模式会忽略你敲的空格，所以间距要靠命令。

| 命令 | 宽度 |
| :-- | :-- |
| `\,` | 细空格，3/18 em |
| `\:` | 中等空格，4/18 em |
| `\;` | 粗空格，5/18 em |
| `\!` | 负的细空格，让两边靠近 |
| `\quad` | 1 em |
| `\qquad` | 2 em |
| `\hspace{2em}` | 自己指定宽度 |
| `\phantom{x}` | 和 `x` 一样大的空白 |

反斜杠后面跟一个空格是普通的词间空格，`~` 是不换行的空格，`f(x)\,dx` 是把 `dx` 和被积函数隔开的常见写法。

## 公式里的文字和字体

| 命令 | 效果 |
| :-- | :-- |
| `\text{if } x > 0` | 直立文字，空格保留 |
| `\mathrm{d}x` | 直立字母，比如微分符号 |
| `\mathbf{v}` | 粗体 |
| `\boldsymbol{\alpha}` | 粗体的希腊字母和符号 |
| `\mathbb{R}` | 黑板粗体 |
| `\mathcal{L}` | 花体 |
| `\mathfrak{g}` | 哥特体 |
| `\mathsf{T}`、`\mathtt{x}` | 无衬线体、等宽体 |

项与项之间的省略号，`\ldots` 在基线上，比如 `a_1, \ldots, a_n`，`\cdots` 居中，比如 `a_1 + \cdots + a_n`。要输出 LaTeX 里有语法含义的字符就加反斜杠，`\%`、`\#`、`\&`、`\_`、`\$`、`\{` 和 `\}`，没有转义的 `%` 会开始一段注释。

## 容易踩的坑

1. **花括号。** `{` 和 `}` 只负责分组，`{x}` 显示出来就是 `x`，要显示花括号就写 `\{` 和 `\}`，或者 `\lbrace` 和 `\rbrace`。妙言 V4.9.0 里反斜杠写法是安全的，因为 Markdown 解析之前就把公式保护起来了。没有这层保护的渲染器要按 CommonMark 的规则走，反斜杠后面跟 ASCII 标点，包括 `{`、`|`、`,`、`;`、`!` 和 `\`，会在 KaTeX 运行之前被吃掉。笔记要在多个应用之间搬运时，用文字形式的命令（`\lbrace`、`\vert`、`\quad`）到哪里都能用。
2. **`|` 和 `\|`。** 单独的 `|` 是一条竖线，`\|` 是双竖线，和 `\Vert` 一样。绝对值和范数优先用 `\lvert x \rvert` 和 `\lVert v \rVert`，它们是正经的左右定界符。Markdown 表格里的竖线会把单元格劈开，要写 `\vert`；妙言会把公式里的竖线遮蔽起来，别的工具不会，表格的其余规则见 [Markdown 表格：对齐、竖线与单元格换行](/zh/blog/markdown-tables/)。
3. **下划线和星号。** 纯 Markdown 里 `_` 和 `*` 会触发强调，`a_i * b_j` 可能被吃掉一部分。妙言 V4.9.0 对公式做了保护，它在代码段和代码块之外查找四对定界符，跳过被转义的，再把公式原文原样交给 KaTeX，所以 `\\`、`\{`、`_` 和 `*` 都能完整到达。没有结束定界符的公式不受保护，代码段里的内容也不受保护。
4. **命令显示成了普通文字。** 要么这个名字不在 KaTeX 里，要么拼错了。KaTeX 0.16.0 不认 `\mathbbm{1}`、`\mathds{1}` 和 `\usepackage{amsmath}`，`\mathbb{1}` 和 `\bm{x}` 可以用。妙言解析不了公式时会把原文连同美元符号一起显示出来。
5. **正文里的美元符号。** 价格可能被当成公式的开头，见 [Markdown 里写 LaTeX 公式](/zh/blog/latex-math-in-markdown/) 里关于美元符号的一节。

## 常见问题

### 为什么求和的上下限在符号旁边，不在上下方？
行内公式里上下限默认在符号旁边，改用 `$$` 块，或者在行内加 `\displaystyle` 或 `\limits`。

### 向量和粗体字母怎么写？
`\vec{v}` 在单个字母上画箭头，`\mathbf{v}` 是粗体，希腊字母要粗体用 `\boldsymbol{\alpha}`，因为 `\mathbf` 对希腊字母没有效果。
