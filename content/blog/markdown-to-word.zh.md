把 Markdown 转成 Word，最稳的办法是 Pandoc，`pandoc note.md -o note.docx` 会把标题、列表、表格、代码和公式转成真正的 Word 结构，再用 `--reference-doc` 指定字体和样式。妙言 V4.5.0 不直接写 `.docx`，它的导出是 HTML、图片和 PDF，所以在妙言里要么导出 Word 能读或能粘贴的东西，要么对同一个笔记文件跑 Pandoc。图表、提示块和双链，两条路都需要手动处理一步。

## Pandoc 这条路

```bash
pandoc note.md -o note.docx
```

在笔记所在的文件夹里运行，这样笔记引用的图片才找得到。Pandoc 手册说 `--resource-path` 默认是工作目录，只在 Pandoc 自己要找图片时才起作用，写 docx 就属于这种情况。图片在别处时用 `--resource-path` 列出文件夹，并且自己把 `.` 也写上，因为一旦设置了这个选项，工作目录除非列出来，否则不再被搜索。

粘贴进妙言的图片在笔记里写成 `/i/name.png`，前面带斜杠，Pandoc 会把它当成从磁盘根目录算起的路径，于是提示 `Could not fetch resource`，用图片的描述文字顶替图片。在笔记所在文件夹里转换时把这个斜杠去掉就行：

```bash
sed 's#](/i/#](i/#g' note.md | pandoc -f gfm -o note.docx
```

Pandoc 自己的 Markdown 已经能读管道表格、任务列表和删除线，按 GFM 读则是照 GitHub 的规则来，还会打开处理 `> [!NOTE]` 提示块的 `alerts` 扩展：

```bash
pandoc -f gfm note.md -o note.docx
```

手册把 `gfm` 描述为 GitHub-Flavored Markdown，不加的话 Pandoc 按它自己的 Markdown 方言读，和 GFM 大部分重叠，但并不完全一样。`$...$` 公式两种读法都行，`tex_math_dollars` 扩展把两个美元符号之间的内容当作 TeX 公式，两种格式里它都是开着的。运行 `pandoc --list-extensions=gfm` 可以看到这个格式有哪些扩展，前面是 `+` 的表示默认开着。

## 格式从哪里来

Pandoc 不是从零画一份 Word 文档，而是把你的内容填进一份参考文档，外观来自这份文档的样式。手册列出了这些样式，段落样式有 Normal、Body Text、First Paragraph、Compact、Title、Author、Date、Heading 1 到 Heading 9、Source Code 和 Footnote Text，字符样式有 Verbatim Char 和 Hyperlink，表格样式只有一个叫 Table。

[[figure:markdown-to-word|从 Markdown 笔记到 Word 的两条路，Pandoc 配参考文档直接写出 .docx，妙言的 HTML 导出要在浏览器里打开再粘贴进 Word，PDF 导出则是固定的页面。|Pandoc 直接写出 .docx，样式取自参考文档，妙言的 HTML 导出只能粘贴进 Word，PDF 导出则是固定的页面。]]

所以格式不在 Markdown 里，`##` 变成 Heading 2 段落，代码围栏变成 Source Code，它们长什么样由参考文档决定。公式也不会被丢掉，手册写明 docx 输出里的 TeX 公式会写成 OMML，也就是 Word 自己的公式格式，到了 Word 里是可以直接编辑的公式。

## 设置字体，尤其是中文

先取出默认的参考文档，在 Word 里改好，再传回去：

```bash
pandoc -o custom-reference.docx --print-default-data-file reference.docx
pandoc note.md -o note.docx --reference-doc=custom-reference.docx
```

用 Word 或 LibreOffice 打开 `custom-reference.docx`，改的是样式而不是示例文字，正文改 Normal 和 Body Text，标题改各级 Heading，代码改 Source Code。中文文档要把这些样式里的中文（东亚）字体也设上，不只设西文字体，因为一个样式可以给西文字符和中文字符分别指定字体，只改西文的话，中文还是样式原来的字体，和西文放在一起可能不协调。Pandoc 默认参考文档里，Body Text 基于 Normal，First Paragraph（标题下面第一段用的样式）和 Compact（紧凑列表项用的样式）又都基于 Body Text，所以字体设在 Normal 上，这几种段落都会跟着变，各级 Heading 和 Title 用的是主题里的标题字体（`styles.xml` 里的 `majorHAnsi` 和 `majorEastAsia`），要单独去改。同一份参考文件对每篇笔记都适用，只需要做一次。

默认的 `reference.docx` 也带着页面大小和页边距，转出来纸张不对，就在参考文档里改一次。

## 走妙言的导出

妙言的文件 > 导出子菜单有 HTML、图片、PDF 和妙言 PPT PDF，没有一个是 Word 格式，也不能替代 Pandoc 去编辑，适合的情形是读的人要的是渲染后的样子，而不是可编辑文字。

