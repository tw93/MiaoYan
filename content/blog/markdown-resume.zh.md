简历写成一个 `.md` 文件，放进 git，再用 Pandoc 加一份小 CSS 导出 PDF，不想装东西就用妙言的「文件」>「导出」>「PDF」。内容只用标题、列表、加粗斜体、链接，最多再加一张小表格。取舍在可控程度上，妙言印出来的是固定 A4 和它自己的样式，不支持自定义 CSS，Pandoc 可以改纸张、边距和字体，但要在命令行里装。

## 一份完整的示例简历

下面这份是虚构的，值得照抄的是结构，名字用唯一的一个 `#` 标题，下面一行联系方式，然后是 `##` 分节。

```markdown
# 陈小满

后端工程师 · 上海 · xiaoman@example.com · [github.com/chenxiaoman](https://github.com/chenxiaoman)

## 简介

七年后端经验，用 Go 和 PostgreSQL 做过支付和开票服务，喜欢小服务、平淡的发布流程和写清楚的值班手册。

## 工作经历

### 高级后端工程师，海浪支付

*上海 · 2022.03 至今*

- 用 Go 重写发票导出服务，夜间任务从 4 小时缩短到 35 分钟。
- 带 4 人团队把单体拆成 6 个服务，迁移期间对客户没有停机。

### 后端工程师，郁金香物流

*杭州 · 2018.08 至 2022.02*

- 做了 40 家合作承运商在用的运单追踪接口。
- 把夜间任务从 cron 迁到队列，失败的任务会自己重试。

## 技能

| 方向 | 工具                              |
| ---- | --------------------------------- |
| 语言 | Go、Python、SQL、TypeScript       |
| 数据 | PostgreSQL、Redis、Kafka          |
| 工具 | Docker、Terraform、GitHub Actions |

## 教育

**计算机科学与技术 本科**，浙江大学，2014 至 2018
```

时间写在每个职位下面的斜体行里，`###` 标题就能保持很短，改一个日期在 diff 里也只是一行。

## 哪些 Markdown 元素适合简历

简历篇幅短、结构重复，正好是 Markdown 擅长的东西。

**标题。** 一个 `#` 放名字，`##` 放分节，`###` 放每一段工作或学历。

**列表。** 每段工作的正文，一条写一个成果。

**加粗和斜体。** 加粗用在学历上，斜体用在地点和时间那一行。

**链接。** 像示例那样，把可见的地址写成链接文字。妙言的 PDF 样式会去掉链接的下划线和颜色，链接印出来和普通文字一样，纸面上的读者仍然能看到地址。

**小表格。** 技能可以用表格，不过 GitHub Flavored Markdown 的表格必须有表头行，所以上面的表格多了「方向」「工具」两个你可能不想要的表头，而且在妙言的 PDF 里表格会带边框、表头有底色、各列等宽，写成 `- 语言：Go、Python、SQL` 这样的列表印出来更干净。表头和对齐的规则见 [Markdown 表格](/zh/blog/markdown-tables/)。

**不要用的。** 图片、嵌套很深的列表和代码块。纯 Markdown 做不出分栏和侧边栏，想要两栏就得写 HTML 或者用设计工具。

## 用 Pandoc 导出 PDF

Pandoc 先把 `.md` 转成 HTML 或 LaTeX，再交给 PDF 引擎，手册里 `--pdf-engine` 列了 `weasyprint`、`xelatex`、`pdflatex` 等，也写明 `--css` 只对 HTML 和 EPUB 输出有效，所以有两条路。

**HTML 引擎加 CSS。** 建议先走这条，样式就是普通 CSS。把下面的内容存成 `resume.css`：

```css
@page { size: A4; margin: 16mm 18mm; }
body { font-family: "PingFang SC", "Helvetica Neue", Arial, sans-serif; font-size: 10pt; line-height: 1.45; }
h1 { font-size: 22pt; margin: 0 0 4pt; }
h2 { font-size: 11pt; border-bottom: 1px solid #999; margin: 14pt 0 6pt; }
h3 { font-size: 10.5pt; margin: 8pt 0 0; }
h3 + p { margin: 0 0 3pt; color: #555; }
ul { margin: 3pt 0; padding-left: 14pt; }
a { color: inherit; }
```

装好 WeasyPrint 后运行：

```bash
pandoc resume.md -o resume.pdf --pdf-engine=weasyprint --css=resume.css -M pagetitle="陈小满的简历"
```

