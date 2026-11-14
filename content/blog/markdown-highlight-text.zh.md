Markdown 里没有高亮语法，CommonMark 和 GitHub Flavored Markdown 都没定义，能通用的写法是 HTML 标签 `<mark>文字</mark>`，GitHub、妙言和很多渲染器都会保留它。更短的 `==文字==` 只在开启了对应扩展的地方有效，比如 Obsidian、Pandoc，或者装了插件的 markdown-it，换到不认识它的渲染器里，等号会原样显示出来。写之前先想好笔记最后在哪里读，只是想强调的话，直接用粗体就行。

## 为啥 `==文字==` 不是标准语法

CommonMark 有强调、加粗和行内代码，GFM 在它上面加了删除线、表格、任务列表和自动链接，高亮两边都没有。[CommonMark 和 GFM 的区别](/zh/blog/commonmark-vs-gfm/)那篇列了各自多出来的东西，其余都是工具自己的扩展，`==` 是其中最常见的一个，它在纯文本里读着顺眼所以流行，但不认识它的解析器会把字符原样放过去。

GitHub 的格式说明里列了标题、粗体、斜体、删除线、引用、代码等等，没有高亮这一项，README 里写 `==重点==`，在 github.com 上看到的就是带等号的原文。

## 哪些地方认 `==文字==`

| 工具 | 情况 | 依据 |
| --- | --- | --- |
| Obsidian | 内置，`==Highlighted text==` | Obsidian Help 的基本格式语法页 |
| Pandoc | `mark` 扩展，需要自己打开 | Pandoc 用户手册，`mark` 扩展 |
| markdown-it | 插件 `markdown-it-mark` | 插件 README |
| GitHub | 不支持 | GitHub Docs 的基本写作和格式语法页 |
| 妙言 | 不支持，保持原样 | 见下文 |

Obsidian 的帮助页把高亮和粗体、删除线放在同一张格式表里，还提到高亮支持六种颜色，在开头的 `==` 后面紧跟一个彩色 emoji 就行，比如 `==🔴Important==`，不加 emoji 就用主题默认的高亮色。这个选色办法是 Obsidian 自己的，换到别的 App 里没有任何意义。

Pandoc 手册对 `mark` 扩展只用了一句话，想高亮一段文字，就用 `==` 开头和结尾。手册把它放在非默认扩展里，所以要自己写出来，比如 `pandoc -f markdown+mark`。`markdown-it-mark` 的 README 写的是 `==marked==` 会变成 `<mark>inserted</mark>`，规则和 CommonMark 的强调一样，实际意思是定界符要贴着文字，`== 带空格 ==` 不会高亮，原因和 `** 带空格 **` 不能加粗一样，这套规则在[粗体、斜体和删除线](/zh/blog/markdown-bold-italic-strikethrough/)里讲过。

这三个扩展最后产出的都是 HTML 的 `<mark>` 元素，短写法只是标签的快捷方式，所以先学标签更划算。

## 能通用的写法：`<mark>`

```markdown
改名之前记得先<mark>备份文件夹</mark>。
```

`<mark>` 是标准的 HTML 元素，表示因为和上下文相关而被标出或高亮的文字，和荧光笔的用途一致。它是行内元素，放在句子、列表项或表格单元格里都行，前后不用空行。

麻烦在会去掉 HTML 的渲染器，能留下什么取决于渲染器。把一段样例发给 GitHub 的 Markdown API，结果是这样的：

- `<mark>` 保留，GitHub 上能看到高亮。
- `<mark style="background:red">` 标签保留，`style` 属性被去掉，想要的颜色就没了。GitHub 的 markup 库在 README 里写明，GitHub 会清理渲染出的 HTML，去掉内联样式以及 `class` 和 `id` 属性。
- `<span style="background:yellow">` 文字保留，标签和颜色都没了。
- `==hi==` 保持原文。

在清理更严格的网站或 App 里，标签可能整个消失只剩文字，这算是还能接受的失败，句子依然通顺，只是少了强调。如果高亮必须在哪里都看得见，就在文字本身再加一个线索，比如粗体。

## 用 CSS 改高亮颜色

高亮是什么颜色是 CSS 的事，Markdown 管不到。渲染器保留内联样式的话，可以自己指定背景：

