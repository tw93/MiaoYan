一个装着纯 Markdown 文件的文件夹，是 Claude Code、Codex 这类编程 Agent 最好上手的笔记格式，因为它们本来就会和文件打交道，列目录、用 grep 搜、读文件、改文件，不用接 API，不用导出，也不用配同步令牌。比较稳的开头是先给 Agent 一份副本，或者一个放在 git 里的文件夹，让它先读，改完用 diff 看一遍再决定留不留。

## 为什么纯文件适合 Agent

编程 Agent 是围着一个工作目录转的，它们用的工具就是开发者每天在用的那几样，列文件、搜文字、打开文件、写文件、跑命令，笔记文件夹不用任何转换就能放进这个循环。

- **读起来便宜。** `grep -rn "pricing" .` 能找出所有提到定价的笔记，带上行号，Agent 不需要数据库客户端或搜索接口，只读相关的三个文件就够了，不用把整个笔记库都读一遍。
- **写就是写文件。** 给 `Project plan.md` 加一节，和改源代码是同一个操作，改完不需要再导入一次。
- **结构本来就是文字。** 标题、列表、表格、front matter 和 `[[wikilink]]` 都是文件里的字符，Agent 看得见，也能原样保住，笔记开头那段元数据见 [Markdown front matter](/zh/blog/markdown-front-matter/)。
- **改动看得清。** 文本文件有逐行的 diff，用 git，或者拿一份副本跑 `diff -r`，就能看到 Agent 到底动了哪几行。

锁在应用数据库里的笔记，通常要先导出、走厂商的 API 或者装插件，Agent 才读得到。这和[本地优先的 Markdown 笔记](/zh/blog/local-first-markdown-notes/)给人的理由是同一个，文件比应用活得久，Agent 只是又一个从中受益的工具。

## 怎么安全地把文件夹交给 Agent

能访问文件的 Agent 就能改文件，这是它有用的地方，也是风险所在，所以要让每一次改动都看得见、退得回。

### 1. 先在副本上试

第一次之前，把笔记库复制一份，让 Agent 在副本里干活：

```bash
cp -R ~/Notes ~/Notes-agent-test
cd ~/Notes-agent-test
```

在这个目录里启动 Agent，出了问题就把副本删掉，某类任务用放心了，再换到真正的文件夹。

### 2. 把真正的文件夹放进 git

文件夹还不是仓库的话，在 Agent 碰它之前先建一个：

```bash
cd ~/Notes
git init
git add -A
git commit -m "notes before agent session"
```

之后 `git status` 能看到 Agent 改了哪些文件，`git diff` 能看到具体哪几行，`git restore <file>` 或 `git checkout -- .` 能把笔记恢复回去，看完 diff 觉得没问题再提交一次。

### 3. 先让它只读

开头先给不需要写任何东西的任务，比如「总结带 `project-x` 标签的笔记」「列出提到合同但 front matter 里没写日期的笔记」「找出链接到不存在标题的笔记」，答案有用了再让它改。真要改的时候点名是哪几个文件，并说清楚哪些东西不能动，比如 front matter、代码块和链接。

### 4. 知道它可能弄坏什么

- **Front matter。** 随手一改，笔记开头的 YAML 块可能被重新排版，甚至整段丢掉。
- **链接。** 改文件名或改标题会让指向它的 `[[wikilink]]` 和锚点失效，Agent 不主动去搜的话，看不到有哪些反向链接。
- **代码块和表格。** 没闭合的围栏会把预览里后面的内容全吞掉，表头和分隔行对不上的表格就不再是表格。
- **附件。** 只挪笔记不挪图片，图片路径就断了。
- **一次改太多。** 「把我的笔记都整理一下」是一次很难审的批量修改，一次给一个文件夹更好。

## 妙言 V4.9.0 能给 Agent 什么

妙言把每篇笔记存成你选的文件夹里的一个 `.md` 文件，所以上面说的文件夹就是你的笔记库，开源仓库里另有两样东西能帮上 Agent。

### miao 命令

`miao` 是一个 Bash 脚本，可以列出、搜索、打印、打开和新建笔记，除了 `help`，命令有 `list [folder]`、`search <query>`、`open <title|path>`、`cat <title|path>`、`new <title> [text]` 和 `update`。其中没有修改已有笔记的命令，所以 Agent 直接改文件。命令行怎么找到你的笔记库、有哪些例子，见[在终端里使用 Markdown 笔记](/zh/blog/markdown-notes-from-terminal/)。

