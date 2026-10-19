选中笔记，从菜单栏打开「文件」，再点「导出」，在弹出的菜单里选「PDF」，妙言会把当前预览印成固定的 A4，按笔记标题存到下载目录。纸张、边距、页眉和深色页面都没有开关，字体跟着设置里的预览字体走，分页可以用原始 HTML 写进笔记。要 Letter 或者别的边距，就用 Pandoc、Typora，或者走别的应用的打印对话框。

## 从笔记导出

点菜单栏的「文件」，再点「导出」，弹出的是笔记菜单里的导出子菜单，四项是「HTML」、「图片」、「PDF」和「妙言 PPT PDF」。在笔记列表上点右键，导出下面也是这四项，没有选中笔记时这次操作不会写文件。

焦点在笔记列表上，而且没有开着幻灯片模式时，`Control + Shift + P` 导出 PDF，`Control + Shift + I` 导出图片，`Option + Control + Shift + P` 导出妙言 PPT PDF。幻灯片模式开着的时候这几个键会被忽略。

PDF 和图片如果当时没开预览，会先打开预览，等一秒再导出，这次导出打开的预览，结束时再关掉。提示先显示带百分比的「正在导出」，成功是「已导出到下载目录~」，失败是「导出失败」。文件名用笔记标题，标题里的 `/` 换成 `_`，再加 `.pdf`，标题如果还是一串 UUID，会变成「无标题」。下载目录里已有同名文件时，后面补 `_yyyy-MM-dd_HH-mm-ss`，写不进去就弹出存储面板。用预览打开这份 PDF，核对插入的标题、页脚的 `1 / N`，以及 h1 到 h3 的大纲，同一菜单里的图片写出的是同一份预览的 PNG。

## PDF 里有什么

公式用随应用打包的 KaTeX，定界符是 `$...$`、`$$...$$`、`\(...\)` 和 `\[...\]`，这个引擎接受哪些写法，见 [Markdown 里写 LaTeX 公式](/zh/blog/latex-math-in-markdown/)。

围栏代码用 highlight.js 11.5.1 上色，打印样式给 `pre` 设了 `white-space: pre-wrap`，长行会折回来。又给 `pre`、表格、`figure`、引用、Mermaid 块和图表面板设了 `page-break-inside: avoid`，标题则是 `page-break-after: avoid`。

Mermaid 和 Markmap 跑的是应用里自带的脚本，打印前会等到 Mermaid 块带上 `data-processed`，Markmap 块带上 `data-markmap-rendered`，图片宽度也不再是 0。一共等 80 次，每次 120 毫秒，源码注释里写成 9.6 秒，到点就照样写出 PDF。Mermaid 渲染失败时留下源代码，错误文字不会写进页面。

PlantUML 向 `https://www.plantuml.com/plantuml/svg/` 要图，所以需要网络，图的原文也会离开这台 Mac。三种图怎么区分，写在 [Markdown 里画 Mermaid 图](/zh/blog/mermaid-diagrams-in-markdown/)。

相对路径的图片按笔记所在的项目文件夹查找，`/i/photo.png` 会去掉开头的斜杠，变成这个文件夹里的 `i/photo.png`。写成完整路径而且文件存在就用那个路径，本地文件找不到就换成标着 `Image Not Found` 的小方块。第一张之后的图片是懒加载，占位图加上 `data-src`，打印用的页面不会滚动，导出时把 `data-src` 抄回 `src`。表格被拉成页宽，屏幕上的目录会藏起来，链接去掉下划线。

纸张是 A4，595.2 乘 841.8 点，边距上 40 点、下 48 点、左右各 45 点，打印设置旁的注释写成上 14 毫米、下 17 毫米、左右 16 毫米。打印面板不出现，过宽的内容缩到页宽以内，预览是深色时纸面仍然是白的。文字用设置里的预览字体，中文由后面的 PingFang SC 和 Hiragino Sans GB 接上。

h1 到 h3 写成 PDF 大纲，每条书签落在哪一页，按标题在不分页的整篇文档里的高度估算，图片或者被要求整块保留的内容会让它偏一页。页脚是 8.5 磅的灰色字，内容是 `1 / N`，PDF 标题用导出标题，creator 字段写成 MiaoYan。

