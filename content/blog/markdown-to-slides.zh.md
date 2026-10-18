把 Markdown 变成幻灯片，做法是在每两页之间单独写一行 `---`，再用支持这种分页的工具打开。在妙言里按 `Command + Option + P`，笔记里至少要有一行 `---`。reveal.js、Marp 和 Slidev 用的是同一个约定，给其中一个写的稿子大多能搬到另一个，区别在主题、导出格式，以及要装多少东西。

## 基本格式

```markdown
# 季度回顾

团队同步

---

## 已经发布

- 编辑器重写
- 更快的预览

---

## 接下来

1. 同步
2. 导出
```

分隔符之间的每一块就是一页，第一块是开场页，所以一个一级标题加一行副标题就是封面。`---` 要独占一行，同一行不能有别的字符。妙言自带的 PPT 指南和 Agent skill 都写明，一页里面不能再放横线，因为同样的字符会被当作分页符。

如果在没有 `---` 的笔记上按快捷键，妙言会提示没有检测到分页符，无法开启幻灯片演示。

## 在妙言里怎么用

1. 打开或新建一篇笔记，在页与页之间加上 `---`。
2. 按 `Command + Option + P`。
3. 按 Enter 预览幻灯片大纲，按 ESC 退出，自带的 PPT 笔记里是这样写的。
4. 想要文件的话，用导出菜单里的妙言 PPT PDF。

新用户安装后会有一篇带可运行示例的妙言 PPT 笔记，老用户可以自己建一篇同名笔记，把稿子贴进去。

### 用注释配置

在笔记最开头写一段由 `key: value` 行组成的 HTML 注释，如果有 YAML frontmatter 就放在它后面。

```markdown
<!--
transition: slide
slideNumber: c/t
controls: true
progress: true
-->
```

这些键直接对应 reveal.js 的配置项，值会被识别成布尔值、数字、`null`、方括号列表或字符串，`highlight.lineNumbers` 这样带点的键会设置嵌套选项，渲染之前妙言会把这段注释去掉。默认值是滑动切换、显示控制按钮和进度条、用网址哈希导航、不显示页码、页面内容不垂直居中。

### 单页的额外设置

````markdown
<!-- .slide: data-background="#F8CB9E" -->
## 自定义背景

- 第一点 <!-- .element: class="fragment" data-fragment-index="1" -->
- 第二点 <!-- .element: class="fragment" data-fragment-index="2" -->

```swift [1|2-3]
let a = 1
let b = 2
```
````

`.slide:` 注释设置这一页的属性，比如背景色、渐变或图片。某一行末尾的 `.element:` 注释给那个元素加属性，`class="fragment"` 表示点一下再显示。语言围栏后面跟 `[1|2-3]` 会逐步高亮对应的行，这些都是 reveal.js 的功能，文档在 revealjs.com/markdown。

幻灯片里可以用 `$...$` 和 `$$...$$` 写公式，Mermaid、PlantUML 和 Markmap 块在演示模式里同样会渲染。要做两栏，可以用带 `display: flex` 的原生 HTML，每个 `div` 里面留一个空行，这样里面的 Markdown 才会照常解析。

写成 `/i/photo.png` 的本地图片会被改写成幻灯片能加载的路径，所以同一张图在普通笔记和演示稿里都能用。

## 它实际是怎么工作的

妙言的 PPT 模式就是一个 reveal.js 页面。笔记正文放进一个 markdown 区段，由 reveal 的 Markdown 插件按分隔符拆开，默认的分隔写法是前后都有换行的 `---`。需要第二种分隔符的纵向幻灯片，在 reveal.js 里默认关闭，妙言的 PPT 页面也没有启用，所以得到的是一串平铺的横向页面。文本进入插件之前，妙言会先保护公式、转义反斜杠和美元符号，再改写图片路径，主题会跟随妙言的浅色或深色外观在 reveal 的 white 和 night 样式之间切换。

既然是 reveal.js，演讲者备注也遵循它的约定，以 `Note:` 开头的行是这一页的备注。正式演讲之前，先把演讲者视图试一遍。

## 任何工具都适用的结构建议

- 一页只讲一件事，一页需要滚动就拆开。
- 用标题当页标题，普通页用 `##`，章节开头页用 `#`。
- 要点控制在四五条，只有顺序重要时才把长列表做成逐条出现。
- 结论放前面，第二页就说出答案，整套稿子更好跟。
- 图片写上说明文字，并且放在同一个文件夹里，搬家时路径不会断。
- 按实际演示的尺寸预览一次，代码和表格缩小后很容易看不清。

## 其他做幻灯片的办法

| 工具 | 怎么写 | 输出 | 需要什么 |
|---|---|---|---|
| 妙言 PPT 模式 | 带 `---` 分隔符的笔记 | 屏幕演示、PDF | Mac 上的妙言 |
| reveal.js | Markdown 或 HTML | 浏览器里的幻灯片，通过打印导出 PDF | 浏览器，页面要自己搭 |
| Marp | 带 `---` 的 Markdown，基于 CommonMark | HTML、PDF、PowerPoint | Marp for VS Code 或 Marp CLI，PDF 和 PowerPoint 导出要用 Chrome 或 Chromium |
| Slidev | 带 `---` 和每页 YAML frontmatter 的 Markdown | 格式见 sli.dev | 安装步骤在它的 Getting Started 指南里 |

表里的信息来自 marp.app、revealjs.com 和 sli.dev，核对日期是 2026-10-18。需要给别人一个 `.pptx` 文件，选 Marp。想在 YAML 里按页设置布局和背景，并且不介意搭它的工具链，选 Slidev。想完全掌控页面，直接用 reveal.js。演示稿只是平时笔记的副产品，想用一个快捷键就开讲，选妙言的这个模式。

## 常见问题排查

- **按快捷键只弹出一条提示。** 笔记里没有 `---` 行，妙言会提示没有分隔符，无法使用妙言 PPT。
- **第一页不见了。** 笔记如果以一行 `---` 开头，到下一行 `---` 为止的内容都会被当作 frontmatter 隐藏，所以演示稿要从标题开始写，不要以分隔符开头。
- **一页里想放横线。** 换成标题或者留白。
- **图片不显示。** 笔记里改用 `/i/<文件名>` 或 `https://` 地址，不要用 `file://` 路径。
- **需要 PowerPoint 文件。** 妙言导出的是 PPT PDF，不是 `.pptx`。

相关阅读可以看 [Markdown 语法速查](/zh/blog/markdown-cheat-sheet/) 和 [Markdown 里画 Mermaid 图](/zh/blog/mermaid-diagrams-in-markdown/)，应用可以在 [App Store](https://apps.apple.com/app/id6759252269) 下载，源码托管在 [github.com/tw93/MiaoYan](https://github.com/tw93/MiaoYan)。

## 常见问题

### 能导出成 PowerPoint 吗

妙言不支持，PPT 模式导出的是 PDF，Marp 列出了 PowerPoint 输出。

### 需要懂 reveal.js 吗

写基础演示稿不需要，不过了解它的属性注释对设置背景和逐步显示有帮助。

### 同一个文件能在别的工具里用吗

`---` 分隔符可以带到 Marp 和 Slidev，但 `<!-- .slide: -->` 这类注释是 reveal.js 专用的。
