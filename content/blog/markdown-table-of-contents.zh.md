Markdown 本身没有目录语法，想要目录有三种办法，手写一个嵌套列表，里面放指向标题的锚点链接；在支持的工具里写 `[TOC]` 这类标记；或者用生成器把列表直接写进文件。选哪种取决于笔记最后在哪里读，因为标题锚点怎么生成、`[TOC]` 认不认，都是渲染器说了算，Markdown 规范并不管。

## Markdown 里的目录是什么

目录就是一个普通的嵌套列表，每一项链接到同一篇文档里的某个标题，链接写成 `#id`。CommonMark 没有规定标题怎么变成 id，每个工具各有一套规则，手写目录出问题，多半就出在这一点上。

```markdown
## 目录

- [安装](#安装)
  - [在 Mac 上](#在-mac-上)
  - [从源码编译](#从源码编译)
- [使用](#使用)
```

子项缩进就嵌套成下一级。列表本身是普通 Markdown，在哪里都能渲染，链接能不能跳转，要看锚点对不对得上。

## 标题锚点是怎么生成的

GitHub 在基础写作和格式语法的文档里写明了规则，字母转成小写，空格换成连字符，其他空白和标点去掉，重复的标题在后面加连字符和一个递增的整数。所以 `## Install on Mac` 对应 `#install-on-mac`，`## What's new?` 对应 `#whats-new`，同一个文件里后面再出现一个 `## Install on Mac`，就是 `#install-on-mac-1`。想看 GitHub 实际生成了什么，把鼠标放到标题上点出现的链接图标，再看地址栏。

别的工具不一样，Python-Markdown 的 `toc` 扩展给重复标题加的是下划线（`header`、`header_1`、`header_2`），slug 函数也可以自己换。所以从 GitHub 的 README 把目录抄到别的站点，遇到重复标题或标点，链接可能悄悄失效。锚点、自定义 `<a id>` 和中文标题的更多细节见 [Markdown 链接与锚点](/zh/blog/markdown-links-and-anchors/)。

## [TOC] 标记在哪里有效

有些工具允许写一行标记，再把它替换成生成的目录，这些都不属于 CommonMark 或 GFM，GitHub 的语法文档里也没有列出任何这类标记。

- **Python-Markdown**（MkDocs 用的引擎）有 `toc` 扩展，标记默认是 `[TOC]`，会被替换成标题的嵌套列表，`toc_depth` 决定包含哪几级。
- **Typora** 的文档写的是输入 `[toc]` 再按回车，就会生成目录，并且随文档改动自动更新。
- **markdown-it-table-of-contents** 是 markdown-it 的插件，默认标记是 `[[toc]]`，要写在行首，默认只包含一级和二级标题。它的 README 提醒，这个插件不会给标题加 id，不另外装锚点插件的话，列表里的链接都是死的。

实际的判断办法是，标记只是某一套工具链的约定，笔记只在那套工具里读，用标记最省事，文件要流转到 GitHub 或别的应用，标记就会原样显示成文字。

## 用生成器，不手敲

生成器会把嵌套的链接列表写进文件，列表是普通 Markdown，在任何渲染器里都在，只要锚点风格和目标站点一致。

### doctoc

doctoc 是 Node 命令行工具，装好以后对单个文件或整个目录运行：

```bash
npm install -g doctoc
doctoc README.md
doctoc .
```

默认把列表插在文件开头（有 front matter 就在它后面），前后包着标记注释（`<!-- START doctoc ... -->` 和 `<!-- END doctoc ... -->`），之后再运行会按注释找到旧列表原地更新，这一块也可以挪到你想放的位置。README 里常用的选项有，`--maxlevel 3` 限制深度，`--notitle` 去掉自动生成的标题，`--github` 或 `--gitlab` 选锚点风格（默认 GitHub），`--dryrun` 不写文件，有文件过期就以退出码 1 结束，适合放进 CI。文件开头写 `<!-- DOCTOC SKIP -->` 会被跳过，标题上一行写 `<!-- DOCTOC EXCLUDE -->` 则不进目录。

### VS Code 的 Markdown All in One

