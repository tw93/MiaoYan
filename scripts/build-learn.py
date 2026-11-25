#!/usr/bin/env python3
"""Learn Markdown, Markdown 闯关: /learn/ and /zh/learn/.

Twenty-six levels, each one way of writing Markdown: the lesson on top, the
editor on the left, the reader's text drawn in MiaoYan's preview in the middle
and the goal on the right. A level is done when the two draw the same blocks
(assets/tools/learn.js compares what markdown-it builds, not the text, so
`*a*` and `_a_` both pass). Progress stays in the browser.

    python3 -I scripts/build-learn.py          # write the pages
    python3 -I scripts/build-learn.py --check  # fail on stale output
"""

import importlib.util
import json
import pathlib
import re
import sys

import markdown

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "content" / "learn"

_spec = importlib.util.spec_from_file_location("build_tools", ROOT / "scripts" / "build-tools.py")
bt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bt)
site = bt.site
mermaid_assets = bt.mermaid_assets
esc = site.esc
SITE = site.SITE
LANGS = ("en", "zh")

CHAPTERS = {
    "text": {"en": "Text", "zh": "文字"},
    "structure": {"en": "Structure", "zh": "结构"},
    "blocks": {"en": "Code and tables", "zh": "代码与表格"},
    "math": {"en": "Math and diagrams", "zh": "公式与图"},
}

