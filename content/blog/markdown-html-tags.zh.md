可以，CommonMark 把原始 HTML 当作语言的一部分，分两种写法，段落里的标签会原样放行，写在行首的标签可以开启一个 HTML 块，整块原样输出。真正有差别的是查看的地方，GFM 会过滤九个标签，GitHub 在此之上还会清理一大批，妙言的预览则什么都放行，所以同一份笔记可能在这里好好的，换个地方 HTML 就没了。

## 原始 HTML 有两种

[CommonMark 规范](https://spec.commonmark.org/0.31.2/)在两处处理 HTML。第 6.6 节 Raw HTML 讲行内 HTML，`<` 和 `>` 之间看起来像标签的文字会不转义地输出，标签名也不限于真实存在的 HTML 元素，所以 `<Warning>` 也算。语法覆盖开始标签、结束标签、注释、处理指令、声明和 CDATA。两个行内标签之间的内容仍然是 Markdown，所以同一行里的 `<span>**加粗**</span>` 会得到 span 里的粗体。

第 4.6 节 HTML blocks 讲从行首开始的 HTML。一共有七种起始条件，每种有自己的结束条件，行首可以有最多三个空格的缩进：

| 类型 | 起始 | 结束 |
|---|---|---|
| 1 | `<pre`、`<script`、`<style` 或 `<textarea` | 含有 `</pre>`、`</script>`、`</style>` 或 `</textarea>` 的那一行，不必和起始标签对应 |
| 2 | `<!--` | 含有 `-->` 的那一行 |
| 3 | `<?` | 含有 `?>` 的那一行 |
| 4 | `<!` 加一个 ASCII 字母 | 含有 `>` 的那一行 |
| 5 | `<![CDATA[` | 含有 `]]>` 的那一行 |
| 6 | `<` 或 `</` 加 62 个块级名称之一，比如 `div`、`p`、`table`、`details`、`summary`、`ul`、`h1` 到 `h6` | 空行 |
| 7 | 其他完整的开始标签或结束标签，且独占一行 | 空行 |

类型 1 到 5 里可以有空行，所以注释和 `<script>` 能跨好几段，类型 6 和 7 不行。类型 7 还不能打断段落（规范的 Example 187），所以紧跟在文字下一行的标签仍然是行内 HTML。

## 为什么空行会结束 HTML 块，块里的 Markdown 为什么不解析

HTML 块里 Markdown 是关掉的，规范说结束条件之前的所有内容都当作原始 HTML 原样输出，Example 161 里的围栏代码块就因为落在 HTML 块里而保持原样。最容易踩的就是这条：

```markdown
<div>
**不是粗体**
</div>

<div>

**粗体**

</div>
```

第一个 `<div>` 开启类型 6 的块，一直到第一个空行才结束，所以星号保持原样。第二个里，`<div>` 后面的空行结束了块，`**粗体**` 成为普通段落，`</div>` 前面的空行让结束标签自己另起一个块，规范的 Example 152 是同样的形状。

规范说这些规则是为既能当块级元素也能当行内元素的标签设计的，并用 `<del>` 举例。单独一行的 `<del>` 开启一个块，`*foo*` 保持原样（Example 166）；内容前后都有空行时，只有标签行是原始 HTML，内容按 Markdown 解析（Example 167）；写在同一行的 `<del>*foo*</del>` 是行内 HTML，内容照常解析（Example 168）。

随之有两个坑。规范没有列在块级名称里的标签，比如 `<a href="foo">` 或 `<kbd>`，只有在完整且独占一行时才会开启块（Example 162 到 165）。另外 `<div>` 不需要写结束标签，块反正会在下一个空行结束（Example 155）。[折叠区块](/zh/blog/markdown-collapsible-sections/)讲了这条规则怎么影响 `<details>` 和 `<summary>`。

## GFM 过滤了什么

[GFM 规范](https://github.github.com/gfm/)在 6.11 节 Disallowed Raw HTML 里加了一个扩展，通常叫 tagfilter，渲染 HTML 时下面这些标签会被过滤：

```text
<title> <textarea> <style> <xmp> <iframe> <noembed> <noframes> <script> <plaintext>
```

过滤的方式是把开头的 `<` 换成 `&lt;`，标签就变成可见文字，不会生效。规范说选它们是因为它们会改变嵌套在里面的 HTML 的解释方式，其他标签一律不动，匹配不分大小写，规范自己的例子里 `<xmp>` 和 `<XMP>` 都被禁用。

要不要挂上这个扩展由解析器决定，不挂的渲染器会把 `<script>` 原样放过去。

## GitHub 在此之上还会去掉什么

GitHub 先做这层过滤，再对结果做清理。[github/markup 的 README](https://github.com/github/markup) 说 HTML 会被清理，「aggressively removing things that could harm you and your kin」，列出 `script` 标签、行内样式、`class` 和 `id` 属性。2026-11-14 用 GitHub 的 Markdown API（`gh api markdown -f text='...' -f mode=gfm`）实测的结果如下，和这句话有一处不同。

| 输入 | GitHub 返回的 |
|---|---|
| `<script>alert(1)</script>` | `&lt;script&gt;alert(1)&lt;/script&gt;`，显示为文字 |
| `<style>p{color:red}</style>`、`<iframe ...>` | 同样显示为文字 |
| `<span style="color:red">red</span>` | `<span>red</span>`，style 没了 |
| `<div style="color:red" class="foo" onclick="alert(1)" id="d1">` | `<div id="user-content-d1">`，style、class、onclick 都没了 |
| `<img src="a.png" width="120" style="border:1px solid red">` | 保留 `width`，`style` 属性没了，GitHub 加上自己的 `max-width` 样式并给图片套了一层链接 |
| `<a href="javascript:alert(1)">js</a>` | 只剩文字 `js`，没有链接 |
| `<a name="top"></a>` | `<a name="user-content-top"></a>` |
| `<u>`、`<small>`、`<abbr>`、`<center>`、`<font>` | 标签被去掉，文字保留 |
| `<kbd>`、`<sup>`、`<sub>`、`<mark>`、`<details open>`、`<br>`、`<p align="center">` | 保留 |

所以 `id` 不是被删掉，而是保留并加上 `user-content-` 前缀。GitHub 的[基础格式文档](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)明确写到了 `<sub>`、`<sup>`、`<ins>`、写成 `<a name="...">` 的自定义锚点，以及用 `<br/>` 换行，其余都来自 API 的输出，以后可能变，当作一份快照，在你真正要用的仓库里再测一遍。

## 通用性比较好的标签

下表列出多数笔记真正用得到的 HTML 和对应的详细文章，「GitHub」一列是上面的 API 结果。

| 标签 | 用途 | GitHub | 妙言预览 | 详细 |
|---|---|---|---|---|
| `<kbd>` | 按键，比如 `Cmd` | 保留 | 原样放行，预览 CSS 里没有它的规则 | |
| `<sup>`、`<sub>` | 角标、`H<sub>2</sub>O` | 保留 | 原样放行 | [下划线与颜色](/zh/blog/markdown-underline-and-color/) |
| `<mark>` | 高亮 | 保留 | 原样放行，黄色背景 | [下划线与颜色](/zh/blog/markdown-underline-and-color/) |
| `<details>`、`<summary>` | 折叠块 | 保留 | 原样放行 | [折叠区块](/zh/blog/markdown-collapsible-sections/) |
| `<br>` | 换行，表格单元格里也能用 | 保留 | 原样放行 | |
| `<img width="...">` | 图片尺寸 | 保留 width，丢掉 style | 原样放行，宽度不超过正文栏 | [图片](/zh/blog/markdown-images/) |
| `<a name="...">` | 跳转目标 | 保留，name 加前缀 | 原样放行，但笔记内链接按 `id` 查找 | [链接与锚点](/zh/blog/markdown-links-and-anchors/) |

能用语义标签就别用 `style` 属性，`<mark>` 在 GitHub 上能留下来，`<span style="color:red">` 文字留着颜色没了。

## 妙言怎么处理 HTML

V4.9.0 的预览用 cmark-gfm 解析，按名字挂了四个扩展，`table`、`footnotes`、`strikethrough` 和 `tasklist`（`Business/Markdown.swift` 第 22 行），tagfilter 不在其中。渲染时传的是 `CMARK_OPT_UNSAFE`，cmark 默认会把原始 HTML 换成占位注释，这里不换，所以每个标签和每个属性都会到预览里，`style` 和 `iframe` 也不例外。

从解析器到屏幕之间，除了改写图片地址，不再动这些 HTML。渲染出来的 HTML 被填进预览模板的 `DOWN_HTML` 位置，写成临时的 `index-<uuid>.html`，用 `loadFileURL` 打开，读取权限设为 `/`，所在的 web view 配置里 `allowsContentJavaScript` 为 true，模板没有声明 Content-Security-Policy，这条路径上也没有删除 `script` 标签的步骤。

同一个渲染器也供 PDF 和 HTML 导出使用，见 [Markdown 转 HTML](/zh/blog/markdown-to-html/)。

## HTML 没有出现时

- **块里的 Markdown 保持原样。** 补上前面说的空行，或者把标签和内容写到同一行。
- **标签变成了文字。** 渲染器用了 tagfilter 把 `<` 替换掉了，换成九个之外的标签。
- **标签没了，文字还在。** 像 GitHub 那样被清理器去掉了，换成目标处会保留的标签。
- **样式没了。** GitHub 会去掉行内样式，改用 `<mark>`、`<ins>` 或 `align`。
- **只有妙言里正常。** 预览什么都放行，到读者会看的地方再检查一遍。

## 常见问题

### Markdown 里可以用 HTML 吗？

可以，CommonMark 允许行内 HTML 和 HTML 块，至于某个标签最后出不出来，由渲染器决定。

### 为什么 HTML 标签里的 Markdown 没有渲染？

那个标签开启了 HTML 块，块会一直到下一个空行，期间 Markdown 是关掉的，在开始标签后面补一个空行即可。

### 为什么 GitHub 把 `<script>` 显示成文字？

GFM 的 tagfilter 会把九个标签的 `<` 换成 `&lt;`，GitHub 又对输出做了进一步清理。

### 妙言会去掉笔记里的 HTML 吗？

不会，预览保留原始 HTML 和属性，适合试一个标签，不适合用来判断别的读者会看到什么。