在 VS Code 里装名为 Markdown All in One 的扩展，打开命令面板运行 `Markdown All in One: Create Table of Contents`。设置项 `markdown.extension.toc.levels`（默认 `1..6`）控制包含哪几级标题，`markdown.extension.toc.updateOnSave`（默认 `true`）让每次保存都刷新目录。扩展把你写的某个列表误认成目录时，在列表上面加一行 `<!-- no toc -->`。想要带编号的标题，同一个扩展还有 `Markdown All in One: Add/Update section numbers`。

### Pandoc

Pandoc 把目录放在转换后的输出里，不改 Markdown 源文件：

```bash
pandoc notes.md -s --toc --toc-depth=2 -o notes.html
```

手册说明 `--toc` 不加 `-s`（独立文档）就没有效果，对 `man`、`docbook4`、`docbook5` 和 `jats` 输出也没有效果，默认深度是 3。对 `docx`、`odt`、`rst`、`latex` 等格式，它插入的是让该格式自己生成目录的指令，不是 HTML 列表。这条路适合要转换的文档，不适合想直接当 Markdown 读的 README。

## GitHub 自带的大纲

GitHub 渲染的文件其实不需要目录。官方文档写明，文件有两个或更多标题时会自动生成目录，点文件头部的 Outline 菜单图标就能打开，README 里手写的目录，只有在别人读原始文件或别的站点的副本时才有保留的价值。

## 妙言里的目录

妙言的目录在预览里，不在 Markdown 文件里，也不用写任何标记。菜单是「视图」下的 Toggle TOC（中文界面叫「切换目录」），快捷键 `Cmd+5`。

按 V4.9.0 的源码，这个面板是这样的：

- 它在预览右边缘的浮动面板里列出 1 到 3 级标题，鼠标放到边缘的细条上会显示，`Cmd+5` 打开时是固定住的，面板里有图钉按钮可以保持展开。
- 笔记里至少有两个 1 到 3 级标题才会出现，预览窄于 600 像素时边缘细条会隐藏，没固定的面板也会收起。
- 菜单项在预览和分栏模式下可用，妙言 PPT 模式下是禁用的。
- 第一次看到预览时，边缘细条上会出现一个红色的小「TOC」角标，只出现一次。
- 点一项，预览滚动到那个标题，滚动时当前所在的标题会高亮。
- 导出 PDF 时面板会被隐藏，但 h1 到 h3 会写成 PDF 书签，在 PDF 阅读器的侧栏里能看到。

有两点要知道。妙言不会把 `[TOC]` 或 `[[toc]]` 变成列表，这两行会按普通文字显示。它的标题 id 是标题的可见文字，不是 GitHub 那种小写加连字符，所以手写的 `[安装](#install-on-mac)` 在预览里不会跳转，面板不受影响，因为它自己建链接，手写目录则要写成 `#Install%20on%20Mac` 的形式，或者用自定义的 `<a id>`，细节在 [Markdown 链接与锚点](/zh/blog/markdown-links-and-anchors/)。PDF 导出和书签落在哪一页见[在 Mac 上把 Markdown 转成 PDF](/zh/blog/markdown-to-pdf-mac/)，标题和列表的语法见 [Markdown 语法速查](/zh/blog/markdown-cheat-sheet/)。

## 出了问题怎么查

- **链接点了没反应。** 列表里的锚点和渲染器生成的 id 对不上，在 GitHub 上悬停标题核对，或者对照工具的 slug 规则，重复标题和标点是最常见的原因。
- **`[TOC]` 这一行显示成文字。** 渲染器不支持这个标记，换成生成的列表或查看器自带的大纲。
- **目录过期了。** 手写的列表不会跟着改动更新，用 doctoc 或 VS Code 命令，或者打开 `updateOnSave`。

## 常见问题

### Markdown 怎么加目录？

手写嵌套的 `[文字](#锚点)` 列表，或者用 doctoc、VS Code 的 Markdown All in One 生成。`[TOC]` 标记只在支持它的工具里有效。

### GitHub 支持 [TOC] 吗？

GitHub 的语法文档里没有列出。文件有两个或更多标题时，GitHub 会在文件头部显示 Outline 菜单。

### 为什么目录链接不跳转？

锚点和渲染器生成的标题 id 不一致。GitHub 是小写加连字符并去掉标点，别的工具各不相同。

### 导出的 PDF 能带目录吗？

妙言导出的 PDF 不会印出目录面板，但会把 h1 到 h3 写成 PDF 书签，想要印在纸面上的目录页，Pandoc 用 `-s --toc` 可以在它自己的输出格式里生成。
