想离开 Bear 又继续在 Mac 上写 Markdown，做法是先把笔记导出成 `.md` 文件，再用一个直接读普通文件的编辑器打开那个文件夹，妙言就是这样一个选择。文件夹就是分类，每篇笔记就是一个文件，把文件夹放在 iCloud Drive 里，iPhone 和 iPad 上也能打开同一份。代价也要说在前面，Bear 靠标签跨整个资料库组织笔记，妙言没有标签功能，如果你的笔记主要靠 `#标签` 找，搬之前先想好怎么改成文件夹。

## Bear 擅长什么

Bear 官方 FAQ 把标签比作话题标签，在笔记任何位置输入 `#tag` 就行，一篇笔记可以带任意多个标签，多个词的标签用一对井号包起来（`#vacation plans#`），用斜杠做嵌套（`#recipes/italian`），在侧边栏点一个标签，就能看到所有包含它的笔记。这和文件夹不是一个模型，因为一篇笔记可以同时挂在好几个标签下。

编辑器基于 CommonMark 规范，Markdown 指南里说格式会在笔记里显示出来而内容仍是纯文本，「Hide Markdown」在 Settings > General 里。它有 Mac 和 iOS 版本，Bear Web 用同一个 iCloud 账号，在主流浏览器里就能打开。

同步属于 Pro 功能。Bear 的 Pro 页面列出了 iCloud 同步、笔记加密、导出 PDF、HTML、DOCX 和 JPG、主题和 OCR 搜索。价格是每月 $2.99 或每年 $29.99，带 7 天试用（页面查看于 2026-10-19，价格会变，以官网为准）。同步页写明 Bear 用的是 CloudKit，而不是 iCloud Drive 里的文件。

## Bear 怎么存你的笔记

Bear 在 iOS 和 macOS 上都把笔记放在一个 SQLite 数据库里，Mac 上的位置是 `~/Library/Group Containers/9K33E3U3T4.net.shinyfrog.bear/Application Data/database.sqlite`。官方页面说只读访问数据库是安全的，建议多数用户不要改它，真要改就先复制一份并退出 Bear。

这是它和「一堆文件」最大的区别，Bear 里的笔记不是访达里看得见，也不是能直接用 `grep` 搜的文件。笔记还是你的，只是要走 Bear 的导出拿出来，而不是复制文件。

## 先把笔记导出来

免费版的 Bear 可以导出为纯文本、Markdown（`.md`）、Text Bundle、Bear Note 和 RTF，HTML、DOCX、PDF、JPEG 和 ePub 要 Pro，这次迁移用不上。

1. 在 Mac 版 Bear 里点侧边栏的「Notes」，按 ⌘A 全选。
2. 选 File > Export notes…（⇧⌘S），格式选 Markdown。
3. 保存到一个新建的空文件夹，比如 `~/Documents/BearExport`。
4. 想把标签留在文件里的话，导出前先在 Bear > Preferences > General 里勾上「Keep tags during export」。

Bear 的导出页没有说每种格式下附件怎么放，所以导出后挑一篇带图的笔记打开看看再放心，图丢了就再用 Text Bundle 导一次对比。

## 搬进妙言

妙言读的是一个装着 `.md`、`.markdown` 或 `.txt` 的文件夹，所以导入就是选文件夹。

1. 把导出的文件夹复制到你想放资料库的地方，比如 iCloud Drive 里的 `MiaoYan` 文件夹。
2. 按 ⌘, 打开偏好设置，找到「笔记位置」。
3. 点「更改」，选中那个文件夹，在重启提示里点「确定」，妙言启动时才加载资料库，取消提示则保留原来的文件夹。

子文件夹会变成侧边栏里的文件夹。Bear 没有文件夹，导出的多半是一个平铺列表，所以要自己建几个文件夹，再按原来最上层的标签把笔记拖进去。妙言按笔记所在文件夹解析相对图片路径，自己粘贴的图片会存成 `![name](/i/name.png)`，放在那个文件夹的 `i/` 目录里，搬完后打开几篇带图的笔记，把打不开的链接改掉，[Mac 上更轻的 Obsidian 替代品](/zh/blog/obsidian-alternative-mac/)那篇用 `rg` 做过同类清理。