# Each level: chapter, title, the lesson (backticks become code, [a](b) a
# link), a hint, the text it starts from, the answer it must draw the same as,
# and its row in the syntax table under the game (code, or ("text", words)).
LEVELS = [
    {
        "id": "heading", "chapter": "text",
        "title": {"en": "Headings", "zh": "标题"},
        "text": {
            "en": "Start a line with `#` and a space and it becomes a level 1 heading, usually one per note. Make the line below a level 1 heading.",
            "zh": "行首写一个 `#` 再空一格，这一行就是一级标题，一篇笔记通常只有一个。把下面这行变成一级标题。",
        },
        "hint": {"en": "Put a space between `#` and the text.", "zh": "`#` 和文字之间要有一个空格。"},
        "start": {"en": "Weekend reading notes", "zh": "周末读书笔记"},
        "answer": {"en": "# Weekend reading notes", "zh": "# 周末读书笔记"},
        "syntax": {"en": "# Heading", "zh": "# 标题"},
    },
    {
        "id": "subheading", "chapter": "text",
        "title": {"en": "Subheadings", "zh": "小标题"},
        "text": {
            "en": "`##` makes a level 2 heading and `###` a level 3, more marks for a lower level. Make “Still to do” and “A few numbers” level 2 headings.",
            "zh": "`##` 是二级标题，`###` 是三级，井号越多级别越低。把“还要做的事”和“几个数字”变成二级标题。",
        },
        "hint": {"en": "Start both lines with `## `.", "zh": "两行开头都写 `## `。"},
        "start": {"en": "# Weekend reading notes\n\nStill to do\n\nA few numbers", "zh": "# 周末读书笔记\n\n还要做的事\n\n几个数字"},
        "answer": {"en": "# Weekend reading notes\n\n## Still to do\n\n## A few numbers", "zh": "# 周末读书笔记\n\n## 还要做的事\n\n## 几个数字"},
        "syntax": {"en": "## Subheading", "zh": "## 小标题"},
    },
    {
        "id": "paragraphs", "chapter": "text",
        "title": {"en": "Paragraphs", "zh": "分段"},
        "text": {
            "en": "A single line break keeps two sentences in one paragraph, a blank line starts a new one. Split the two sentences below into two paragraphs.",
            "zh": "只换一行，两句还在同一段里，中间空一行才是新的一段。把下面两句分成两段。",
        },
        "hint": {"en": "Press Return once more between them.", "zh": "在两句之间多按一次回车。"},
        "start": {"en": "I finished part two this week.\nThis weekend I want to tidy my notes.", "zh": "这周读完了第二部分。\n周末想把笔记整理一下。"},
        "answer": {"en": "I finished part two this week.\n\nThis weekend I want to tidy my notes.", "zh": "这周读完了第二部分。\n\n周末想把笔记整理一下。"},
        "syntax": {"en": ("text", "A blank line between paragraphs"), "zh": ("text", "段落之间空一行")},
    },
    {
        "id": "bold", "chapter": "text",
        "title": {"en": "Bold", "zh": "加粗"},
        "text": {
            "en": "Two asterisks on each side make text bold, `**like this**`. Make “part three” bold.",
            "zh": "两边各加两个星号就是加粗，`**像这样**`。把“第三部分”加粗。",
        },
        "hint": {"en": "You can also select the words and press `⌘B`.", "zh": "也可以选中文字按 `⌘B`。"},
        "start": {"en": "The best part of the book is part three.", "zh": "这本书最值得读的是第三部分。"},
        "answer": {"en": "The best part of the book is **part three**.", "zh": "这本书最值得读的是**第三部分**。"},
        "syntax": {"en": "**bold**", "zh": "**加粗**"},
    },
    {
        "id": "italic", "chapter": "text",
        "title": {"en": "Italics", "zh": "斜体"},
        "text": {
            "en": "One asterisk on each side makes italics, `*like this*`, and underscores work too. Put “never” in italics.",
            "zh": "两边各加一个星号是斜体，`*像这样*`。把“并不是”变成斜体。",
        },
        "hint": {"en": "Select the word and press `⌘I`.", "zh": "选中后按 `⌘I`。"},
        "start": {"en": "History is never a straight line.", "zh": "历史并不是一条直线。"},
        "answer": {"en": "History is *never* a straight line.", "zh": "历史*并不是*一条直线。"},
        "syntax": {"en": "*italics*", "zh": "*斜体*"},
    },
    {
        "id": "strike", "chapter": "text",
        "title": {"en": "Strikethrough", "zh": "删除线"},
        "text": {
            "en": "Two tildes `~~` on each side strike text through, handy for a change of plan. Strike out “Saturday”.",
            "zh": "两边各加两个波浪线 `~~` 是删除线，适合划掉改了主意的地方。把“周六”划掉。",
        },
        "hint": {"en": "Keep `~~` right against the word.", "zh": "`~~` 要紧贴着文字。"},
        "start": {"en": "Return the books on Saturday Sunday.", "zh": "周六周日去图书馆还书。"},
        "answer": {"en": "Return the books on ~~Saturday~~ Sunday.", "zh": "~~周六~~周日去图书馆还书。"},
        "syntax": {"en": "~~struck~~", "zh": "~~删除线~~"},
    },
    {
        "id": "code", "chapter": "text",
        "title": {"en": "Inline code", "zh": "行内代码"},
        "text": {
            "en": "Wrap text in backticks, the key under Esc, for inline code: commands, file names and shortcuts read best this way. Mark git status as code.",
            "zh": "用反引号包起来是行内代码，反引号在 Esc 下面，命令、文件名和快捷键都适合这样写。把 git status 标成代码。",
        },
        "hint": {"en": "One backtick on each side.", "zh": "两边各一个反引号。"},
        "start": {"en": "Type git status in Terminal to see what changed.", "zh": "在终端里输入 git status 看看改了什么。"},
        "answer": {"en": "Type `git status` in Terminal to see what changed.", "zh": "在终端里输入 `git status` 看看改了什么。"},
        "syntax": {"en": "`code`", "zh": "`代码`"},
    },
    {
        "id": "link", "chapter": "text",
        "title": {"en": "Links", "zh": "链接"},
        "text": {
            "en": "Put the text in square brackets and the address in parentheses right after, `[MiaoYan](https://miaoyan.app)`. Link “MiaoYan's site” to `https://miaoyan.app`.",
            "zh": "方括号里写文字，紧跟着的圆括号里写地址，`[妙言](https://miaoyan.app)`。把“妙言官网”做成指向 `https://miaoyan.app` 的链接。",
        },
        "hint": {"en": "No space between `]` and `(`.", "zh": "方括号和圆括号之间不能有空格。"},
        "start": {"en": "Take a look at MiaoYan's site sometime.", "zh": "有空去妙言官网看看。"},
        "answer": {"en": "Take a look at [MiaoYan's site](https://miaoyan.app) sometime.", "zh": "有空去[妙言官网](https://miaoyan.app)看看。"},
        "syntax": {"en": "[text](https://…)", "zh": "[文字](https://…)"},
    },
    {
        "id": "text-review", "chapter": "text",
        "title": {"en": "Review", "zh": "小结"},
        "text": {
            "en": "Put the chapter together: a level 1 heading, two paragraphs, bold, italics and a link to `https://miaoyan.app/blog/`, laid out like the goal.",
            "zh": "把这一章用上：一级标题、分段、加粗、斜体，再加一个指向 `https://miaoyan.app/zh/blog/` 的链接，排成目标的样子。",
        },
        "hint": {
            "en": "Split the paragraphs first, then mark one thing at a time. The tinted blocks in the preview are the ones that still differ.",
            "zh": "先分段，再一处处加标记，预览里底色变深的地方就是还不一样的。",
        },
        "start": {
            "en": "Reading club\nThis Saturday at 3 pm, in the second floor room.\nBring your own notes, past notes are here.",
            "zh": "读书会通知\n这周六下午三点，在二楼会议室。\n记得带上自己的笔记，往期笔记在这里。",
        },
        "answer": {
            "en": "# Reading club\n\nThis Saturday at 3 pm, in the **second floor room**.\n\nBring *your own notes*, past notes are [here](https://miaoyan.app/blog/).",
            "zh": "# 读书会通知\n\n这周六下午三点，在**二楼会议室**。\n\n记得带上*自己的笔记*，往期笔记在[这里](https://miaoyan.app/zh/blog/)。",
        },
        "syntax": None,
    },
    {
        "id": "list", "chapter": "structure",
        "title": {"en": "Lists", "zh": "列表"},
        "text": {
            "en": "Start each line with `-` and a space for a list item. Turn the three things below into a list.",
            "zh": "每行开头写 `-` 加空格，就是一个列表项。把下面三样变成列表。",
        },
        "hint": {"en": "Every line starts with `- `. In MiaoYan, Return after an item starts the next one for you.", "zh": "每一行都以 `- ` 开头，在妙言里写完一项按回车，下一行会自动接上。"},
        "start": {"en": "Milk\nBread\nEggs", "zh": "牛奶\n面包\n鸡蛋"},
        "answer": {"en": "- Milk\n- Bread\n- Eggs", "zh": "- 牛奶\n- 面包\n- 鸡蛋"},
        "syntax": {"en": "- Item", "zh": "- 列表项"},
    },
    {
        "id": "ordered", "chapter": "structure",
        "title": {"en": "Numbered lists", "zh": "编号列表"},
        "text": {
            "en": "Start with `1.` and a space for a numbered list; the numbers count on in order even if you write them wrong. Number the three steps.",
            "zh": "用 `1.` 加空格开头是编号列表，后面的数字写错了也会按顺序排。给三个步骤编上号。",
        },
        "hint": {"en": "Writing `1.` on every line works too.", "zh": "每行都写 `1.` 也可以。"},
        "start": {"en": "Open MiaoYan\nCreate a note\nStart writing", "zh": "打开妙言\n新建一篇笔记\n开始写"},
        "answer": {"en": "1. Open MiaoYan\n2. Create a note\n3. Start writing", "zh": "1. 打开妙言\n2. 新建一篇笔记\n3. 开始写"},
        "syntax": {"en": "1. Step", "zh": "1. 第一步"},
    },
    {
        "id": "nested", "chapter": "structure",
        "title": {"en": "Nested lists", "zh": "嵌套列表"},
        "text": {
            "en": "Indent an item further than the one above, two spaces or one Tab, and it hangs under it. Put Apples and Bananas under Fruit.",
            "zh": "把一项往里缩进，比上一项多两个空格或者按一下 Tab，它就挂到上一项下面。让苹果和香蕉成为水果的子项。",
        },
        "hint": {"en": "Press Tab at the start of the Apples and Bananas lines.", "zh": "在苹果和香蕉那两行开头按 Tab。"},
        "start": {"en": "- Fruit\n- Apples\n- Bananas\n- Vegetables", "zh": "- 水果\n- 苹果\n- 香蕉\n- 蔬菜"},
        "answer": {"en": "- Fruit\n  - Apples\n  - Bananas\n- Vegetables", "zh": "- 水果\n  - 苹果\n  - 香蕉\n- 蔬菜"},
        "syntax": {"en": "  - Sub-item", "zh": "  - 子项"},
    },
    {
        "id": "tasks", "chapter": "structure",
        "title": {"en": "Task lists", "zh": "待办"},
        "text": {
            "en": "`[ ]` after the dash makes an open task and `[x]` a finished one. Turn the list into tasks, the first one already done.",
            "zh": "在 `-` 后面写 `[ ]` 是没做的待办，`[x]` 是做完的。把下面变成待办，第一项已经做完。",
        },
        "hint": {"en": "A space inside the brackets for an open task, `x` for a done one.", "zh": "没做的方括号中间是一个空格，做完的写 `x`。"},
        "start": {"en": "- Finish part three\n- Tidy the notes\n- Write a short review", "zh": "- 读完第三部分\n- 整理笔记\n- 写短评"},
        "answer": {"en": "- [x] Finish part three\n- [ ] Tidy the notes\n- [ ] Write a short review", "zh": "- [x] 读完第三部分\n- [ ] 整理笔记\n- [ ] 写短评"},
        "syntax": {"en": "- [ ] Task", "zh": "- [ ] 待办"},
    },
    {
        "id": "quote", "chapter": "structure",
        "title": {"en": "Quotes", "zh": "引用"},
        "text": {
            "en": "Start a line with `>` and a space and the paragraph becomes a quote, right for a line from a book. Make the sentence a quote.",
            "zh": "行首写 `>` 加空格，这一段就是引用，摘抄书里的话正合适。把这句变成引用。",
        },
        "hint": {"en": "A space after `>`.", "zh": "`>` 后面空一格。"},
        "start": {"en": "History is never a straight line, so take your time before drawing conclusions.", "zh": "历史从来不是一条直线，读的时候最好也别急着下结论。"},
        "answer": {"en": "> History is never a straight line, so take your time before drawing conclusions.", "zh": "> 历史从来不是一条直线，读的时候最好也别急着下结论。"},
        "syntax": {"en": "> Quote", "zh": "> 引用"},
    },
    {
        "id": "rule", "chapter": "structure",
        "title": {"en": "Dividers", "zh": "分割线"},
        "text": {
            "en": "`---` alone on a line draws a divider. Leave a blank line above it, or the line of text over it turns into a heading. In MiaoYan's slides it also starts the next slide. Put a divider between the two paragraphs.",
            "zh": "单独一行写 `---` 是一条分割线，上面要空一行，紧贴在文字下面会把那行变成标题，在妙言的 PPT 里它还是翻到下一页的记号。在两段中间加一条分割线。",
        },
        "hint": {"en": "A blank line before and after `---`.", "zh": "`---` 的上下都留一个空行。"},
        "start": {"en": "First half done.\n\nSecond half tomorrow.", "zh": "上半场读完了。\n\n下半场明天继续。"},
        "answer": {"en": "First half done.\n\n---\n\nSecond half tomorrow.", "zh": "上半场读完了。\n\n---\n\n下半场明天继续。"},
        "syntax": {"en": "---", "zh": "---"},
    },
    {
        "id": "structure-review", "chapter": "structure",
        "title": {"en": "Review", "zh": "小结"},
        "text": {
            "en": "“Weekend plan” is a level 2 heading, “To buy” and “To do” level 3, the shopping is numbered, the first task is done and the last line is a quote.",
            "zh": "“周末计划”是二级标题，“要买的”和“要做的”是三级标题，要买的东西编上号，第一项待办已经做完，最后一句是引用。",
        },
        "hint": {
            "en": "Leave a blank line between a heading and the list under it.",
            "zh": "标题和下面的列表之间空一行。",
        },
        "start": {
            "en": "Weekend plan\nTo buy\nMilk\nBread\nTo do\nFinish part three\nWrite a short review\nRead slowly, no rush.",
            "zh": "周末计划\n要买的\n牛奶\n面包\n要做的\n读完第三部分\n写短评\n慢慢读，不着急。",
        },
        "answer": {
            "en": "## Weekend plan\n\n### To buy\n\n1. Milk\n2. Bread\n\n### To do\n\n- [x] Finish part three\n- [ ] Write a short review\n\n> Read slowly, no rush.",
            "zh": "## 周末计划\n\n### 要买的\n\n1. 牛奶\n2. 面包\n\n### 要做的\n\n- [x] 读完第三部分\n- [ ] 写短评\n\n> 慢慢读，不着急。",
        },
        "syntax": None,
    },
    {
        "id": "fence", "chapter": "blocks",
        "title": {"en": "Code blocks", "zh": "代码块"},
        "text": {
            "en": "A line of three backticks ```` ``` ```` above and below makes a code block, and a language name after the opening backticks colours it. Put this Python in a code block marked `python`.",
            "zh": "上下各一行三个反引号 ```` ``` ```` 围起来是代码块，开头的反引号后面写上语言名会按语言着色。把这段 Python 放进代码块，标上 `python`。",
        },
        "hint": {"en": "The first line is ```` ```python ```` and the last ```` ``` ````.", "zh": "第一行写 ```` ```python ````，最后一行写 ```` ``` ````。"},
        "start": {"en": "def words(text):\n    return len(text.split())", "zh": "def words(text):\n    return len(text.split())"},
        "answer": {"en": "```python\ndef words(text):\n    return len(text.split())\n```", "zh": "```python\ndef words(text):\n    return len(text.split())\n```"},
        "syntax": {"en": "```python", "zh": "```python"},
    },
    {
        "id": "table", "chapter": "blocks",
        "title": {"en": "Tables", "zh": "表格"},
        "text": {
            "en": "Vertical bars `|` separate the cells, and a second row of `---` divides the header from the rest. Make a two-column table with the first line as its header.",
            "zh": "用竖线 `|` 隔开每一格，第二行写 `---` 把表头和内容分开。把下面做成两列的表格，第一行是表头。",
        },
        "hint": {
            "en": "Each row is `| a | b |`, and the second row is `| --- | --- |`. The [Markdown table generator](/tools/markdown-table-generator/) writes bigger ones for you.",
            "zh": "每一行写成 `| a | b |`，第二行是 `| --- | --- |`，大一点的表格可以用 [Markdown 表格生成器](/zh/tools/markdown-table-generator/) 来做。",
        },
        "start": {
            "en": "Event, Years ago\nCognitive revolution, 70000\nAgricultural revolution, 12000",
            "zh": "事件，距今\n认知革命，7 万年\n农业革命，1.2 万年",
        },
        "answer": {
            "en": "| Event | Years ago |\n| --- | --- |\n| Cognitive revolution | 70000 |\n| Agricultural revolution | 12000 |",
            "zh": "| 事件 | 距今 |\n| --- | --- |\n| 认知革命 | 7 万年 |\n| 农业革命 | 1.2 万年 |",
        },
        "syntax": {"en": "| A | B |", "zh": "| 表头 | 表头 |"},
    },
    {
        "id": "align", "chapter": "blocks",
        "title": {"en": "Column alignment", "zh": "表格对齐"},
        "text": {
            "en": "Colons in the `---` row set the alignment: `:---` left, `:---:` centred, `---:` right. Align the Years ago column right.",
            "zh": "在 `---` 那一行加冒号决定对齐，`:---` 靠左，`:---:` 居中，`---:` 靠右。让“距今”这一列靠右。",
        },
        "hint": {"en": "Change the second cell of the second row to `---:`.", "zh": "把第二行的第二格改成 `---:`。"},
        "start": {
            "en": "| Event | Years ago |\n| --- | --- |\n| Cognitive revolution | 70000 |\n| Agricultural revolution | 12000 |",
            "zh": "| 事件 | 距今 |\n| --- | --- |\n| 认知革命 | 7 万年 |\n| 农业革命 | 1.2 万年 |",
        },
        "answer": {
            "en": "| Event | Years ago |\n| --- | ---: |\n| Cognitive revolution | 70000 |\n| Agricultural revolution | 12000 |",
            "zh": "| 事件 | 距今 |\n| --- | ---: |\n| 认知革命 | 7 万年 |\n| 农业革命 | 1.2 万年 |",
        },
        "syntax": {"en": "| :---: | ---: |", "zh": "| :---: | ---: |"},
    },
    {
        "id": "image", "chapter": "blocks",
        "title": {"en": "Images", "zh": "图片"},
        "text": {
            "en": "An image is a link with an exclamation mark in front, `![caption](address)`, the brackets holding what the picture shows. Add the image at `/assets/shots/en-preview-1400.webp` with the caption “MiaoYan preview”.",
            "zh": "图片和链接很像，前面多一个感叹号，`![说明](地址)`，方括号里写图片说明。插入地址为 `/assets/shots/zh-preview-1400.webp` 的图片，说明写“妙言预览”。",
        },
        "hint": {"en": "Keep the `/` at the start of the address, and the `!` right against `[`.", "zh": "地址开头的 `/` 别漏了，感叹号要紧贴着方括号。"},
        "start": {"en": "This is MiaoYan's preview:\n\n", "zh": "妙言的预览长这样：\n\n"},
        "answer": {
            "en": "This is MiaoYan's preview:\n\n![MiaoYan preview](/assets/shots/en-preview-1400.webp)",
            "zh": "妙言的预览长这样：\n\n![妙言预览](/assets/shots/zh-preview-1400.webp)",
        },
        "syntax": {"en": "![caption](address)", "zh": "![说明](地址)"},
    },
    {
        "id": "escape", "chapter": "blocks",
        "title": {"en": "Escaping", "zh": "转义"},
        "text": {
            "en": "To show a mark such as `*` as it is, put a backslash `\\` in front of it. Make the asterisks below show up instead of making italics.",
            "zh": "想让星号这类符号原样显示，在它前面加一个反斜杠 `\\`。让下面的星号原样显示，不变成斜体。",
        },
        "hint": {"en": "Both asterisks need a `\\`.", "zh": "两个星号前面都要加 `\\`。"},
        "start": {"en": "*Asterisks* are Markdown marks.", "zh": "*星号* 是 Markdown 的标记。"},
        "answer": {"en": "\\*Asterisks\\* are Markdown marks.", "zh": "\\*星号\\* 是 Markdown 的标记。"},
        "syntax": {"en": "\\*", "zh": "\\*"},
    },
    {
        "id": "blocks-review", "chapter": "blocks",
        "title": {"en": "Review", "zh": "小结"},
        "text": {
            "en": "“Everyday commands” is a level 2 heading, the table's commands are inline code, and the last two lines go in a code block marked `bash`.",
            "zh": "“常用命令”是二级标题，表格里的命令写成行内代码，最后两行放进标着 `bash` 的代码块。",
        },
        "hint": {"en": "Leave a blank line between the table and the code block.", "zh": "表格和代码块之间空一行。"},
        "start": {
            "en": "Everyday commands\nCommand, What it does\ngit status, See what changed\ngit diff, See which lines changed\ngit add .\ngit commit -m \"Update notes\"",
            "zh": "常用命令\n命令，作用\ngit status，看改了什么\ngit diff，看改了哪几行\ngit add .\ngit commit -m \"更新笔记\"",
        },
        "answer": {
            "en": "## Everyday commands\n\n| Command | What it does |\n| --- | --- |\n| `git status` | See what changed |\n| `git diff` | See which lines changed |\n\n```bash\ngit add .\ngit commit -m \"Update notes\"\n```",
            "zh": "## 常用命令\n\n| 命令 | 作用 |\n| --- | --- |\n| `git status` | 看改了什么 |\n| `git diff` | 看改了哪几行 |\n\n```bash\ngit add .\ngit commit -m \"更新笔记\"\n```",
        },
        "syntax": None,
    },
    {
        "id": "math", "chapter": "math",
        "title": {"en": "Formulas", "zh": "公式"},
        "text": {
            "en": "LaTeX between two `$` is an inline formula, and `^` raises what follows. Write the Pythagorean theorem as a formula.",
            "zh": "两个 `$` 中间写 LaTeX 就是行内公式，`^` 是上标。把勾股定理写成公式。",
        },
        "hint": {"en": "Keep each `$` right against the formula, with no space inside.", "zh": "`$` 紧贴着公式，里面开头结尾不要留空格。"},
        "start": {"en": "Pythagoras: a^2 + b^2 = c^2", "zh": "勾股定理：a^2 + b^2 = c^2"},
        "answer": {"en": "Pythagoras: $a^2 + b^2 = c^2$", "zh": "勾股定理：$a^2 + b^2 = c^2$"},
        "syntax": {"en": "$a^2$", "zh": "$a^2$"},
    },
    {
        "id": "math-block", "chapter": "math",
        "title": {"en": "Display formulas", "zh": "公式块"},
        "text": {
            "en": "A formula on its own lines between two `$$` lines is drawn larger and centred. Make this growth formula a display formula; `_0` is a subscript.",
            "zh": "单独成行的公式上下各写一行 `$$`，会居中放大显示。把这个增长公式写成公式块，`_0` 是下标。",
        },
        "hint": {"en": "`$$` on the first line, the formula, `$$` on the last.", "zh": "第一行 `$$`，中间是公式，最后一行 `$$`。"},
        "start": {"en": "N(t) = N_0 e^{rt}", "zh": "N(t) = N_0 e^{rt}"},
        "answer": {"en": "$$\nN(t) = N_0 e^{rt}\n$$", "zh": "$$\nN(t) = N_0 e^{rt}\n$$"},
        "syntax": {"en": "$$", "zh": "$$"},
    },
    {
        "id": "mermaid", "chapter": "math",
        "title": {"en": "Diagrams", "zh": "流程图"},
        "text": {
            "en": "Mark a code block `mermaid` and its text is drawn as a diagram, `-->` drawing an arrow. Put this in a mermaid block and add a step: Notes points to Review.",
            "zh": "代码块的语言写成 `mermaid`，里面的文字就会画成图，`-->` 是箭头。把这段放进 mermaid 代码块，再加一步，做笔记指向写短评。",
        },
        "hint": {"en": "Add a line `B --> C[Review]`.", "zh": "加一行 `B --> C[写短评]`。"},
        "start": {"en": "flowchart LR\n  A[Read] --> B[Notes]", "zh": "flowchart LR\n  A[读书] --> B[做笔记]"},
        "answer": {
            "en": "```mermaid\nflowchart LR\n  A[Read] --> B[Notes]\n  B --> C[Review]\n```",
            "zh": "```mermaid\nflowchart LR\n  A[读书] --> B[做笔记]\n  B --> C[写短评]\n```",
        },
        "syntax": {"en": "```mermaid", "zh": "```mermaid"},
    },
    {
        "id": "final", "chapter": "math",
        "title": {"en": "The whole note", "zh": "整篇笔记"},
        "text": {
            "en": "The last level uses everything: two heading levels, bold, a finished task, a table with its second column on the right, a quote and a formula. Lay the draft out like the goal.",
            "zh": "最后一关，把学过的都用上：两级标题、加粗、做完的待办、第二列靠右的表格、引用和公式，把这份草稿排成目标的样子。",
        },
        "hint": {"en": "Work from the top down; each tinted block in the preview is the next thing to fix.", "zh": "从上往下一块块来，预览里底色变深的就是下一处要改的。"},
        "start": {
            "en": "Weekend reading notes\nNotes from the second half of Sapiens, part three is the best.\nStill to do\nFinish part three\nTidy the numbers from the book\nA few numbers\nEvent, Years ago\nCognitive revolution, 70000\nAgricultural revolution, 12000\nHistory is never a straight line.\nPopulation grows as N_0 e^{rt}.",
            "zh": "周末读书笔记\n读《人类简史》后半本时记下的几个地方，第三部分最值得读。\n还要做的事\n读完第三部分\n整理书里的几个数字\n几个数字\n事件，距今\n认知革命，7 万年\n农业革命，1.2 万年\n历史从来不是一条直线。\n人口按 N_0 e^{rt} 增长。",
        },
        "answer": {
            "en": "# Weekend reading notes\n\nNotes from the second half of Sapiens, **part three** is the best.\n\n## Still to do\n\n- [x] Finish part three\n- [ ] Tidy the numbers from the book\n\n## A few numbers\n\n| Event | Years ago |\n| --- | ---: |\n| Cognitive revolution | 70000 |\n| Agricultural revolution | 12000 |\n\n> History is never a straight line.\n\nPopulation grows as $N_0 e^{rt}$.",
            "zh": "# 周末读书笔记\n\n读《人类简史》后半本时记下的几个地方，**第三部分**最值得读。\n\n## 还要做的事\n\n- [x] 读完第三部分\n- [ ] 整理书里的几个数字\n\n## 几个数字\n\n| 事件 | 距今 |\n| --- | ---: |\n| 认知革命 | 7 万年 |\n| 农业革命 | 1.2 万年 |\n\n> 历史从来不是一条直线。\n\n人口按 $N_0 e^{rt}$ 增长。",
        },
        "syntax": None,
    },
]

