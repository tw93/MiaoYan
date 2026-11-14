Notion 和 Evernote 都能把笔记导出来，但谁也不会直接给你一个整理好的 Markdown 文件夹。Notion 在导出窗口里就能选 Markdown 和 CSV，Evernote 导出的是 XML 格式的 ENEX，还得用 evernote2md 或 Yarle 这类转换工具转成 Markdown，最后一步都得自己来，看一遍导出的内容，改文件名和图片路径，再用能直接读写纯文件的编辑器打开这个文件夹。Apple 备忘录有自己的路线，见[把 Apple 备忘录导出为 Markdown](/zh/blog/apple-notes-to-markdown/)。

## 从 Notion 导出

打开页面，点右上角的 `•••`，选 `Export`，在导出窗口里选 `Markdown & CSV`。Notion 帮助页说，不是数据库的页面会变成 Markdown 文件，整页数据库会变成 CSV，每个子页面各有一个 Markdown 文件，标注块（Callout）因为 Markdown 里没有对应写法会导成 HTML，不过妙言的预览允许原始 HTML，照样能显示。想带上整棵页面树就勾上 `Include subpages`。

帮助页讲文件夹和资源时说的是 HTML 与 PDF 导出，包含子页面时解压后每个页面在自己的文件夹里，图片等资源单独存在其中，Markdown & CSV 它没有这么说，所以解压后先看一眼实际的目录再决定怎么清理。Windows 解压时遇到路径过长的报错，可以取消勾选 `Create folders for subpages`，或者换 7-Zip 之类的工具解压。

要导出整个工作区，打开 `Settings`，在 `Workspace` 下选 `General`，再点 `Export all workspace content`，只有桌面端和网页端能用，最长可能要 30 小时，下载链接发到邮箱，7 天后失效。

### Notion 会丢掉或改掉什么

- **数据库视图。** 导出数据库只给当前视图或默认视图，不能一次导出所有视图，表单视图也导不出，帮助页建议从 Table 视图导出回复。
- **数据库变成 CSV。** 每一行的属性在 CSV 里，页面正文是各自的 Markdown 文件，想让属性跟着笔记走，就得自己抄进 front matter（见下文）。
- **评论。** 帮助页只在 HTML 导出里提到评论，Markdown & CSV 里别指望有。
- **文件名。** 帮助页没有说导出文件怎么命名、会不会加标识符，以解压出来的文件夹为准，下面的改名脚本只会改匹配到的名字。

## 从 Evernote 导出

Evernote 帮助页说，导出只能在 Mac 或 Windows 的桌面版里做，网页版不行，免费账号也能导出。选中笔记本或几条笔记，右键选 `Export...`，格式有 ENEX、单页 HTML 和多页 HTML，再勾选要带上的属性（标签、创建日期、作者等），点 `Export`，文件会存到桌面。一次最多导出 100 条笔记，或者整个笔记本，ENEX 文件的大小上限可以在 300 MB 到 2 GB 之间选，属性会作为元数据存在 ENEX 或 HTML 文件里。

选 ENEX，下面两个转换工具读的都是它。两个工具里 evernote2md 是一条命令，Yarle 多一个桌面应用和更多选项。

### 用 evernote2md 转换

它的 README 给的安装方式是 `brew install evernote2md`，或者去 Releases 页面下载，命令格式是：

```bash
evernote2md [flags] [input] [outputDir]
```

输入可以是一个 `.enex` 文件、一个放着导出文件的目录，或者 `exports/My*.enex` 这样的通配符，不写输出目录就放在 `./notes`。每条笔记生成一个 Markdown 文件，图片放进 `image` 目录，PDF 等其他附件放进 `file` 目录，链接会保持正确，文件的创建和修改时间按笔记属性设置。标签会作为文字插进笔记，`--tagTemplate` 可以改写法，README 说 front matter 是可选的，举的例子是 Jekyll，其余参数用 `--help` 看。

```bash
evernote2md "Work.enex" ./work-notes
```

### 用 Yarle 转换

Yarle 有 Mac、Windows、Linux 的桌面应用，也能用命令行：

```bash
npx -p yarle-evernote-to-md@latest yarle --configFile ./config.json
```

选项都写在这个配置文件里，这次迁移用得上的有 `enexSources`（一个 `.enex` 文件或一个文件夹的绝对路径）、`outputDir`、放附件的 `resourcesDir`、要设成 `StandardMD` 而不是 `ObsidianMD` 的 `outputFormat`，还有 `useHashTags`。`nestedTags` 会把 `tag1_sub tag of tag1` 这样的标签写成 `tag1/sub-tag-of-tag1`，`replacementCharacterMap` 把文件名里不合法的字符换成 `_`。README 说要把标题、创建和更新时间、标签、来源和笔记本作为元数据写进笔记，得自己建一个模板，用 `templateFile` 指过去，不指定就用默认模板。README 对默认的附件文件夹前后不一致，示例配置里是 `resources`，正文里是 `_resources`，以实际输出为准。

