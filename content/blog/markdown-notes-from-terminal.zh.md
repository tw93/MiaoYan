妙言自带一个叫 `miao` 的小命令行工具，可以在终端里列出、搜索、打印、打开和新建笔记，一共六个命令（`open`、`new`、`search`、`list`、`cat`、`update`），不能编辑已有笔记。这是故意这样设计的，笔记本来就是纯 Markdown 文件，脚本或者 AI 编码 Agent 可以直接改文件，妙言会从磁盘读到变化。

## 安装和检查

安装脚本来自妙言仓库，只有一个文件：

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/MiaoYan/main/scripts/install.sh | bash
```

和所有管道安装一样，你可以先把脚本下载下来读一遍。它做四件事，解析最新的 GitHub release 标签，把该标签下的 `miaoyan` 脚本下载到 `~/.local/bin` 并命名为 `miao`，加上可执行权限，再在旁边建一个叫 `miaoyan` 的符号链接。如果 `~/.local/bin` 不在 `PATH` 里，它会把一行 `export PATH` 追加到 `~/.zshrc`、`~/.bashrc` 或 `~/.bash_profile`（取第一个存在的），并提醒你重新加载 shell。

用 `miao help` 检查安装，它会打印命令列表。这个 CLI 是 Bash 脚本，只支持 macOS，`new` 和 `open` 会调用 macOS 的 `open` 命令，标题编码用到 `python3`，两者都需要可用。

## 各个命令

```bash
miao list [folder]        # 顶层文件夹，或某个文件夹里的 Markdown 文件
miao search <query>       # 在终端里搜索笔记
miao cat <title|path>     # 打印笔记
miao open <title|path>    # 在妙言里打开笔记或文件夹
miao new <title> [text]   # 新建笔记
miao update               # 更新 CLI
```

**`miao list`** 不带参数时，打印笔记库里含有 Markdown 笔记的顶层文件夹。`miao list Projects` 打印该文件夹下直接包含的 Markdown 文件，路径相对于笔记库根目录。放在笔记库根目录的笔记默认不显示，CLI 会提示用 `miao list .` 把它们列出来。

**`miao search`** 以 `路径:行号:内容` 的形式打印匹配，路径相对于笔记库根目录。如果装了 ripgrep（`rg`）就用它做固定字符串匹配，查询里的特殊字符不会被当成正则，没有 ripgrep 则退回 `grep`，`Trash` 文件夹里的文件会被排除。没有匹配时会向标准错误输出「No matches found」并以非零状态退出。

**`miao cat`** 把整个文件连同 front matter 一起打印到标准输出，参数可以是路径、相对笔记库的路径或标题。标题按去掉 `.md` 的文件名匹配，完全一致的标题会解析到找到的第一个。

**`miao open`** 在妙言里打开解析到的文件或文件夹。参数不是路径时，退回到 `miaoyan://goto/<标题>` 这个地址，wikilink 走的也是这条路（见 [Wikilink 与反向链接](/zh/blog/wikilinks-and-backlinks/)）。

**`miao new`** 用标题和可选的正文拼出一个 `miaoyan://new/` 地址交给应用，所以要装有妙言。正文是第二个参数，记得加引号。

**`miao update`** 从妙言仓库 main 分支下载当前的 `miao` 脚本并替换已安装的，想更新 CLI 时再跑，不要把它当作脚本里的例行步骤。

## 它怎么找到你的笔记

CLI 不需要配置，但知道它怎么找笔记库，出问题时就好排查。

1. 如果设置了环境变量 `MIAOYAN_PATH`，就优先使用。
2. 否则通过 `defaults read com.tw93.miaoyan` 读取妙言在你选择文件夹时保存的 `storageUrl` 偏好设置。
3. 如果这样依然拿不到文件夹，再依次尝试 `~/Documents/MiaoYan`、`~/Save/MiaoYan` 和 `~/MiaoYan`。

都不存在时，它会打印「Error: Notes directory not found.」并提示设置 `MIAOYAN_PATH`。笔记库放在不常见的位置时，包括 CLI 不会去找的妙言自己的 iCloud 云盘文件夹，可以写进 shell 配置：

