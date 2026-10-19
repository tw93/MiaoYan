Markdown 转 HTML 分两步，解析器先读懂 Markdown 并建出文档树，渲染器再把这棵树写成 HTML 标签。临时转一个页面，命令行里用 Pandoc（`pandoc -s note.md -o note.html`）就能得到一份完整的、放哪儿都能用的文件；在妙言 V4.5.0 里，文件 > 导出 > HTML 在应用里做同样的事，只有一个限制要先知道，导出的文件从妙言的 CDN 加载样式和脚本，并且不带本地图片。

## 片段还是完整页面

解析器默认给的是片段，一堆 `<h1>`、`<p>`、`<ul>`，没有 `<html>` 和 `<body>`，要把 HTML 放进模板、CMS 或邮件时，要的就是它。完整页面则需要在片段外面包一层带字符集、标题和样式表链接的 head。

Pandoc 的手册写得很明确，默认只生成文档片段，加 `-s` 或 `--standalone` 才生成带 `<head>` 和 `<body>` 的完整文档，`--css` 要和 `-s` 一起用，因为样式表的链接是写进文档头部的。

## 命令行的几条路

```bash
# Pandoc：完整页面，链接外部样式表
pandoc -s note.md -o note.html --css style.css

# Pandoc：样式和图片都内联成一个文件
pandoc -s note.md -o note.html --embed-resources

# markdown-it：输出片段到文件
npm install markdown-it
npx markdown-it note.md -o note.html
```

Pandoc 的 `--embed-resources` 生成没有任何外部依赖的独立 HTML 文件，只对 HTML 输出有效，旧的 `--self-contained` 是 `--embed-resources --standalone` 的弃用同义词。Pandoc 自己的 Markdown 已经能读管道表格、任务列表和删除线，加 `-f gfm`（手册里描述为 GitHub-Flavored Markdown）则按 GitHub 的规则读，还会打开 `> [!NOTE]` 这类提示块。Pandoc 的数学公式默认用 MathML，`--math-method=katex` 可以切到 KaTeX。

markdown-it 的命令行读文件，不给文件时读标准输入，不加 `-o` 就写到标准输出，参数里有关闭内嵌 HTML 的 `--no-html`、自动识别链接的 `-l` 和排版替换的 `-t`。它的 README 把「Safe by default」列在特性里，库的默认选项也确实是 `html: false`，但命令行不加 `--no-html` 就会打开内嵌 HTML，转不是自己写的文本时记得加上这个参数。

cmark-gfm 是妙言用的 C 解析器，它的 README 说库默认会清除原始 HTML 和有风险的链接，命令行加 `--unsafe` 才放行。它负责把 Markdown 渲染成 HTML，页面的 head、样式表和脚本要你自己加。

## 它到底是怎么转的

Markdown 是文本格式，所有工具走的是同一条流水线，块解析器判断每一行是段落、标题、列表还是代码围栏，行内解析器处理其中的强调、链接和代码片段，结果是一棵树，渲染器遍历这棵树再打印标签。CommonMark 规定了核心语法对应的 HTML，GFM 在上面加了表格和任务列表，所以两个启用了不同扩展的工具，对同一个文件可能输出不同的 HTML，这就是同一张表在一个工具里是表格、在另一个里是一堆竖线的原因。

「转换好的页面」里其他东西都是渲染之后才加的，head、样式表，以及画公式和图表的脚本。转换器替不替你加，才是工具之间真正的差别。CommonMark 和 GFM 各规定了什么，见 [CommonMark 与 GFM 的区别](/zh/blog/commonmark-vs-gfm/)。

## 妙言的 HTML 导出

在妙言 V4.5.0 里选中一篇笔记，点文件 > 导出 > HTML，或者在妙言窗口里按 `Control + Shift + H`，不需要先打开预览。文件以 `标题.html` 写进下载目录，标题里的 `/` 换成 `_`，重名时在后面加时间戳，下载目录写不进去时会弹出保存面板，提示是「已导出到下载目录~」。

文件里有什么：