## 幻灯片是另一份 PDF

笔记文本里出现 `---` 时，导出菜单里的妙言 PPT PDF 会写出 `标题_PPT.pdf`，没有这三个字符就提示「没有分隔符 --- 标识，无法使用妙言 PPT~」。这个判断是子串搜索，表格行 `|---|` 也能通过。一行 `---` 怎样变成一页，见 [Markdown 转幻灯片](/zh/blog/markdown-to-slides/)。

`Command + Option + P` 用来开关妙言 PPT。选妙言 PPT PDF 时如果幻灯片模式没开，会先打开它，窗口当时不是全屏幕就进入全屏幕，等 1.2 秒，按 reveal.js 的打印布局抓取，并把 `pdfMaxPagesPerSlide` 设成 1，若是这次导出打开的模式，抓完再关掉。

这份文件来自网页视图的 PDF 快照，不走文章导出那套 A4 边距，也不画 `1 / N` 页脚。幻灯片模式已经开着时再选 PDF，拿到的也是幻灯片的网页快照，文件名是 `标题.pdf`，同样没有页脚。

## 这一页是怎么排出来的

妙言用 cmark-gfm 把笔记渲染成 HTML，原始 HTML 会保留下来，然后网页视图跑 KaTeX、highlight.js 和图表脚本。导出把这份文档复制进一个隐藏的网页视图，注入只在打印时生效的样式，等图片和图表就绪，再用 `NSPrintOperation` 存盘，打印面板保持关闭。分页由 WebKit 决定，大纲和页脚由 PDFKit 在打印之后补上，PDF 就是预览被打印出来的结果。

Pandoc 默认把 Markdown 转成 LaTeX，再运行 `pdflatex`，所以 TeX 得在 `PATH` 里。`--pdf-engine` 用来指定程序，手册列出的值里有 `pdflatex`、`xelatex`、`lualatex`、`weasyprint` 和 `wkhtmltopdf`。不写 `-t` 时引擎是 `pdflatex`，`-t html` 时默认是 `weasyprint`，`wkhtmltopdf` 是其余 HTML 引擎里的一个。同一本手册写着 `wkhtmltopdf` 已经废弃，不要拿它处理不可信的输入。

LaTeX 这条路上，纸张、边距和字体是模板变量，缺包会停在 TeX 日志里，HTML 引擎则是把排好的页面打印出来，改外观用 `--css`。要看中间文件，输出改成 `-s -o test.tex`，再运行 `pdflatex test.tex`。

## Pandoc、Typora、VS Code 和系统打印

在放着笔记和图片的文件夹里运行下面这条命令。

```bash
pandoc note.md -o note.pdf --pdf-engine=xelatex -V CJKmainfont="PingFang SC"
```

不写 `--resource-path` 时，Pandoc 在工作目录里找图片，而且只在它确实需要这个文件时才找，生成 PDF 就属于这种情况。改走 HTML 引擎时用下面这条。

```bash
pandoc note.md -o note.pdf --pdf-engine=weasyprint
```

行内 TeX 会交给 LaTeX 写入器，所以 `\newpage` 能在这条路上分页，WeasyPrint 收不到这条命令。YAML 里的 `papersize` 可以写 `a4` 或 `letter`，`geometry` 可以写手册示例里的 `top=30mm` 和 `left=20mm`。设置了 `CJKmainfont` 之后，`xelatex` 需要 `xeCJK`，`xelatex` 或 `lualatex` 需要 `fontspec`，PingFang SC 就是妙言打印字体栈里已经写上的中文字体。

Typora 支持页上的导出入口是 File > Export > PDF，也能导出 HTML 和图片。偏好设置里 Export 下面的 PDF，可以改纸张，包括 A4、A5 或自定义尺寸，以及边距、导出主题、一级标题之间的分页、页眉和页脚，页脚示例是 `No. ${pageNo} / ${pageCount}`，Windows 和 Linux 上这条 PDF 只支持浅色主题。PDF (LaTeX / Pandoc) 要自己加进导出列表才会出现，并且要装好 Pandoc，`PATH` 上还要有一个引擎，或者填上引擎的完整路径。编辑器之间怎么选，见 [Mac 上的 Typora 替代品](/zh/blog/typora-alternative-mac/)。