```bash
export MIAOYAN_PATH="$HOME/Notes"
```

## 示例

新建一篇带日期的日记，并写上第一行：

```bash
miao new "Journal $(date +%F)" "Morning plan: finish the draft."
```

列出提到某个短语的文件，每篇笔记只出现一次：

```bash
miao search "release checklist" | cut -d: -f1 | sort -u
```

打印某个文件夹里的所有笔记，比如交给别的工具：

```bash
miao list Projects | while read -r f; do
  echo "## $f"
  miao cat "$f"
done
```

统计一篇笔记的字数：

```bash
miao cat "Project plan" | wc -w
```

在应用里打开第一个搜索结果：

```bash
miao open "$(miao search 'quarterly review' | head -1 | cut -d: -f1)"
```

搜索输出的路径相对于笔记库根目录，`open` 和 `cat` 的路径形式也是相对它解析的，所以这些命令能拼在一起。

## 配合 AI 编码 Agent

笔记库是个文件夹，能读文件的 Agent 本来就能读你的笔记。CLI 的帮助在两处，`miao search` 和 `miao list` 让 Agent 不用遍历整棵目录树就能用很少的开销看清笔记库的结构，`miao open` 则把结果展示给你看。

妙言还发布了一个 Agent skill，教 Agent 认识妙言的语法，包括按精确标题写的 wikilink、放在 `i/` 文件夹里以 `/i/<文件名>` 引用的本地图片、数学公式和图表围栏、PPT 的分页符，以及 CLI 命令。安装方式：

```bash
npx skills add tw93/MiaoYan/skills/miaoyan -g
```

这个 skill 要求 Agent 只用真实存在的命令，不要自己编出 `miao edit` 或 `miao append`，CLI 找不到笔记库时设置 `MIAOYAN_PATH`，并且不能猜私人文件夹的位置，也不能写到你批准的笔记库之外。

编辑是文件层面的操作。如果 Agent 改了妙言里正打开的笔记，应用会从磁盘重新加载，要是编辑器里有不同的未保存文字，妙言会先把你的文字写进隐藏的 `.miaoyan-conflicts` 文件夹并提示你，不会悄悄丢掉。即便如此，让 Agent 改写某篇笔记之前，先切换到别的笔记，因为妙言在你离开一篇笔记时会为它保存一个历史版本，见 [Markdown 笔记的版本历史](/zh/blog/markdown-note-version-history/)。

## 常见故障

- **「Notes directory not found.」** 设置环境变量 `MIAOYAN_PATH`，或者先打开一次妙言，在偏好设置里选好文件夹。
- **两篇笔记同名。** `miao cat` 和 `miao open` 会把完全一致的标题解析到最先匹配的文件，遇到标题重复时改用 `Projects/Plan` 这样的相对路径即可。
- **`miao search` 结果太多或太少。** 有 ripgrep 时是字面字符串匹配，没有时 `grep` 会把查询当成模式。
- **`miao new` 好像没反应。** 它是交给应用处理的，检查是否装了妙言并允许它打开。
- **command not found。** 说明 `~/.local/bin` 不在当前 shell 的 `PATH` 里，重新打开一个终端窗口即可。

CLI 只是文件夹之上的一层便利。想知道这种设计为什么站得住，看 [本地优先的 Markdown 笔记](/zh/blog/local-first-markdown-notes/)。妙言 Mac 版在 [GitHub](https://github.com/tw93/MiaoYan) 开源，[App Store](https://apps.apple.com/app/id6759252269) 版本覆盖 Mac、iPhone 和 iPad。

## 常见问题

### CLI 能编辑或追加已有笔记吗？

不能，没有 edit 或 append 命令，用任何工具直接改文件，妙言会重新加载。

### CLI 支持 App Store 版吗？

支持，命令用法一样。它通过 `storageUrl` 偏好设置或默认文件夹找笔记库，找错或找不到时，把 `MIAOYAN_PATH` 设成你在应用里选的文件夹。

### 能在 Linux 上用吗？

不能，脚本调用了只有 macOS 才有的工具，应用本身也是 Mac 应用。
