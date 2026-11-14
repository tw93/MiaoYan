README 是一个叫 `README.md` 的 Markdown 文件，GitHub 会把它显示在仓库首页，等于项目的门面。一份好的 README 按顺序回答四件事，这是什么、怎么装、怎么用、怎么参与，用普通 Markdown 加几个 GitHub 支持的功能来写就够了，链接和图片尽量用相对路径，这样换分支、被克隆之后都不会断，推送之前再在本地预览一遍渲染结果。

## README 是干什么的，GitHub 在哪里显示它

GitHub 文档列出了 README 应该告诉访问者的内容，项目做什么、为什么有用、怎么开始、去哪里求助，以及谁在维护和贡献。

GitHub 会在三个位置找这个文件。仓库里有多个 README 时，显示的那一个按 `.github` 目录、仓库根目录、`docs` 目录的顺序选。多数项目放在根目录，克隆下来之后人们第一眼也是去根目录找。

有一个限制值得知道，在 GitHub 上查看时，超过 500 KiB 的内容会被截断，只有塞了大量数据才会碰到。

## 一个好用的章节顺序

这个顺序对应第一次来的访问者会依次问的问题，妙言自己的 README 大体也是这个路子。

1. **名称和一句话介绍。** 妙言的是「A native Mac app for local Markdown notes」，紧跟在标题下面，说清它是什么，不写它想成为什么。
2. **截图或演示。** 标题下面放一张图，妙言的 README 在徽章下面是一张 Mac、iPad、iPhone 的拼图。
3. **特性。** 三到五条，每条是一个事实，「笔记是你选的文件夹里的 Markdown 文件」比「强大灵活」有用得多。
4. **安装。** 有多条路径时用编号列表，妙言列了 App Store、Homebrew 和 GitHub Releases，Homebrew 那条是代码块里的 `brew install --cask miaoyan`。
5. **用法。** 最短的可运行示例，放进围栏代码块，命令行工具就写真实命令，应用就写新用户第一步要用的那个快捷键。
6. **配置。** 只写人们真会改的选项，并写出默认值。
7. **参与贡献。** 怎么报 bug、怎么提补丁，或者链到 `CONTRIBUTING.md`。
8. **许可证。** 一行，比如「MIT License」，并和仓库里的 `LICENSE` 文件一致。

没话可说的章节就别写，某一节长过一屏，就挪到 `docs/` 下面的文件里再链过去。代码要放在带语言名的围栏代码块里，GitHub 才会高亮，围栏的写法和嵌套代码要用更长围栏的规则见 [Markdown 代码块](/zh/blog/markdown-code-blocks/)。

## 相对链接和图片

指向仓库自己文件的链接用相对路径。GitHub 文档说它会按你当前所在的分支转换相对链接和图片路径，所以在功能分支上链接也不会断，并且相对链接对克隆仓库的人更方便，以 `/` 开头的链接则是相对于仓库根目录。

```markdown
![分栏编辑与预览](docs/images/split.png)
见[语法指南](docs/syntax.md)和[贡献说明](CONTRIBUTING.md)。
```

指向自己文件的绝对链接，比如完整的 `github.com/.../blob/main/...` 地址，反而是个坑，它把文件钉死在某一个分支上，在克隆下来的仓库里也可能打不开。链接文字要写在同一行里，GitHub 文档也是这么要求的。

妙言的 README 主截图用的是托管在官网上的绝对地址，这是选择而不是规则，README 被复制到仓库之外的地方时，托管的图照样能加载，相对路径却可能解析不了。README 会发布到多个地方时托管图更稳，只放在 GitHub 上就用相对路径更省事。图片语法、alt 文字和尺寸见 [Markdown 图片](/zh/blog/markdown-images/)，标题锚点和跳转见 [Markdown 链接与锚点](/zh/blog/markdown-links-and-anchors/)。

有多语言版本时，在顶部放一行语言链接，妙言的 README 就是一行链接，各自指向 `README_CN.md` 这样的同级文件。

## 徽章

徽章是标题旁边的一小张图，通常来自 shields.io，用来显示下载量、构建状态、许可证、支持的平台。shields.io 官网对自己的描述是「Concise, consistent, and legible badges」，它给出的静态徽章地址形如 `https://img.shields.io/badge/any%20text-you%20like-blue`，`/badge/` 后面依次是文字、第二段文字和颜色。