COPY = {
    "en": {
        "title": "Learn Markdown",
        "head_title": "Learn Markdown: an interactive Markdown tutorial in 26 levels",
        "lede": "26 levels, one way of writing in each: make your text draw the same as the goal and the level is done.",
        "description": "A free interactive Markdown tutorial in 26 levels, from headings, bold, lists and tasks to tables, code blocks, formulas and Mermaid diagrams, drawn in MiaoYan's preview as you type. Progress stays in your browser.",
        "map": "Levels",
        "level": "Level {n}",
        "panes": ("Markdown", "Preview", "Goal"),
        "hint": "Hint",
        "answer": "Show answer",
        "reset": "Start over",
        "next": "Next level",
        "finish_title": "All 26 levels done",
        "finish_text": "That is the Markdown you will use day to day. Write your notes in MiaoYan, or take a note further with [Markdown to image](/tools/markdown-to-image/) and [Markdown slides](/tools/markdown-slides/).",
        "again": "Play again",
        "app_title": "Keep writing in MiaoYan",
        "app_text": "Every level draws in MiaoYan's own preview, so the notes you write in the app look the same, with formulas and diagrams too.",
        "app_alt": "MiaoYan's editor beside its preview",
        "strings": {
            "level": "Level {n}",
            "passed": "Level done",
            "allDone": "All 26 levels done",
            "count": "{n} of {total} done",
            "loadFailed": "Part of the page did not load; reload to try again.",
        },
    },
    "zh": {
        "title": "Markdown 闯关",
        "head_title": "Markdown 闯关：26 关边玩边学 Markdown 语法",
        "lede": "26 关，每关学一种写法，让你写的和目标排出来一样就过关，做完常用的 Markdown 就都会了。",
        "description": "免费的 Markdown 交互教程，26 关从标题、加粗、列表、待办到表格、代码块、公式和 Mermaid 图，边写边看妙言的预览，写对了就过关，进度留在浏览器里。",
        "map": "关卡",
        "level": "第 {n} 关",
        "panes": ("Markdown", "预览", "目标"),
        "hint": "提示",
        "answer": "看答案",
        "reset": "重来",
        "next": "下一关",
        "finish_title": "26 关都过了",
        "finish_text": "日常要用的 Markdown 写法都会了，接下来可以在妙言里写笔记，也可以把写好的笔记用 [Markdown 转长图](/zh/tools/markdown-to-image/) 或 [妙言 PPT](/zh/tools/markdown-slides/) 再往前走一步。",
        "again": "重新闯一遍",
        "app_title": "接着在妙言里写",
        "app_text": "每一关用的都是妙言自己的预览，在 App 里写出来的笔记也是这个样子，公式和图表都会画出来。",
        "app_alt": "妙言的编辑和预览并排",
        "strings": {
            "level": "第 {n} 关",
            "passed": "这一关过了",
            "allDone": "26 关都过了",
            "count": "已过 {n} / {total}",
            "loadFailed": "页面有一部分没加载出来，刷新一下再试。",
        },
    },
}