- **PDF。** 文件 > 导出 > PDF 把预览打印到固定的 A4 页面，保存在下载目录，对方只读，或者图表必须保持原样时用它，内容见 [Mac 上把 Markdown 导出 PDF](/zh/blog/markdown-to-pdf-mac/)。
- **HTML。** 文件 > 导出 > HTML 写出 `标题.html`，样式和脚本从妙言的 CDN 加载，本地图片的路径也指向那个 CDN，加载不出来，见 [Markdown 转 HTML](/zh/blog/markdown-to-html/)。可以用浏览器打开，选中内容再粘贴进 Word，但 Word 对粘贴进来的 HTML 保留多少并不固定，拿自己的笔记试一次再检查结果，能跟着过来的只有远程图片。
- **图片。** 写出整个预览的 PNG，更适合单张插图，不适合当文档。

## 哪些能保留，哪些会丢

| 笔记里的内容 | 经过 Pandoc | 怎么处理 |
| --- | --- | --- |
| 标题、列表、粗体、链接 | 变成 Word 样式 | 检查参考文档里的样式 |
| 表格 | 变成使用 Table 样式的 Word 表格 | 检查列宽和对齐 |
| 代码围栏 | 标了语言的围栏会高亮，在 docx 里用 Source Code | 检查长行 |
| `$...$` 公式 | 写成 Word 公式（OMML） | 点一下公式确认 |
| Mermaid、PlantUML、Markmap 块 | 对 Pandoc 来说是带语言名的普通代码，不会画图 | 把图贴成图片 |
| `> [!NOTE]` 提示块 | 加 `-f gfm` 时变成一行 Note 加正文的普通段落，用 Pandoc 自己的 Markdown 时是以 `[!NOTE]` 开头的引用 | 在 Word 里重新排版或改写 |
| `[[双链]]` | Pandoc 有 `wikilinks_title_after_pipe` 和 `wikilinks_title_before_pipe` 两个扩展 | 换成真正的链接，或者启用其一 |

图表方面，妙言在预览和 PDF 导出里会渲染 Mermaid 和 Markmap，一个可行的办法是从预览里截下图表，作为图片插入，Mermaid 源码仍留在笔记里；PlantUML 需要网络，预览要向 PlantUML 服务器取 SVG。

提示块的框会丢。妙言会把 `> [!NOTE]` 引用块渲染成带样式的提示块，Pandoc 手册说它的 `alerts` 扩展支持 GitHub 风格的 Markdown alert，`--list-extensions` 显示这个扩展在 `gfm` 里开着、在 Pandoc 自己的 Markdown 里关着。在 Pandoc 3.12.1 里，`-f gfm` 会把提示块变成一行 Note 加正文，都是 First Paragraph 样式，没有框也没有颜色，用 Pandoc 自己的 Markdown 则保留为以 `[!NOTE]` 开头的引用。

## 转完之后的检查

1. 打开文件，在 Word 的导航窗格里看标题层级，跳级说明源文件里就跳了。
2. 滚到每一张表和每一张图，图缺了说明 Pandoc 没找到文件，在笔记所在目录运行，或者设 `--resource-path`。
3. 点一个公式，它应该是公式，如果是图片或者原样的美元符号，回头检查输入格式。
4. 看第一页，笔记开头的 front matter 是元数据而不是正文，确认标题和作者是你要的样子。
5. 搜 `[!`、`[[` 和三个反引号，找出没转换的提示块、双链和代码围栏。
6. 在 `custom-reference.docx` 里改一个样式，重新转换，确认整篇文档都跟着变。

Pandoc 的 raw 块可以往 docx 里插入 Word 专用的 XML，比如分页符，手册在 `raw_attribute` 扩展那一节给了例子，这个扩展在 Pandoc 自己的 Markdown 里开着、在 `gfm` 里关着，按 GFM 读时要写成 `-f gfm+raw_attribute`，Markdown 表达不了的版式细节可以这样控制。Markdown 本身能写什么，见 [Markdown 语法速查](/zh/blog/markdown-cheat-sheet/) 和 [Markdown 里画 Mermaid 图](/zh/blog/mermaid-diagrams-in-markdown/)。

## 常见问题

### 妙言能直接存成 .docx 吗？

不能，V4.5.0 导出 HTML、图片、PDF 和妙言 PPT PDF，要 docx 就对笔记文件跑 Pandoc。

### 为什么中文和英文看起来不是一个字体？

样式里西文和中文各指定了一个字体，在参考文档的样式里设置东亚字体。

### 需要装 LaTeX 吗？

转 docx 不需要，Pandoc 对 LaTeX 的依赖在它默认的 PDF 路径上，不在 Word 文件上。
