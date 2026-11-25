## What it changes

Where a Han character or kana touches a Latin letter or a digit, it adds one space between them, so `使用Swift开发` becomes `使用 Swift 开发` and `第3章` becomes `第 3 章`; spaces already there stay. A half-width `,;:!?.` that ends a clause after a Han character becomes full-width, so `你好,世界` becomes `你好，世界`, while the dot and colon inside numbers like 3.5 and 10:00 stay. Spaces around full-width punctuation are removed, full-width letters and digits become half-width, three dots after Chinese become an ellipsis, a single em dash between Han characters becomes a comma while the doubled Chinese dash stays, and runs of blank lines fold into one.

The right side shows the result with every added or replaced character marked, and a thin line where a space or a blank line was removed. Copy it and paste it back where it came from.

## What it leaves alone

Fenced and inline code are never changed, though inline code gets a space on each side, so ``运行`git status`确认`` becomes ``运行 `git status` 确认``. Math in `$...$` and `$$`, link and image targets, `[[wikilinks]]`, bare URLs, reference definitions and front matter stay as they are, while link text is cleaned.

Why Chinese writers add this space, and the usual exceptions, are in [Chinese-English spacing in Markdown notes](/blog/chinese-english-spacing/).

## FAQ

### Is it the same as Clean Typography in MiaoYan?

Yes. It runs the same rules as Clean Typography in MiaoYan for Mac, written line by line from its source, so the same text comes out identical in both. In MiaoYan it cleans the open note in one step, and `⌘Z` undoes it.

### Does it change quotation marks?

No. Corner brackets, curly quotes and straight quotes each have their own users, so it leaves them as they are; the only punctuation it changes is a half-width comma, semicolon, colon, exclamation mark, question mark or full stop after a Chinese character.

### Does it add a space between a number and its unit?

No. `10Gbps` stays `10Gbps`, and `90°` and `15%` do not change, because unit symbols are not letters or digits. Add the space yourself where a unit takes one.

### A product name got a space. What now?

It does not know product names, so a brand written without a space, like `豆瓣FM`, gets one. Every change is marked on the right, so look over the marks and put the name back in your text after copying. The cleaning runs in your browser and the text is not sent to a server.