```markdown
![macOS 12.0+](https://img.shields.io/badge/macOS-12.0%2B-orange?style=flat-square)
```

妙言 README 里就用了这个徽章地址，只是写成了 HTML 的 `<img>` 标签，`flat-square` 是样式参数。徽章只留访问者会据此行动的几枚，一长排只是噪音，静态形式之外的写法去看 shields.io 自己的文档，实时徽章的地址格式因服务而异。

## GitHub 自动生成的目录

对渲染后的 Markdown 文件，GitHub 会根据章节标题自动生成目录，访问者从渲染页面顶部角落的 Outline 菜单图标打开。这带来两个结果，README 里不用再手写目录，标题层级同时成了导航，所以章节用 `##`，小节用 `###`，别跳级。鼠标悬停在标题上还会出现链接图标，可以拿到这个标题的锚点，直接链到某一节。

## 换个地方就不渲染的 GitHub 专属写法

GitHub Flavored Markdown 包含表格、任务列表、删除线和自动链接，很多渲染器都支持。但 README 里常见的几样东西是 GitHub 自己的功能，不是标准，在不支持它们的查看器里会显示成原始文字，标准和扩展的分界见 [CommonMark 和 GFM 的区别](/zh/blog/commonmark-vs-gfm/)。

- **提示块（alerts）。** 第一行是 `> [!NOTE]` 的引用块，另外四种类型是 `TIP`、`IMPORTANT`、`WARNING`、`CAUTION`，在 GitHub 上会带颜色和图标。文档建议一篇里用一两个，不要连续放，也不能嵌套在其他元素里，别处可能只会看到一个以 `[!NOTE]` 开头的普通引用。
- **Mermaid 图。** 语言名为 `mermaid` 的围栏代码块会被画成图，GitHub 说议题、讨论、拉取请求、wiki 和 Markdown 文件里都可以渲染，不支持 Mermaid 的工具只会显示成普通代码块，见 [Markdown 里画 Mermaid 图](/zh/blog/mermaid-diagrams-in-markdown/)。
- **任务列表里的议题引用。** 任务列表是 `- [ ]` 和 `- [x]`，GitHub 文档里的截图显示，任务项里的议题引用会被渲染成议题标题，这种替换是 GitHub 的，复选框本身是通用的。
- **换行。** 在议题和拉取请求里 GitHub 会把换行直接当成换行，`.md` 文件里却需要行尾两个空格、反斜杠或 `<br/>`，在评论框里看着正常的内容，写进文件可能连成一段。

README 如果还会在别处被阅读，就在那边也测一遍。

## 推送前先看一眼

README 容易出一些小毛病，表格的分隔行和表头单元格数量对不上就退回普通文字，相对路径写错，围栏没闭合把后面整页吞掉，最好在 GitHub 替你发现之前先预览。

在妙言里把 README 当笔记打开，按 `⌘\` 切换分栏，Markdown 和渲染结果并排显示。按 V4.9.0 的源码，预览用的是 cmark-gfm，开启了表格、脚注、删除线和任务列表，会渲染 Mermaid，原始 HTML 直接放行，所以很多 README 里居中的 `<div>` 和带 `width` 的 `<img>` 会按写的样子显示，`> [!NOTE]` 这类引用也会转成和 GitHub 类似的提示块。依赖 GitHub 本身的东西它查不了，相对链接要等推送后按分支解析，shields.io 徽章需要联网，Outline 菜单只在 github.com 上有，推送之后再打开一次仓库页确认。

任何本地的 Markdown 预览都行，关键是在别人之前先看到渲染结果，在 Mac 上选编辑器可以看 [Mac 上怎么选 Markdown 编辑器](/zh/blog/markdown-editor-for-mac/)。

## 常见问题

### 文件名该叫 README.md 还是 README？

用 `README.md` 就好，GitHub 的 README 文档只说 README 文件，但 `.md` 扩展名才会让 GitHub 和编辑器把它当 Markdown 处理。

### README 写多长合适？

够访问者装上并跑起来就行，详细的指南放进 `docs/` 再链过去。

### 可以每种语言一份 README 吗？

可以，主 README 放根目录，开头几行链到 `README_CN.md` 这样的同级文件，妙言就是这么做的。

### 提示块和 Mermaid 在 GitHub 之外能用吗？

不一定，它们是 GitHub 的功能，不支持的工具会显示成普通引用或代码块。