VS Code 里，yzane 的 Markdown PDF 扩展把 `markdown-pdf: Export (pdf)` 放在编辑器的右键菜单里，用 F1 打开的命令面板里也有这一项。打印经过本机的 Chrome、Edge、Chromium，或者扩展自己下载的 Chromium。公式用 KaTeX，不需要网络，Mermaid 围栏也包含在导出里，不过 Mermaid 脚本默认从 CDN 加载（`markdown-pdf.mermaidServer`），`markdown-pdf.displayHeaderFooter` 的默认值是 true。

妙言没有「打印」命令，这条路要在另一个能打开笔记的应用里走。Apple 的 Mac 使用手册把能打印的文稿从文件菜单选打印，再打开 PDF 弹出式菜单，选取保存为 PDF，纸张大小也在同一个打印对话框里定。妙言导出的 HTML 不适合拿到浏览器里打印，文件的 base URL 是 `https://cdn.miaoyan.app/Resources/DownView.bundle/`，本地图片也不会像预览那样改成 `file://`，`images/fig.png` 不会出现在下载目录那份 HTML 旁边。

## 对不上的时候

页面上还留着美元符号时，多半是公式还在代码里，KaTeX 会跳过代码，或者预览还没排完，公式排在空闲回调上，超时是 200 毫秒。等预览里公式已经画出来再导一次，`$5` 会被当成价钱留下原文，`$2+2$` 才是公式。

出现 `Image Not Found` 方块，或者一块空白，查找位置是项目文件夹，不是下载目录，`/i/photo.png` 就是该文件夹下的 `i/photo.png`。远程图片和 PlantUML 都要网络，等待一结束 PDF 就保存，缺掉的那一块会留在页面上。

代码块从中间被切开时，样式已经要求 `pre` 整块留下，并且把长行折回来，纸张仍是那张固定的 A4，边距也改不了，可以把围栏写短一些，或者改用 Pandoc 的 `geometry`。原始 HTML 会进入预览，写上 `style="page-break-before: always"` 就是笔记里能放的分页，导出命令自己没有分页开关。

Pandoc 的 PDF 里中文不见了，默认引擎是 `pdflatex`，换成上面的 `xelatex` 并设置 `CJKmainfont`。妙言自己的 PDF 字体栈里已经有 PingFang SC，这条导出不依赖 TeX。

书签偏了一页时，以页脚为准，页脚是真实页码，大纲用的是标题在不分页文档里的高度，图片或者 `page-break-inside: avoid` 让分页不均匀时，估算就会偏。

只弹出分隔符那句提示，说明笔记里没有 `---`，妙言 PPT PDF 就停在这一步。幻灯片模式开着时按笔记列表上的快捷键则什么都不会发生，那些键在这个模式里被忽略，改用菜单里的导出。

预览是深色、PDF 是白页，因为打印样式把背景设成 `#ffffff`，文章导出没有深色页面。

提示「导出失败」而且没有文件，通常是抓到的页面不超过 50 个字符、隐藏页面没能加载，或者打印出来几乎是空的，等预览画完再导一次。下载目录写不进去时不会报失败，而是弹出存储面板让你选位置。

## 常见问题

### 这份 PDF 能改成 Letter 吗

妙言没有纸张选项，把 Pandoc 的 `papersize` 设成 `letter`，或用 Typora 的纸张大小，或在能打印这篇笔记的应用里选文件菜单的打印，在保存为 PDF 之前把尺寸定好。

### 妙言导出 PDF 要安装 TeX 吗

妙言导出 PDF 不需要另装 TeX，它的 PDF 是 WebKit 把预览打印出来，TeX 用在 Pandoc 默认的 LaTeX 路径上，Typora 也要等你加上 PDF (LaTeX / Pandoc) 之后才会用到。

### 为什么选了 PDF 却得到幻灯片

幻灯片模式开着时，PDF 走 reveal.js 的快照，先退出这个模式再导出。妙言 PPT PDF 的文件名是 `标题_PPT.pdf`，幻灯片模式下选 PDF 得到的仍叫 `标题.pdf`。

### 书签打开的页不对，页脚也错了吗

页脚是当前页码和总页数，书签的页按标题在不分页文档里的高度估算，可能偏一页。
