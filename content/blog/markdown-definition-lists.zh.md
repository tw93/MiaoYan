标准 Markdown 没有定义列表。CommonMark 和 GitHub Flavored Markdown 都没有定义这个语法，常见的「术语一行，下一行写 `: 定义`」只在额外支持它的处理器里有效，比如 Pandoc、kramdown、PHP Markdown Extra，以及开了 `def_list` 扩展的 Python-Markdown（MkDocs 可以加载它）和装了 `markdown-it-deflist` 插件的 markdown-it。靠不住的地方就直接写 HTML 的 `<dl>`、`<dt>` 和 `<dd>`，或者改成加粗术语加一段文字，或者做成两列表格。妙言的预览能渲染 HTML 写法，冒号写法会原样显示成普通文字。

## 定义列表是什么

定义列表把术语和解释配成对，比如术语表、命令行参数说明、配置项清单。HTML 早就有对应的元素，整个列表是 `<dl>`，每个术语是 `<dt>`，每条解释是 `<dd>`，一个术语可以有几条解释，几个术语也可以共用一条。

它读起来像 Markdown 自带的功能，是因为好几个有名的处理器都认一种纯文本简写。这个简写属于扩展，不是语言本身的一部分，所以同一篇笔记在一个工具里是整齐的术语表，换一个工具就成了一堆冒号。什么算标准、什么算扩展，可以看 [CommonMark 和 GFM 有什么区别](/zh/blog/commonmark-vs-gfm/)。

## CommonMark 和 GFM 没有定义列表

CommonMark 规范里没有定义列表这种结构，GFM 规范也没有，它在 CommonMark 之上加的是表格、任务列表、删除线、扩展自动链接和一个标签过滤器。`<dl>` 也不在标签过滤器的名单里，所以 GFM 不会拦它。

输入这样一段：

```markdown
Apple
: A fruit.
```

CommonMark 或 GFM 的解析器只会读出一个段落，冒号那行是它的第二行。用 Pandoc 3.13 跑 `pandoc -f gfm -t html`，得到的是 `<p>Apple : A fruit.</p>`，两行被连在一起，文字没丢，只是没有结构。

## 冒号写法

大家说的冒号写法出自 PHP Markdown Extra，Pandoc 和 kramdown 沿用它，各自在细节上有些不同。术语单独占一行，每条解释从下一行开始，以冒号起头：

```markdown
Apple
:   Pomaceous fruit of plants of the genus Malus.
:   An American computer company.

Pear
:   A fruit that is not an apple.
```

下面这些规则都来自各处理器自己的文档。

- **多条解释。** 每多一条解释就多一行冒号，如上面的 Apple。PHP Markdown Extra 里几个术语还可以共用一条解释，连着写几行术语，再接冒号行。
- **空行。** Markdown Extra 要求术语和上一条解释之间隔一个空行。术语和解释之间有没有空行会改变输出，Markdown Extra 会把前面有空行的解释包进 `<p>`，Pandoc 的说法是这条解释会被当成一个段落。在 Pandoc 里，`Pear`、空行、`: Also fruit.` 得到 `<dd><p>Also fruit.</p></dd>`，不留空行时得到的是不带 `<p>` 的 `<dd>`。
- **冒号的位置。** 冒号在左边缘或者缩进几格。Markdown Extra 最多缩进三格，冒号后要有空格或制表符；Pandoc 认冒号或波浪线，缩进一到两格；kramdown 最多三格，后面至少一个空格或制表符。
- **较长的解释。** 后续的块要缩进到和冒号后的文字对齐。Markdown Extra 和 Pandoc 都允许一条解释里放多个段落、代码块和列表。段落折行时下一行不缩进两边也都认，Pandoc 管这叫懒式续行，kramdown 也认，但文档建议不要依赖。
- **术语只占一行。** Pandoc 说每个术语必须在一行内写完，kramdown 里前一个段落的每一行都是一个单独的术语。

## 冒号写法在哪里能渲染

处理器开着这个功能才行。

- **Pandoc** 自己的 Markdown 里叫 `definition_lists` 扩展，默认开启，用 `-f gfm` 或 `-f commonmark` 时是关的，上面的输出就是这样。
- **kramdown** 在它的语法参考里有专门的定义列表一节。
- **Python-Markdown** 自带 `def_list` 扩展，用 `markdown.markdown(text, extensions=['def_list'])` 开启。MkDocs 基于 Python-Markdown，默认只启用 `meta`、`toc`、`tables` 和 `fenced_code`，所以 MkDocs 站点要在 `mkdocs.yml` 的 `markdown_extensions` 下自己加上 `def_list`。
- **markdown-it** 需要单独的 `markdown-it-deflist` 插件，用 `.use(require('markdown-it-deflist'))` 加载，它的 README 说语法和 Pandoc 在 `commonmark_x` 下的定义列表基本兼容。