```markdown
<mark style="background: #cdeccd; color: inherit">已完成</mark>
```

像 GitHub 那样会去掉样式的地方，只能用默认颜色。如果页面样式表在你手里，比如导出的 HTML 文件，可以给 `mark` 写一次规则，不用每处都加内联样式：

```css
mark {
  background: #cdeccd;
  color: inherit;
}
```

浅色背景配浅色文字会看不清，所以页面有深色主题时，文字颜色要和背景一起设。彩色文字和下划线是这个问题的另一半，放在 [Markdown 里的下划线和颜色](/zh/blog/markdown-underline-and-color/)那篇。

## 妙言怎么处理高亮

妙言用 cmark-gfm 转换 Markdown，并且让它保留原始 HTML。解析器开了表格、脚注、删除线和任务列表四个扩展，没有一个处理 `==`，所以预览里 `==文字==` 按原样显示，`<mark>文字</mark>` 则由网页视图画成高亮。

预览自己给 `<mark>` 配了样式。浅色主题是黄色背景（`rgba(255, 247, 0, 0.88)`），带一两个像素的内边距，文字沿用周围颜色，深色主题是深橄榄色背景（`rgba(77, 74, 0, 0.88)`），浅色文字依然看得清。导出 PDF 时一律用浅黄色加打印用的墨色，否则深橄榄色会变成深底深字。标签上的内联 `style` 不会被去掉，内联样式又优先于样式表，所以在预览里给 `<mark>` 写 `style="background: ..."` 会盖过主题颜色，只是以后换到更严格的网站时不会跟过去。导出的步骤在 [Mac 上 Markdown 转 PDF](/zh/blog/markdown-to-pdf-mac/)里。

从 Obsidian 搬过来的笔记，里面的 `==文字==` 在妙言里会显示成带等号的原文，需要手动或者查找替换改成 `<mark>` 标签。

## 不用高亮的替代办法

很多时候最好的做法就是不高亮。

- **粗体**最通用，纯文本里也成立，复制粘贴也不会丢。
- **行内代码**比如 `` `先备份` `` 在多数渲染器里是一个灰底框，它本来是给代码用的，适合命令、文件名和按键，不要当成通用高亮。
- **引用块**把一段话作为整块隔开，提示块（callout）还带标签，`> [!NOTE]` 加另外四种类型，在 GitHub 和妙言里是彩色方框，在别处就是一段开头带 `[!NOTE]` 的普通引用，规则见[引用块和嵌套列表](/zh/blog/markdown-blockquotes-and-nested-lists/)。
- **删除线**是给要删掉的文字用的，GFM 里写 `~~旧的~~`。

## 给代码块里的行加高亮

围栏代码块里面 Markdown 不解析，所以这是另一个问题。最常见的场景是展示改动，用 `diff` 语言：

````markdown
```diff
- timeout: 30
+ timeout: 60
```
````

以 `-` 开头的行画成删除，以 `+` 开头的行画成新增。这是语法高亮器的约定，不是 Markdown 的功能，只要高亮器带 diff 定义就能用。GitHub 用自己的 diff 配色渲染，妙言自带的 highlight.js 注册了 Diff，给这些行用它的 `addition` 和 `deletion` 词法颜色，是文字颜色，没有背景色带。围栏语言名的更多写法在[Markdown 代码块](/zh/blog/markdown-code-blocks/)里。

## 常见问题

### Markdown 里高亮文字的语法是什么？

CommonMark 和 GFM 都没有定义，用 `<mark>文字</mark>`，或者工具支持时用 `==文字==`，比如 Obsidian。

### 为啥我看到的是 ==文字== 而不是高亮？

渲染器没有 mark 扩展，把等号换成 `<mark>` 标签，或者在有扩展的工具里打开它，Pandoc 就是 `+mark`。

### GitHub 支持 Markdown 高亮吗？

`==` 不支持。`<mark>` 标签会保留，用 `style` 属性设的颜色会被去掉。

### 能换一种颜色高亮吗？

只能靠 CSS，内联 `style` 或样式表都行，前提是渲染器保留它。Obsidian 在 `==` 后面加彩色 emoji 的办法只在它自己里面有效。