### 妙言 Agent Skill

仓库在 `skills/miaoyan` 里带了一个 Skill，主体是 `SKILL.md`，README 说它用来教 Agent 妙言的语法、附件、PPT 写法和命令行用法，安装命令是：

```bash
npx skills add tw93/MiaoYan/skills/miaoyan -g
```

这个 Skill 是一套说明，不是连到应用上的插件，按 V4.9.0 里的内容，它要求 Agent：

- 先判断你要的是写笔记、做 PPT、整理笔记还是命令行操作，并沿用你的语言，不擅自翻译；
- 修改时保留已有的 front matter、围栏代码、行内代码、公式、链接、wikilink 和附件路径；
- 用不到妙言特有功能时退回标准的 GitHub Flavored Markdown，表格、任务列表、删除线和脚注是支持的扩展；
- 用 `[[准确的标题]]` 链接笔记，不带 `.md` 后缀，也不发明别名、标题或块引用的写法；
- 本地图片放在笔记所在文件夹下的 `i/` 里，写成 `/i/<filename>`，不用 `file://` 地址或绝对路径；
- 图用 `mermaid`、`plantuml`、`markmap` 围栏，公式用 `$...$` 和 `$$...$$`，提示框用 `> [!NOTE]` 这类 GitHub 标记，折叠用 `<details>`；
- 幻灯片之间用单独一行的 `---` 分隔，不在一页里把 `---` 当普通分割线；
- 只用真实存在的 `miao` 命令，不编造 `miao edit` 或 `miao append`，只有你要求时才跑 `miao update`，命令行找不到笔记库就设置 `MIAOYAN_PATH`，不猜私人文件夹，也不往你认可的笔记库之外写东西；
- 最后检查围栏是否闭合、路径是否有效、wikilink 目标是否准确、PPT 分隔符是否单独成行。

`SKILL.md` 旁边的 `skills/miaoyan/agents/openai.yaml` 里是这个 Skill 的显示名、一句简介和一条默认提示词。

Claude Code 自己的文档说，Skill 是放在一个文件夹里、带 YAML front matter 的 `SKILL.md`，对所有项目生效的放在 `~/.claude/skills/<skill-name>/`，只对一个仓库生效的放在仓库里的 `.claude/skills/<skill-name>/`。Claude 根据 `description` 判断什么时候用得上这个 Skill，真正用到时才加载正文。

## 应用开着的时候会怎样

Agent 改的正好是妙言正在显示的笔记时，应用监视着文件夹，会从磁盘重新加载这个文件。如果这时编辑器里的文字和文件不一样，妙言会先把你的版本写进笔记库根目录下隐藏的 `.miaoyan-conflicts` 文件夹，弹出一条「Changed on disk. Your version was backed up」的提示，再载入磁盘上的版本。

所以习惯很简单，Agent 在改某篇笔记时你别在里面打字，先切到别的笔记。妙言也会保留笔记的历史版本兜底，见 [Markdown 笔记的版本历史](/zh/blog/markdown-note-version-history/)，不过这些快照存在应用的支持目录里，不在你的笔记文件夹里，你自己能掌控的历史还是 git。

## 容易出的问题

- **Agent 写到了笔记库外面。** 在笔记目录里启动它，命令行那边明确设置 `MIAOYAN_PATH`，不要让脚本去猜。
- **标题重复。** `miao cat` 和 `miao open` 按准确标题取第一个匹配，标题有重复时给 Agent 一个路径，比如 `Projects/Plan`。
- **改的比要求的多。** 跑 `git diff`，恢复文件，再用更窄的要求重来一遍。
- **敏感笔记。** Agent 读到的内容都会进入这次会话，私人笔记放在一个不交给 Agent 的文件夹里。

## 常见问题

### 不装插件，Claude Code 或 Codex 能读我的笔记吗？

能，只要它们能打开这个文件夹。Markdown 笔记就是普通文件，文件工具加 `grep` 就够了，妙言的 Skill 只是让它们多懂一些应用的语法和命令行。

### 要把整个笔记文件夹都交给 Agent 吗？

一开始不要，先从副本或 git 仓库、只读任务、一次一个文件夹开始。