GitHub 的基本写作和格式语法那一页没有提定义列表，所以不要指望 README 里冒号写法能用，依赖它之前先拿一篇临时笔记试一下。

## HTML 兜底写法

HTML 是最通用的路。只要允许原始 HTML，Markdown 处理器就会把 `<dl>` 原样放过去：

```markdown
<dl>
  <dt>Apple</dt>
  <dd>A fruit.</dd>
  <dt>Pear</dt>
  <dd>Another fruit.</dd>
</dl>
```

麻烦在 CommonMark 怎么对待 HTML 里面的 Markdown。以 `<dl>`、`<dt>`、`<dd>` 这类块级标签开头的行会开启一个 HTML 块，一直到下一个空行才结束，规范说这种块里的内容原样输出。所以下面这段不会格式化：

```markdown
<dl>
<dt>Pear</dt>
<dd>**not parsed**</dd>
</dl>
```

星号会原样留着。规范自己的 `<div>` 例子给了出路，把里面的内容单独放几行，和标签之间隔开空行，它就会重新按 Markdown 解析：

```markdown
<dl>
<dt>Apple</dt>
<dd>

*Fruit* with `code`

- a list

</dd>
</dl>
```

用 Pandoc 的 `-f gfm` 跑，`<dd>` 里得到的是强调、行内代码和真正的列表，而同一行写的 `<dd>**not parsed**</dd>` 仍然是字面文字。里面的内容不要缩进四个空格，否则会变成代码块。

这比冒号写法费事，适合结构本身有用的场合，比如别的工具或样式表要读取的术语表。

## 妙言里是什么情况

妙言的预览用 cmark-gfm 解析 Markdown，创建解析器时带了脚注选项，再按名字挂上四个扩展，`table`、`footnotes`、`strikethrough` 和 `tasklist`，里面没有定义列表扩展，cmark-gfm 核心也不带，所以术语行加一行 `: A fruit.` 仍是同一个段落。换行设置用默认的「每次换行」时，每个换行都会变成 `<br>`，冒号那行看起来还是单独一行，换成「GitHub 风格」两行就会用空格连在一起。渲染时传了允许原始 HTML 的选项，`<dl>` 会照写的样子渲染，上面的空行写法在 `<dd>` 里也能得到强调、行内代码和列表，而同一行写的 `<dd>**not parsed**</dd>` 仍是字面文字。

所以在妙言里想要真正的术语表就写 HTML，从 Pandoc 笔记带过来的冒号写法会显示成文字。用妙言导出 HTML 时 `<dl>` 会跟着带出去，导出的细节见 [Markdown 转 HTML](/zh/blog/markdown-to-html/)。

## 哪里都能用的替代写法

笔记要在好几个地方都读得顺，就别靠扩展，用普通 Markdown。

**加粗术语，下面跟一段。** 最简单，也最通用：

```markdown
**Apple**
A fruit.

**Pear**
Another fruit.
```

想让术语独占一行，就用反斜杠或行尾两个空格显式换行，见 [Markdown 换行](/zh/blog/markdown-line-breaks/)。加粗本身的写法在 [加粗、斜体和删除线](/zh/blog/markdown-bold-italic-strikethrough/)。

**两列表格。** 适合参数、配置项这类简短而整齐的条目：

```markdown
| 参数 | 含义     |
| ---- | -------- |
| `-s` | 独立文档 |
| `-o` | 输出文件 |
```

表格一个单元格只能一行，也放不了列表，所以只适合短解释，规则见 [Markdown 表格](/zh/blog/markdown-tables/)。解释很长、带段落和列表时，一个术语配一个小标题往往比任何列表都清楚。

## 常见问题

### GitHub 支持 Markdown 定义列表吗？

GFM 规范没有定义这种语法，GitHub 的格式化文档也没提，所以用替代写法或 HTML，并且在最终阅读的地方检查结果。

### 冒号写法是 Pandoc 独有的吗？

不是。它出自 PHP Markdown Extra，kramdown、Python-Markdown 和 markdown-it-deflist 也能读，各自有一点细节差别。

### MkDocs 怎么写定义列表？

在 `mkdocs.yml` 的 `markdown_extensions` 里加上 `def_list`，然后写术语加 `: 定义` 的形式。

### 为什么 dd 里的加粗没生效？

以 `<dd>` 开头的行属于 HTML 块，CommonMark 会原样输出不解析，把内容单独放几行，前后各留空行就行。