def route(lang):
    return "/zh/learn/" if lang == "zh" else "/learn/"


def output(lang):
    return ROOT / route(lang).strip("/") / "index.html"


CODE_RE = re.compile(r"(`+)(?!`)(.+?)(?<!`)\1(?!`)")
LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")


def inline(text):
    """A lesson line: code spans and links, everything else as text."""
    out, at = [], 0
    for m in re.finditer(f"{CODE_RE.pattern}|{LINK_RE.pattern}", text):
        out.append(esc(text[at:m.start()]))
        if m.group(1):
            body = m.group(2)
            if body.startswith(" ") and body.endswith(" ") and body.strip():
                body = body[1:-1]
            out.append(f"<code>{esc(body)}</code>")
        else:
            out.append(f'<a href="{esc(m.group(4))}">{esc(m.group(3))}</a>')
        at = m.end()
    out.append(esc(text[at:]))
    return "".join(out)


def levels(lang):
    return [{
        "id": lv["id"],
        "title": lv["title"][lang],
        "text": inline(lv["text"][lang]),
        "hint": inline(lv["hint"][lang]),
        "start": lv["start"][lang],
        "answer": lv["answer"][lang],
    } for lv in LEVELS]


def level_map(lang):
    copy = COPY[lang]
    groups, n = [], 0
    for key, names in CHAPTERS.items():
        dots = []
        for lv in LEVELS:
            if lv["chapter"] != key:
                continue
            label = f'{copy["level"].format(n=n + 1)} {lv["title"][lang]}'
            current = ' aria-current="step"' if n == 0 else ""
            dots.append(f'<li><button type="button" class="learn-dot" data-level="{n}" aria-label="{esc(label)}" title="{esc(label)}"{current}>{n + 1}</button></li>')
            n += 1
        groups.append(f'<div class="learn-chapter"><p class="learn-chapter-name">{esc(names[lang])}</p><ol class="learn-dots">{"".join(dots)}</ol></div>')
    return f'<nav class="learn-map" aria-label="{esc(copy["map"])}">{"".join(groups)}</nav>'


