Markdown 的提示框（callout）是一段首行带标记的引用，比如 `> [!NOTE]`，支持它的应用会把它渲染成带图标和颜色的方框。这套写法没有统一标准，GitHub 定了五种类型（NOTE、TIP、IMPORTANT、WARNING、CAUTION），Obsidian 有自己更长的一套，还支持标题和折叠，MkDocs Material 和 Docusaurus 这类文档生成器用的则是完全不同的语法。稳妥的做法是按笔记最终被阅读的地方选方言，并且写成即使退化成普通引用也还能读懂的样子。

这篇讲的是几种方言之间的差别，引用的基本写法和简短的 `[!NOTE]` 小节在[Markdown 引用和嵌套列表](/zh/blog/markdown-blockquotes-and-nested-lists/)里。

## GitHub 的 alerts

GitHub 管它叫 alerts，在基本写作和格式语法那一页里写成基于引用语法的 Markdown 扩展，一共五种，类型写在引用的第一行：

```markdown
> [!NOTE]
> Useful information that users should know, even when skimming content.

> [!TIP]
> Helpful advice for doing things better or more easily.

> [!IMPORTANT]
> Key information users need to know to achieve their goal.

> [!WARNING]
> Urgent info that needs immediate user attention to avoid problems.

> [!CAUTION]
> Advises about risks or negative outcomes of certain actions.
```

类型是固定的几个，别的词不算 alert，文档里标记单独占引用的一行，正文写在后面几行，按文档写的语法没有自定义标题，也没有折叠。文档另外给了三条使用建议，只在对读者成功至关重要时才用，每篇文章一两个，不要连续放。它还写明 alerts 不能嵌套在其他元素里，所以放进列表项或另一层引用里，已经在 GitHub 承诺的范围之外。

文档页没有列出 alerts 会在哪些页面渲染，只说在 GitHub 上会显示成带颜色和图标的样式。笔记如果要放进 README、issue、pull request 或 wiki，在那里贴一个测试用的 alert 看一眼，比直接假设更可靠。

## Obsidian 的 callouts

Obsidian 的帮助页显示它用同样的 `> [!type]` 开头，但功能更多。类型不分大小写，取自更长的一份清单，`note`、`abstract`、`info`、`todo`、`tip`、`success`、`question`、`warning`、`failure`、`danger`、`bug`、`example` 和 `quote`，另有一批别名，比如 `summary` 和 `tldr` 对应 `abstract`，`hint` 和 `important` 对应 `tip`，`caution` 和 `attention` 对应 `warning`，不认识的类型会退回 `note`。

标记后面的文字成为标题，标记后紧跟 `+` 或 `-` 就变成可折叠，分别是默认展开和默认折叠：

```markdown
> [!tip] Callouts can have custom titles
> Like this one.

> [!faq]- Are callouts foldable?
> Yes. The contents are hidden while it is collapsed.

> [!question] Can callouts be nested?
>
> > [!todo] Yes, they can.
```

Obsidian 支持嵌套，还可以用 CSS 片段给某个 `data-callout` 值设置 `--callout-color` 和 `--callout-icon` 来自定义类型。

它和 GitHub 的重叠是真实的，但只有一部分。`[!NOTE]`、`[!TIP]` 和 `[!WARNING]` 在两边意思大致相同，`[!IMPORTANT]` 在 GitHub 是独立类型，在 Obsidian 却是 `tip` 的别名，同一条笔记换个地方颜色和图标就变了，`[!CAUTION]` 在 GitHub 是独立类型，在 Obsidian 是 `warning` 的别名。标题、折叠和大部分 Obsidian 类型在 GitHub 上都不存在。

## MkDocs Material 和 Docusaurus

文档生成器用自己的语法，而且根本不是引用。

MkDocs Material 叫它 admonitions，要在 `mkdocs.yml` 里启用 `admonition` 扩展（可折叠的要加 `pymdownx.details`，嵌套任意内容要加 `pymdownx.superfences`），正文缩进四个空格：

```markdown
!!! note "Optional title"
    Content here.

??? tip
    Collapsed by default.

???+ tip
    Expanded by default.
```

类型后面写一个空字符串可以去掉标题，支持的类型有 `note`、`abstract`、`info`、`tip`、`success`、`question`、`warning`、`failure`、`danger`、`bug`、`example` 和 `quote`。