- 正文是 cmark-gfm 的输出，原始 HTML 放行，所以你写的标签会保留，笔记开头的 front matter 会先被去掉。
- 妙言会在顶部补一个笔记标题的 `<h1>`，本来笔记以 `#` 标题开头时应该跳过，但 V4.5.0 里这个判断从来不成立，所以你自己的标题上面也会再加一行，两者相同时标题就出现两次，介意的话在导出的文件里删掉一个。
- 页面用的是预览的模板，字体取你设置的预览字体，正文宽度限制在 760 像素，颜色按当前主题的浅色或深色。
- 它不内联任何东西。一个 `<base>` 标签指向 `https://cdn.miaoyan.app/Resources/DownView.bundle/`，模板里排版、KaTeX、highlight.js、Mermaid 和 Markmap 的样式与脚本都从那里加载，离线打开时，写在页面里的背景色、文字颜色和正文宽度还在，排版样式表加载不到，公式和图表也画不出来。

最容易让人意外的是图片。HTML 导出渲染 Markdown 时没有走预览和 PDF 导出用来查找本地图片的那一步，而 `<base>` 标签又让所有相对路径都按 CDN 地址解析，`/i/photo.png` 变成 `https://cdn.miaoyan.app/i/photo.png`，`images/fig.png` 变成那边 `DownView.bundle/` 下的路径，都不存在，把图片拷到 HTML 旁边也没用，`https://` 开头的远程图片可以正常加载。要分享的文件，要么笔记里用远程图片地址，要么导出 PDF，见 [Mac 上把 Markdown 导出 PDF](/zh/blog/markdown-to-pdf-mac/)，图片路径的细节见 [Markdown 图片](/zh/blog/markdown-images/)。

## 放到网上

不需要服务器的文件可以放到任何静态托管上。比如 GitHub Pages，会把仓库里的 HTML、CSS 和 JavaScript 文件发布成网站，入口文件找的是 `index.html`，要放在发布目录的最顶层。把转换好的页面命名为 `index.html`，图片放在旁边，Markdown 里用相对路径，搬过去之后路径仍然成立。

用 Pandoc 的 `--embed-resources` 得到的是一个文件，发邮件或上传都不会漏东西；用妙言导出的要记得 CDN 这层依赖，页面放到你的站点上，样式仍然来自 `cdn.miaoyan.app`。

## 原始 HTML 与安全

Markdown 允许内嵌 HTML，放行 HTML 的转换器也会放行 `<script>` 标签。Pandoc 手册对它的 Markdown 读取器写明了后果，启用 `raw_html` 时用户可以注入任意 HTML，建议把所有来自不可信输入的 HTML 都过一遍 HTML 净化器。可以用 `-f markdown-raw_html` 关掉这个扩展，但同一节也提醒，链接和属性里照样能放危险内容，对用户提交的文本还是要过净化器。

DOMPurify 自称是只依赖 DOM 的 HTML、MathML 和 SVG 的 XSS 净化器，用法是 `DOMPurify.sanitize(dirty)`，在服务器上运行需要 jsdom 这类 DOM 实现。转自己的笔记时这些都不要紧，Markdown 来自别人时才要紧，因为妙言的预览和导出都保留原始 HTML。

## 常见问题的排查

- **页面没有样式。** Pandoc 的页面不加 `--css` 就没有你自己的样式表，妙言导出的文件离线打开则加载不到它的样式。
- **图片是坏的。** 妙言导出里的本地路径会按妙言的 CDN 地址解析，改用远程地址，或者在 Pandoc 里用 `--embed-resources`。
- **表格显示成竖线。** 用的是没有表格扩展的纯 CommonMark 解析器，Pandoc 和 markdown-it 默认就能读管道表格，cmark-gfm 要挂上表格扩展才行。
- **公式显示成原始的美元符号。** 页面没有公式渲染器，妙言导出的页面需要 CDN 能访问。
- **托管后 404。** 入口文件不叫 `index.html`，或者不在发布目录的顶层。

## 常见问题

### 一定要托管吗？

不需要，用浏览器从磁盘直接打开就行，只是妙言导出的文件要联网才能加载样式和脚本。

### 哪个工具输出的 HTML 最干净？

cmark-gfm 和 markdown-it 给的是朴素的片段，Pandoc 加 `-s` 给完整页面，输出取决于你启用了哪些扩展。

### 妙言能整个文件夹一起转吗？

导出菜单只作用于选中的那一篇笔记。