def cheatsheet(lang):
    head = ("Markdown", "用来") if lang == "zh" else ("Markdown", "For")
    rows = []
    for lv in LEVELS:
        syntax = lv["syntax"]
        if not syntax:
            continue
        s = syntax[lang]
        cell = esc(s[1]) if isinstance(s, tuple) else f"<code>{esc(s)}</code>"
        rows.append(f"<tr><td>{cell}</td><td>{esc(lv['title'][lang])}</td></tr>")
    return f'<table><thead><tr><th>{head[0]}</th><th>{head[1]}</th></tr></thead><tbody>{"".join(rows)}</tbody></table>'


def prose(lang):
    md = markdown.Markdown(extensions=["extra", "sane_lists"])
    body = md.convert((SRC / f"learn.{lang}.md").read_text(encoding="utf-8"))
    if "<p><!-- cheatsheet --></p>" not in body and "<!-- cheatsheet -->" not in body:
        raise SystemExit(f"learn.{lang}.md has no <!-- cheatsheet --> marker")
    body = body.replace("<p><!-- cheatsheet --></p>", cheatsheet(lang)).replace("<!-- cheatsheet -->", cheatsheet(lang))
    return body


def page(lang):
    copy = COPY[lang]
    ui = bt.UI[lang]
    canonical = SITE + route(lang)
    body = prose(lang)
    faqs = bt.faq_pairs(body, lang)
    graph = [
        {
            "@type": "BreadcrumbList",
            "itemListElement": [
                {"@type": "ListItem", "position": 1, "name": ui["home_name"], "item": SITE + site.lang_entry(lang)[1]},
                {"@type": "ListItem", "position": 2, "name": copy["title"], "item": canonical},
            ],
        },
        {
            "@type": "LearningResource",
            "name": copy["title"],
            "url": canonical,
            "description": copy["description"],
            "inLanguage": "zh-CN" if lang == "zh" else "en",
            "learningResourceType": "Interactive tutorial",
            "teaches": "Markdown",
            "isAccessibleForFree": True,
            "author": bt.AUTHOR,
            "publisher": {"@type": "SoftwareApplication", "name": "MiaoYan", "url": SITE + "/"},
        },
    ]
    if faqs:
        graph.append({
            "@type": "FAQPage",
            "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in faqs],
        })
    out = bt.head(
        lang, title=copy["head_title"], desc=copy["description"], canonical=canonical,
        en_url=SITE + route("en"), zh_url=SITE + route("zh"),
        jsonld={"@context": "https://schema.org", "@graph": graph},
    )
    first = LEVELS[0]
    panes = copy["panes"]
    data = {
        "lang": lang,
        "parser": [bt.versioned("assets/vendor/markdown-it-14.1.0.min.js"), bt.versioned("assets/vendor/highlight-11.5.1.min.js")],
        "katex": [bt.versioned("assets/vendor/katex-0.16.47.min.js")],
        "katexCss": bt.versioned("assets/vendor/katex/katex.min.css"),
        "mermaid": [bt.versioned(p) for p in sorted(mermaid_assets.VENDOR, key=lambda p: "mermaid-" in p)],
        "mermaidConfig": mermaid_assets.CONFIG,
        "css": [bt.versioned(f"assets/vendor/preview/{c}.css") for c in bt.PREVIEW_CSS],
        "pageCss": bt.PREVIEW_PAGE_CSS,
        "strings": copy["strings"],
        "levels": levels(lang),
    }
    frame = 'sandbox="allow-same-origin allow-popups allow-popups-to-escape-sandbox" srcdoc="&lt;!doctype html&gt;&lt;title&gt;&lt;/title&gt;"'
    store = site.store_url(lang)
    shot = f"/assets/shots/{lang}-split-1400.webp"
    finish_text = inline(copy["finish_text"])
    main = f"""<main class="tool-page learn-page">
  <h1 class="section-title">{esc(copy["title"])}</h1>
  <p class="section-lede">{esc(copy["lede"])}</p>
  <div class="tool learn-tool" id="learn-tool">
    {level_map(lang)}
    <div class="learn-head">
      <div class="learn-lesson">
        <h2 class="learn-title" id="learn-title"><span class="learn-no">{esc(copy["level"].format(n=1))}</span> {esc(first["title"][lang])}</h2>
        <p class="learn-text" id="learn-text">{inline(first["text"][lang])}</p>
        <p class="learn-hint" id="learn-hint" hidden>{inline(first["hint"][lang])}</p>
      </div>
      <div class="learn-actions">
        <button type="button" class="tool-chip" data-action="hint">{esc(copy["hint"])}</button>
        <button type="button" class="tool-chip" data-action="answer">{esc(copy["answer"])}</button>
        <button type="button" class="tool-chip" data-action="reset">{esc(copy["reset"])}</button>
        <button type="button" class="tool-chip" data-action="next">{esc(copy["next"])}</button>
      </div>
    </div>
    <div class="learn-grid">
      <div class="learn-pane learn-pane-edit">
        <p class="learn-label" id="learn-code-label">{esc(panes[0])}</p>
        <div class="tool-editor"><textarea id="learn-code" class="tool-code viewer-code" aria-labelledby="learn-code-label" data-highlight spellcheck="false" autocapitalize="off" autocomplete="off" autocorrect="off" wrap="soft">{esc(first["start"][lang])}</textarea></div>
      </div>
      <div class="learn-pane">
        <p class="learn-label">{esc(panes[1])}</p>
        <div class="viewer-frame learn-frame"><iframe id="learn-mine" title="{esc(panes[1])}" {frame}></iframe></div>
      </div>
      <div class="learn-pane">
        <p class="learn-label">{esc(panes[2])}</p>
        <div class="viewer-frame learn-frame learn-frame-goal"><iframe id="learn-goal" title="{esc(panes[2])}" {frame}></iframe></div>
      </div>
    </div>
    <div class="tool-foot">
      <p class="tool-status" id="learn-status" role="status" aria-live="polite"></p>
      <p class="tool-count" id="learn-count">{esc(copy["strings"]["count"].format(n=0, total=len(LEVELS)))}</p>
    </div>
    <section class="learn-finish" id="learn-finish" hidden>
      <h2 class="learn-finish-title">{esc(copy["finish_title"])}</h2>
      <p>{finish_text}</p>
      <button type="button" class="tool-chip" data-action="again">{esc(copy["again"])}</button>
    </section>
  </div>
  <div class="blog-body tool-body">
{bt.fold_faq(body, lang)}
  </div>
  <section class="tool-app" aria-labelledby="tool-app-title">
    <div class="tool-app-text">
      <h2 class="tool-app-title" id="tool-app-title">{esc(copy["app_title"])}</h2>
      <p>{esc(copy["app_text"])}</p>
      <a class="btn btn-ghost" href="{store}" target="_blank" rel="noopener" data-store>{site.APPLE}{esc(ui["app_cta"])}</a>
    </div>
    <figure class="tool-app-shot"><img src="{shot}" width="1400" height="910" alt="{esc(copy["app_alt"])}" loading="lazy" decoding="async"></figure>
  </section>
</main>"""
    tail = (
        f'<script type="application/json" id="learn-data">{bt.script_json(data)}</script>\n'
        + "".join(f'<script src="{bt.versioned(s)}" defer></script>\n' for s in ("assets/tools/md-highlight.js", "assets/tools/md-editor.js", "assets/tools/md-rules.js"))
        + f'<script src="{bt.versioned("assets/tools/learn.js")}" defer></script>'
    )
    menu = [(k, route(k)) for k in LANGS]
    header = site.header_html(lang, home=site.lang_entry(lang)[1], menu=menu)
    footer = site.footer_html(lang, faq_href=f"{site.lang_entry(lang)[1]}#faq")
    return out + f"""<body>
<div class="wrap">
{header}
{main}
</div>
{footer}
{tail}
{site.page_script(site.STORE_JS, site.LANG_JS)}
{site.ANALYTICS}
</body>
</html>
"""