### Evernote 会丢掉什么

Yarle 的 README 列出它处理的内容有文字、标签、链接、代码块、行内图片、附件和网页剪藏，两个 README 都没有承诺表格和复杂排版会转成什么样，所以先打开排版最复杂的几条笔记看看。Yarle 的 README 还提到，笔记重名会让笔记之间的链接转错，建议先建一条目录笔记，和整个笔记本一起导出。

## 清理文件夹

趁文件夹还小，能一眼检查完，在导入前做完。

**改文件名。** 妙言按去掉扩展名的文件名显示笔记，名字后面拖着什么，你看到的标题就是什么。如果 Notion 的文件名末尾带 32 位十六进制 ID，下面这个循环只会打印将要执行的改名，确认列表没问题后删掉 `echo`，`-n` 能避免重名时覆盖文件：

```bash
for f in *.md; do
  n=$(printf '%s' "$f" | sed -E 's/ [0-9a-f]{32}\.md$/.md/')
  [ "$n" != "$f" ] && echo mv -n "$f" "$n"
done
```

**把图片集中到一个文件夹。** 在笔记旁边建一个 `assets` 文件夹，把图片挪进去，再改链接。妙言预览会把不是绝对路径的地址按笔记所在的文件夹解析，并解码 `%20` 这类百分号编码，所以 `![](assets/photo.png)` 能用，带空格的文件夹名写成 `%20` 也找得到。以 `/` 开头但不是 `/i/` 的路径会被当成磁盘上的绝对路径，`/assets/photo.png` 找不到你的笔记文件夹，文件缺失时会显示一个写着 `Image Not Found` 的灰色方框，路径规则在[Markdown 图片怎么写](/zh/blog/markdown-images/)里讲了。evernote2md 生成的 `image` 和 `file` 文件夹可以原样保留，抽一条链接确认一下就行。

**把属性写成 front matter。** Notion 一行的属性，和 Evernote 笔记的标签、日期都是元数据，写在文件开头的 YAML 块里：

```markdown
---
title: Q3 plan
tags: [work, planning]
created: 2024-03-02
---
```

文件以 `---` 开头时，妙言会在预览和导出里隐藏这样的块。妙言 V4.9.0 不会把这些标签变成侧栏或筛选，所以把它当成留在文件里、给其他工具用的数据。语法和引号规则见 [Markdown front matter](/zh/blog/markdown-front-matter/)。

## 在妙言里打开

想把迁移好的文件夹当成笔记库，选妙言 > 设置…（Command-逗号），点笔记位置旁边的 `更改`，选中文件夹。妙言会检查它是不是可写的目录，不是就提示「无法使用这个文件夹」并保留原来的位置，选对之后会出现 `重新启动` 按钮，新文件夹下次启动才生效。

想把笔记加进已有的笔记库，用文件 > 导入，打开面板的提示是「选择要导入的 Markdown 文件或文件夹」，可以多选。扫描会递归进入文件夹，保留 `.md`、`.markdown` 和 `.txt` 文件，跳过隐藏项和名为 `i`、`files`、`.Trash` 的文件夹。导入只会把笔记文件按文件名复制进主笔记文件夹，不复制图片文件夹，也不保留原来的目录结构，名字重复时副本会叫 `Name Copy.md`，再重复是 `Name Copy 2.md`。笔记里有图片链接的话，图片文件夹要手动复制，或者改用笔记位置，链接才不会断，什么都没匹配到会弹出「没有可导入的 Markdown 文件」。

侧栏会隐藏只有附件文件、没有笔记也没有子文件夹的文件夹，以及没有直接放笔记的 `assets` 文件夹，所以只放图片的 `assets` 或 `image` 不会出现在列表里，文件还在磁盘上。为什么值得费这番功夫留下纯文件，见[本地优先的 Markdown 笔记](/zh/blog/local-first-markdown-notes/)。

## 常见问题

### Notion 的 Markdown 导出带图片吗？

帮助页说图片等资源单独保存，但这句话讲的是 HTML 和 PDF 导出，Markdown & CSV 没有说，解压后看一下文件夹。

### 不用桌面版能导出 Evernote 吗？

不能，帮助页说导出只能在 Mac 或 Windows 的桌面版里做。