用 Pandoc 3.13 和 WeasyPrint 68.1 跑上面的示例，得到的是一页 A4，文字都能选中，中文靠 CSS 里的 `font-family: "PingFang SC"` 就能正常显示。`-M pagetitle=...` 设置 PDF 标题，不会在页面上多出一个标题块。

**LaTeX。** 不写 `--pdf-engine` 时 Pandoc 走 LaTeX，所以要装 TeX。Pandoc 的 LaTeX 输出默认是美国 Letter，需要自己设纸张：

```bash
pandoc resume.md -o resume.pdf --pdf-engine=xelatex -V papersize=a4 -V geometry:margin=18mm -V mainfont="Helvetica Neue"
```

`papersize`、`geometry` 和 `mainfont` 都是 Pandoc 手册 LaTeX 部分的变量，出来的是 Pandoc 默认的 LaTeX 样子，不是上面那种紧凑版式。写中文简历时，手册说 `xelatex` 下的 `CJKmainfont` 需要 `xeCJK`，走 HTML 这条路就没有这个麻烦。

## 用妙言导出 PDF

选中笔记，点「文件」>「导出」>「PDF」，妙言把渲染好的预览印到 A4 上（595.2 × 841.8 点），上边距 40 点、下边距 48 点、左右各 45 点，文件按笔记标题命名存到「下载」。具体步骤和快捷键见[在 Mac 上把 Markdown 转成 PDF](/zh/blog/markdown-to-pdf-mac/)。

4.9.0 里能改和不能改的有这些：

- 正文和标题用设置里的预览字体。
- 纸张、边距、页眉都是固定的。
- PDF 没有自定义 CSS。
- 笔记以 `#` 标题开头时，这个标题就是页面标题，名字不会印两遍，PDF 还会带一行灰色的 `1 / N` 页脚。
- 链接没有下划线和颜色，表格带边框、表头有底色，深色预览下页面背景也是白的。

结果是一页干净的文档，但没法改样式，在意外观就对同一个 `.md` 跑 Pandoc。

## 控制分页

想让某一节从新的一页开始，在两个块之间放一行原始 HTML：

```markdown
<div style="page-break-after: always"></div>
```

Pandoc 加 WeasyPrint 会认这一行，LaTeX 这条路会丢掉原始 HTML，分页就被忽略了，LaTeX 要写 `\newpage`。妙言的预览保留原始 HTML，PDF 由 WebKit 打印，WebKit 分页时认 `page-break-after: always`（也认较新的 `break-after: page`），所以导出的 PDF 里也会换页，看一下页脚的 `1 / N` 就知道有没有生效。

## 一份源文件，多个岗位

长的完整版放在 `main` 上，每个岗位拉一个分支：

```bash
git switch -c resume/platform-engineer
```

在这个分支里删条目、调顺序，改错别字或加一段新工作就提交到 `main`，再合并进各个岗位分支，每个分支用同一条命令导出自己的 PDF。

front matter 适合管构建，不适合选内容。文件开头写上 `pagetitle: 陈小满的简历`，Pandoc 就把它当作 PDF 标题，命令里不用再写 `-M`，妙言在预览和导出里会隐藏文件开头的 front matter，不会出现在页面上。Pandoc 用不到的键，比如 `role: backend`，也不会出现在 PDF 里，只能当给自己的备注，不是开关。按岗位选内容仍然要靠分支或者另一个文件，妙言在什么情况下把一段当作 front matter，见 [Markdown front matter](/zh/blog/markdown-front-matter/)。

## 常见出错的地方

- **表格带边框、各列等宽。** 这是妙言的打印样式，技能改成列表。
- **分页没有生效。** LaTeX 这条路会丢掉原始 HTML，改用 `\newpage`。
- **LaTeX 遇到中文报错。** 它需要 `CJKmainfont` 和 `xeCJK`，改走 HTML 这条路，在 CSS 里设 `font-family`。
- **PDF 是 Letter 不是 A4。** 这是 Pandoc 的 LaTeX 默认值，加上 `-V papersize=a4`。
- **链接印出来像普通文字。** 妙言就是这样设计的，把地址写在链接文字里。

## 常见问题

### Markdown 简历能通过招聘系统的筛选吗？

这取决于具体的系统，它们只看到 PDF，看不到 Markdown，你能控制的是 PDF 里有按阅读顺序排好的真实文字，上面 Pandoc 的两条路导出的都是能选中的文字，`pdftotext resume.pdf -` 能从上到下读出来，投递前对自己的文件跑一下就行。

### 投递时可以直接发 `.md` 文件吗？

发 PDF。多数投递表单要的是 PDF 或 Word，PDF 也保得住版式，`.md` 留作源文件。