MODIFIED = "2026-11-25"


def sitemap_block():
    return "".join(f"\n  <url>\n    <loc>{SITE}{route(lang)}</loc>\n    <lastmod>{MODIFIED}</lastmod>\n  </url>" for lang in LANGS) + "\n  "


def llms_block():
    lines = ["## Learn", ""]
    for lang in LANGS:
        lines.append(f"- [{COPY[lang]['title']}]({SITE}{route(lang)}): {COPY[lang]['description']}")
    return "\n" + "\n".join(lines) + "\n"


def replace_block(text, inner, name):
    start, end = "<!-- learn:start -->", "<!-- learn:end -->"
    pattern = re.compile(re.escape(start) + ".*?" + re.escape(end), re.S)
    if not pattern.search(text):
        raise SystemExit(f"{name} is missing the {start} {end} markers")
    return pattern.sub(lambda _: start + inner + end, text)


def outputs():
    files = {output(lang): page(lang) for lang in LANGS}
    for name, block in (("sitemap.xml", sitemap_block()), ("llms.txt", llms_block())):
        files[ROOT / name] = replace_block((ROOT / name).read_text(encoding="utf-8"), block, name)
    return files


def main():
    check = "--check" in sys.argv
    ids = [lv["id"] for lv in LEVELS]
    if len(set(ids)) != len(ids):
        sys.exit("learn: duplicate level ids")
    for lv in LEVELS:
        for field in ("title", "text", "hint", "start", "answer"):
            for lang in LANGS:
                if not lv[field].get(lang) and field != "start":
                    sys.exit(f"learn: level {lv['id']} has no {lang} {field}")
    files = outputs()
    broken = bt.broken_links({p: t for p, t in files.items()})
    for line in broken:
        print(f"broken link: {line}", file=sys.stderr)
    if check:
        changed = [p for p, text in files.items() if not p.exists() or p.read_text(encoding="utf-8") != text]
        for p in changed:
            print(f"stale: {p.relative_to(ROOT)}", file=sys.stderr)
        if changed or broken:
            print("learn is out of date or broken: run python3 scripts/build-learn.py", file=sys.stderr)
            return 1
        print(f"learn-ok ({len(LEVELS)} levels)")
        return 0
    if broken:
        return 1
    for p, text in files.items():
        if not p.exists() or p.read_text(encoding="utf-8") != text:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8")
    print(f"learn: {len(LEVELS)} levels, {len(files)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
