Markdown 里放 emoji 有两种做法，一种是直接输入 Unicode 字符，比如 🎉，另一种是写成 `:tada:` 这样的短代码，让渲染器替换。字符在任何能显示文字的地方都能用，短代码并不属于 Markdown，只有查看器自己加了支持才会转换，其他地方会原样显示成带冒号的一串文字。

## 直接输入字符

emoji 就是普通的 Unicode 字符，Markdown 不会对它做任何特殊处理，它以文字形式存在 `.md` 文件里，复制粘贴也不会丢。在 Mac 上，苹果的支持页面 [Use emoji and symbols on Mac](https://support.apple.com/guide/mac-help/use-emoji-and-symbols-mchlp1560/mac) 给了两条路。

- 输入一个常用词，再按 Fn/地球仪键-E，苹果说明这会给出 emoji 建议，没有建议时会打开字符检视器。
- 什么都不输入，直接按 Fn/地球仪键-E，或者选择菜单栏的编辑 > 表情与符号，打开字符检视器搜索。

## 写成短代码

短代码就是夹在两个冒号中间的名字。GitHub 文档写的是输入 `:EMOJICODE:`，也就是冒号加 emoji 的名字，它给的例子是 `:+1: This PR looks great - it's ready to merge! :shipit:`。

这是 GitHub 的功能，不是 Markdown 的，[CommonMark 0.31.2 规范](https://spec.commonmark.org/0.31.2/)和 [GFM 规范](https://github.github.com/gfm/)全文都没有出现 emoji 这个词，所以只按规范实现的解析器会把 `:tada:` 当普通文字输出。两份规范各自定义了什么，见 [CommonMark 和 GFM 有什么区别](/zh/blog/commonmark-vs-gfm/)。

GitHub 的名字可以从 REST API 列出来，2026 年 11 月 14 日跑 `gh api emojis` 返回了 1936 个名字，其中 1913 个对应 Unicode 图片，23 个是 GitHub 自己的图片、没有 Unicode 对应，比如 `octocat`、`shipit` 和 `bowtie`。几个真实条目如下。

```text
smile             .../emoji/unicode/1f604.png
tada              .../emoji/unicode/1f389.png
rocket            .../emoji/unicode/1f680.png
white_check_mark  .../emoji/unicode/2705.png
```

这个数量会随着新 emoji 加入而变化，地址最后一段是码点，所以 `:tada:` 就是 U+1F389。

## 短代码在哪里会渲染

GitHub 是在渲染时替换的，把 `Text :smile: here` 分别用 `-f mode=gfm` 和 `-f mode=markdown` 发给 Markdown API，两次返回的都是 `<p>Text 😄 here</p>`，是 Unicode 字符，不是图片标签。

Pandoc 把它做成可选扩展，[手册](https://pandoc.org/MANUAL.html)里 `emoji` 的说明是 “Parses textual emojis like :smile: as Unicode emoticons”。在 Pandoc 3.13 里，`pandoc --list-extensions=gfm` 显示 `+emoji`，`pandoc --list-extensions=commonmark` 显示 `-emoji`，所以 `pandoc -f gfm` 会转换，`pandoc -f commonmark` 不会，gfm 读入后输出的是 `<span class="emoji" data-emoji="smile">😄</span>`。

## 该用哪一种

取舍在于文件里留下的是什么。

**短代码**保持 ASCII，`:white_check_mark:` 在任何编辑器和任何 diff 里都读得懂，字体缺这个字形也没关系，输入时也不用开选择器，代价是只有加了支持的地方才会渲染，而且每个工具各带一张名字表。

**Unicode 字符**没有依赖，编辑器里看到什么文件里就存什么，只要能显示文字的渲染器都能显示，用的是平台自己的字体，代价是源码里更难输入，也没法按名字搜索。

笔记只放在自己的文件夹里就直接输入字符，GitHub 上的 README 和 issue 两种都行，文字要经过好几个工具转换时字符更稳。想原样显示 `:tada:` 就放进代码片段，GitHub 和妙言都会放过代码片段和围栏代码块里的短代码。反斜杠在这里不管用，[转义字符](/zh/blog/markdown-escape-characters/)那篇讲过 `\:` 是合法的转义，但解析器去掉反斜杠后文字仍是 `:tada:`，替换照样发生，GitHub 的 Markdown API 对 `\:tada:` 和 `:tada\:` 返回的都是 🎉。

## 标题里的 emoji 和锚点

emoji 真正容易出问题的是这里。通过 `gh api repos/<owner>/<repo>/readme` 加上 HTML 媒体类型读公开仓库渲染后的 README，能拿到 GitHub 生成的 id，下面是两个 README 里的例子。

| 源码里的标题 | GitHub 生成的锚点 |
| --- | --- |
| `## 🌟 Preview` | `#-preview` |
| `### What's included 🚀` | `#whats-included-` |
| `## Quickstart 🛠️` | `#quickstart-` 后面跟一个看不见的字符 |

emoji 本身会从 id 里去掉，但它旁边的空格仍变成连字符，所以开头的 emoji 让锚点以连字符开头，结尾的 emoji 让锚点以连字符结尾。第三行是个坑，🛠️ 是扳手加 U+FE0F，也就是要求彩色样式的变体选择符，它被留在了 id 里，id 末尾三个字节是 `ef b8 8f`，手敲的 `#quickstart-` 看着一样，却和这个 id 对不上。

想避开这个问题，就别在要被链接的标题里放 emoji，或者在标题上方放一个 `<a name="..."></a>` 再链接过去，通用规则见[Markdown 链接和锚点](/zh/blog/markdown-links-and-anchors/)。

## 妙言 V4.9.0 怎么处理

妙言的预览会转换短代码。预览页加载了 `emoji.min.js`，是开源库 js-emoji 的一份拷贝，笔记渲染完成后 `common.js` 里的一个函数遍历文本节点，把库认识的 `:name:` 逐个替换成 Unicode 字符而不是图片，`:tada:` 显示出来就是系统 emoji 字体里的 🎉，`<code>` 和 `<pre>` 里面的内容会跳过。它在打开笔记时运行，分栏编辑时新插入的块也会再跑一遍，仓库里有一个单元测试断言这两种情况之后预览文本里都不再出现 `:smile:`。

导出 PDF 和图片截取的就是这份渲染好的预览，所以带着转换后的 emoji，切换演示用的也是同一个页面；妙言 PPT 按 `---` 分页，加载的是另一个页面，里面没有 js-emoji，幻灯片上的短代码会原样显示。

从源码能看出两个限制。名字表属于 js-emoji，不是 GitHub 的那张，文件里有 `tada`、`rocket`、`white_check_mark`、`memo`、`warning` 和 `+1`，没有 `octocat`、`shipit` 和 `bowtie`，库不认识的名字会保持原样，用冷门名字之前先试一下。转换也只发生在预览里，保存下来的 `.md` 里仍是 `:smile:`，别的应用打开这个文件看到的是短代码。

预览里的标题 id 是标题的可见文字，不是 GitHub 那种小写连字符的写法，用 Unicode 字符写的标题会把字符保留在 id 里，而短代码的替换在分配 id 之前进行，所以标题里写 `:tada:` 时 id 里也是 🎉。

想让 emoji 在文件里和其他工具里都保得住，就用上面的字符检视器输入字符。

## 常见问题

### `:smile:` 在所有 Markdown 里都能用吗？

不能。CommonMark 和 GFM 规范都没有定义它，Pandoc 只有启用 `emoji` 扩展才转换，`gfm` 默认开，`commonmark` 默认关。

### 怎么拿到 GitHub 的 emoji 名字列表？

运行 `gh api emojis`，返回的是名字和图片地址组成的 JSON。

### 为什么链接到带 emoji 的标题跳不过去？

GitHub 会从 id 里去掉 emoji，但保留它旁边空格变成的连字符，还可能保留一个看不见的变体选择符，从标题的链接图标上复制锚点，不要自己手敲。