Docusaurus 用三个冒号，关键字取自 `note`、`tip`、`info`、`warning` 和 `danger`，标题写在方括号里：

```markdown
:::note[Your title]

Markdown works inside.

:::
```

Docusaurus 的文档要求开头和结尾那两行前后留空行，因为 Prettier 会把这种写法弄坏，嵌套时外层要比内层多写冒号。

这两种都是站点生成器在构建时才有的功能，用这个工具发布文档时是对的选择，拿来写在编辑器里打开的笔记就不合适，因为工具之外没有谁认识它们。

## 不认识时各自是什么样子

对不认识它的解析器来说，这些全是普通文字，读起来的样子各不相同：

| 写法 | 不支持的渲染器里 |
| --- | --- |
| `> [!NOTE]` 加正文 | 一段普通引用，开头是字面的 `[!NOTE]` |
| `> [!tip]- Title` | 一段普通引用，第一行是 `[!tip]- Title` |
| `!!! note` 加缩进正文 | 以 `!!! note` 开头的普通文字，缩进的正文可能显示成纯文本，也可能成为代码块，取决于空行 |
| `:::note` ... `:::` | 带着冒号和单词的普通段落 |

GitHub 这种写法退化得最好，引用本身保留，标记词也还能当标签读，这是笔记要在多个工具间流转时优先选它的实际理由。admonition 一类退化得更糟，四个空格的正文可能落成代码块。文件要在多个应用里读时，哪些功能算标准可以看 [CommonMark 和 GFM 的区别](/zh/blog/commonmark-vs-gfm/)。

## 妙言怎么处理

妙言 4.9.0 在这份清单里只支持 GitHub 这一种，从源码能看出做法。cmark-gfm 渲染完之后，一个后处理函数会找首段以 `[!NOTE]`、`[!TIP]`、`[!IMPORTANT]`、`[!WARNING]` 或 `[!CAUTION]` 开头的 `<blockquote>`，大小写都认，把它改写成带标题行和图标的 `div`。因为处理的是渲染后的 HTML，围栏代码块里的标记永远匹配不到，测试里也有这一条。嵌在 alert 里的引用仍然是引用，五种颜色分别是蓝、绿、紫、琥珀和红。

代码没有做的事也要说清楚。`[!DANGER]` 这样不认识的词保持普通引用，Obsidian 的 `+` 和 `-` 折叠标记也一样，因为标记后面直接跟着别的字符就不会转换。没有自定义标题，没有折叠，`!!!` 和 `:::` 也不认识，会按文字显示。还有一个从代码里看到的边界，标记后面的空格是被接受的，所以 `> [!tip] My title` 会变成一个 Tip 框，正文以 My title 开头，而不是标题叫 My title 的框，正文还是写到下一行，这是 GitHub 文档给的写法。

笔记里需要折叠时，用 `<details>`，写法在[Markdown 折叠区块](/zh/blog/markdown-collapsible-sections/)里，妙言的预览和 GitHub 都能用。

## 怎么选，怎么检查

按去处选。README 和仓库里的文件用 GitHub 写法，住在 Obsidian 里的资料库可以用它完整的一套，并接受其他应用只会显示标记，文档站点就用生成器定义的那套。要在不同工具间流转的笔记，用 GitHub 的五种类型，并把关键的一句放在正文里，不放在标题里。

检查就是在每个会阅读它的地方打开一遍，看到带图标的框说明方言被支持，看到引用里显示着 `[!NOTE]` 说明不支持，但没有任何东西坏掉。标记后面多了一个字符、类型拼错，或者在 GitHub 上把提示框缩进在列表项下面，是提示框没出现最常见的几个原因。

## 常见问题

### GitHub 支持哪几种类型？
五种，NOTE、TIP、IMPORTANT、WARNING 和 CAUTION，标记单独写在引用的第一行。

### GitHub 的 alert 能自定义标题吗？
按文档写的语法不能，类型词本身就是标题，Obsidian 和 MkDocs Material 可以自定义标题。

### 为什么我的提示框显示成带 [!NOTE] 的普通引用？
应用没有实现这套语法，或者标记和它认识的类型不完全一致，检查拼写，并确认正文在下一行。

### 所有 Markdown 编辑器都支持提示框吗？
不是，它们都是扩展，每种方言只有为它做的工具才认识。