## 妙言的模型有什么不同

妙言只把文件夹树当作结构，一篇笔记只在一个文件夹里，标题就是文件名，除了版本快照放在应用自己的支持目录，其余内容都在文件里。笔记之间用 `[[标题]]` 链接并带反向链接，见[Markdown 笔记里的 Wikilink 与反向链接](/zh/blog/wikilinks-and-backlinks/)。Bear 的导出页提到有一个「HTML Links」选项，会把笔记之间的 wiki 链接转成 HTML 链接，导出后可以检查一下链接还在不在。

iPhone 和 iPad 上，妙言没有账号也没有自己的同步服务，App 打开的是和 Mac 同一个 iCloud Drive 文件夹，文件由 iCloud 来搬。出问题时看[跨设备同步 Markdown 笔记的几种做法](/zh/blog/sync-markdown-notes-across-devices/)。

## Bear 更好的地方，以及你会失去什么

- **跨文件夹的标签。** 妙言没有，`#recipes` 你可以照样打在正文里并去搜，但它只是文字。
- **为写作做的移动端。** Bear 有原生的 iPhone 和 iPad 版，FAQ 里写了 iPadOS 键盘快捷键，妙言的 iPhone 和 iPad 版是先进入阅读，点编辑按钮才切到编辑器，也没有自己的键盘快捷键。
- **小组件、Apple Watch 和快捷指令。** Bear 的 FAQ 列了这些，妙言的页面没有提到。
- **PDF、DOCX、JPG 导出。** 在 Bear 里属于 Pro，妙言有自己的 PDF 路径，见 [在 Mac 上把 Markdown 转成 PDF](/zh/blog/markdown-to-pdf-mac/)，没有 DOCX。
- **一篇笔记放在多个位置。** 妙言里一篇笔记只在一个文件夹里。

得到的是一个不依赖任何 App 的资料库，文件能被任何编辑器打开，备份就是复制文件夹，同步也不用 Pro，用你本来就在用的网盘就行。妙言在 Mac 上还能渲染 LaTeX、Mermaid、PlantUML 和 Markmap，Bear 的 Markdown 指南没有提到这些。

## 什么时候留在 Bear

标签是你找笔记的主要方式，主要在 iPhone 上随手记，或者喜欢那种带样式的单栏编辑器，就留在 Bear。想要基于文件夹的 Mac 编辑器，或者想先试试纯文件再决定，可以读[Mac 上怎么选 Markdown 编辑器](/zh/blog/markdown-editor-for-mac/)，里面比较了几个主流选择，[本地优先的 Markdown 笔记怎么管](/zh/blog/local-first-markdown-notes/)讲了为什么一个普通文件夹值得这点取舍。

迁移可以放心试，导出不会改动 Bear 里的任何内容，保留 Bear，导出一次，在妙言里打开副本，两边用上一周再决定。

## 常见问题

### Bear 免费版能把全部笔记导出成 Markdown 吗？

可以。免费版支持导出 Markdown、纯文本、Text Bundle、Bear Note 和 RTF，全选笔记后用 File > Export notes…（⇧⌘S）。

### 妙言支持 Bear 的 #标签吗？

不支持。笔记里的 `#tag` 只是文字，文件夹是唯一的组织方式，搬之前或之后把主要的标签改成文件夹。

### 能直接读 Bear 的数据库吗？

Mac 上可以只读打开那个 SQLite 文件，Bear 说只读是安全的，不过官方支持的路径是导出，iOS 上数据库不对外开放。

### 搬完以后笔记会同步到 iPhone 和 iPad 吗？

资料库文件夹在 iCloud Drive 里就会，妙言的 iPhone 和 iPad 版打开的是同一个文件夹，同步由 iCloud 完成。
