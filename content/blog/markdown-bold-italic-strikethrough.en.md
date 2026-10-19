Use `**bold**`, `*italic*` and `~~strikethrough~~`. Asterisks also work inside words, underscores do not, and strikethrough is a GitHub Flavored Markdown extension rather than core CommonMark. When emphasis fails and you see literal asterisks, the cause is nearly always the character touching the delimiter: a `**` that opens next to punctuation or closes right after it has to be separated from the neighbouring text by a space or more punctuation. That bites hardest in Chinese text, such as `**注意：**这样不行`. MiaoYan V4.5.0 has Bold, Italic and Deleteline in the Format menu, and you can fall back to `<b>` and `<del>` tags when the rules get in the way.

## Asterisks, underscores and combinations

```markdown
*italic* or _italic_
**bold** or __bold__
***bold italic***
**bold with *italic* inside**
~~**struck and bold**~~
```

Both characters make the same HTML, `<em>` for one and `<strong>` for two. Three give italic wrapped around bold, and nesting in either order works, so `**_x_**` and `***x***` both render bold italic. A span cannot cross a blank line, so `**bold`, a blank line, then `break**` stays literal. Emphasis also works inside headings, list items, table cells and link text, and around code spans.

The difference is intraword behaviour. `un*frigging*believable` italicizes the middle, but `un_frigging_believable` and `snake_case_name` stay as typed, because CommonMark does not let `_` open or close emphasis inside a word. That protects identifiers such as `snake_case_name`, though a standalone `__init__` still turns into bold init, so put code in backticks. Defaulting to `*` avoids both surprises, since it behaves the same inside words and next to CJK characters.

## Why some emphasis fails

CommonMark decides by looking at the characters on each side of a run of `*` or `_`. In plain words: a run can open emphasis only if what follows is not whitespace, and if what follows is punctuation, what precedes must be whitespace or punctuation. A run can close only if what precedes is not whitespace, and if what precedes is punctuation, what follows must be whitespace or punctuation. The spec calls these left-flanking and right-flanking runs. Underscore adds the intraword rule on top.

These were run through cmark-gfm 0.29.0.gfm.3, the version bundled with MiaoYan V4.5.0, with its four extensions on:

| Source | Result |
| --- | --- |
| `这是**加粗**文字` | bold works, CJK letters count as ordinary text |
| `**加粗**，逗号` and `**加粗**。` | works, the closing `**` follows a letter |
| `**注意：**这样不行` | fails, literal asterisks |
| `中文**（括号）**继续` | fails |
| `句子**“引号”**后面` | fails |
| `**bold.**Next` | fails, same cause in ASCII |
| `这是_斜体_文字` | fails, `_` is blocked inside a word |
| `这是*斜体*文字` | works |

The failing rows share one shape: punctuation on the inside of the delimiter, an ordinary character on the outside. Full-width punctuation such as `：`, `“` and `（` counts as punctuation, and Chinese has no spaces to satisfy the rule. Three fixes worked in the same runs: move the punctuation outside, `**注意**：这样可以`; put a space or more punctuation beside the delimiter, `**注意：** 这样可以` or `（**括号**）继续`; or use `<strong>` tags.

One more thing is engine-dependent. The CommonMark 0.31.2 spec counts symbols such as `¥` as punctuation, while MiaoYan's cmark-gfm build still bolds `价格**¥100**元`. A note that renders in MiaoYan can therefore break in a parser that follows the 0.31 rule, so test the place it will be published. MiaoYan's editor pane also tints bold and italic with its own regular expressions, not cmark, and that pattern only checks for non-space characters inside the marks, so a span like `**注意：**这样` is tinted as bold in the editor while the preview shows asterisks. Judge by the preview.

## Strikethrough

`~~text~~` is a GFM extension, and MiaoYan V4.5.0 enables it. The GFM spec says one or two tildes work, and GitHub's docs list `~~ ~~` or `~ ~`. In the test runs, `~one~` struck through, but unequal counts such as `~~a~` and three tildes mid-line stayed literal.

The single tilde is a trap for Chinese and technical text. `3~5 天，6~10 天` rendered as `3`, then a struck-through "5 天，6", then `10 天`. Pairs like `~5` and `~10` with a space before them are safe, and `~/Documents` stays literal. For a range, write `3-5`, use the full-width `～`, or escape with `\~`; the [escape characters](/blog/markdown-escape-characters/) article has the rest of the list. Two tildes are safer for deliberate strikethrough. The editor's own strike pattern recognises only the double-tilde form, so a single-tilde strike shows up in the preview but gets no styling in the editor.

Strikethrough is not in the CommonMark spec. A parser without the extension prints the tildes, and the [CommonMark vs GFM](/blog/commonmark-vs-gfm/) article lists what else differs. If the text will reach such a renderer, `<del>` or `<s>` is the safer choice.

## The menu and shortcuts in MiaoYan

In V4.5.0, the Format menu (in Chinese, 格式) holds these items:

| Menu item | Chinese label | Shortcut | Inserts |
| --- | --- | --- | --- |
| Bold | 粗体 | `⌘B` | `**text**` |
| Italic | 斜体 | `⌘I` | `*text*` |
| Deleteline | 删除线 | `⌘⇧X` | `~~text~~` |

With text selected, the command wraps it and leaves the cursor after the closing mark. With nothing selected it inserts an empty pair and puts the cursor between the marks. It always wraps and never toggles, so pressing `⌘B` on bold text adds a second layer, `****text****`, which you remove by hand. The commands need the editor focused and do nothing in preview mode. The same menu has Underline, which writes `<u>text</u>`, because Markdown has no underline syntax. See the [cheat sheet](/blog/markdown-cheat-sheet/) for how the rest of the syntax maps.

## When to use HTML

The preview renders raw HTML, so `<b>`, `<strong>`, `<del>` and `<s>` all work. Reach for them when a delimiter sits against punctuation or CJK text and you cannot add a space. Markdown inside inline tags is still parsed, so `<b>*x*</b>` gives bold wrapped around italic.

Keep the tag on the same line as its text. A tag alone on a line starts an HTML block, and the lines inside it are not parsed as Markdown. The trade-off is portability in the other direction: a renderer that strips raw HTML drops the tags, which can leave plain text where you wanted emphasis.

## Checking the result

Open the preview and look for literal `*`, `_` or `~`. Then check in order: whitespace just inside the delimiter, punctuation touching the delimiter with a letter on the other side, an underscore in the middle of a word, unequal tilde counts, and a blank line between the opening and closing marks. If a character is still being read as syntax, escape it with a backslash.

To catch the closing-side failure across a folder before you publish, search for a `**` that has punctuation on its inside and a letter on its outside:

```bash
grep -rnE '[：；，。！？、）」』”.,:;!?)]\*\*[^[:space:]*：；，。！？、）」』”.,:;!?)]' --include='*.md' .
```

Run on the failing and working examples in the table above plus `**注意**：这样可以`, `**注意：** 这样可以` and `（**括号**）继续`, it listed exactly the four lines cmark-gfm left as literal asterisks. It does not see the opening side, so a line it misses can still fail.

## FAQ

### Is bold two asterisks or two underscores?

Both are valid. Asterisks are safer, since underscores do nothing inside words and next to Chinese text.

### Why does my bold show asterisks next to Chinese punctuation?

The closing `**` follows punctuation and precedes a letter, so it cannot close. Move the punctuation outside, add a space, or use `<strong>`.

### Does GitHub support single-tilde strikethrough?

Its documentation lists `~~text~~` and `~text~`, and the GFM spec says one or two tildes.
