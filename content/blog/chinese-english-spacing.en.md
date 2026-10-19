Chinese writers usually put one ordinary space between Han characters and Latin letters or digits, so it is written `使用 Swift 开发` and `第 3 章`, not `使用Swift开发`. Chinese has no spaces between words, so the space is not a grammar rule; it is a readability convention from the Chinese copywriting guide, and it is not part of Markdown. Markdown passes the characters through unchanged. In MiaoYan two commands in the Edit menu add the spaces: Clean Typography, which has no shortcut and also fixes Chinese punctuation, and Format on `⌘⇧L`, which adds them as a side effect of its bundled Prettier formatter.

## Why the space exists

Han characters are square and evenly spaced, Latin letters are narrow and proportional, and when the two touch the text looks cramped. Typesetters have long solved this with a small gap, not a full space. The W3C requirements document for Chinese layout, [clreq](https://www.w3.org/TR/clreq/), says that for horizontal text there is, in principle, tracking or spacing of up to a quarter of a Han character's width between a Han character and an adjacent Western letter or numeral, except at the start or end of a line.

Plain text has no such gap, so writers type a real space instead. The best-known statement of the habit is the [Chinese Copywriting Guidelines](https://github.com/sparanoid/chinese-copywriting-guidelines) (中文文案排版指北), which asks for a space between Chinese and English, between Chinese and digits, and between digits and units. Its own example is "在 LeanCloud 上，数据存储是围绕 `AVObject` 进行的", where the inline code gets the same treatment as a Latin word.

The guide is a style convention, not a standard, and plenty of published Chinese text ignores it. What matters for a note is consistency. A mixed archive, with some notes spaced and some not, is the thing that hurts search and diff, because `Swift开发` and `Swift 开发` are different strings.

## The exceptions that matter

Three cases from the guide come up constantly.

- Full-width punctuation takes no space on either side. Write `刚刚买了一部 iPhone，好开心！`, not `iPhone ，好开心`. The comma, period and question mark already have their own built-in whitespace.
- Degrees and percent signs attach to the number: `90°`, `15%`. A space before `%` is wrong in the guide. Other units do get a space: `10 Gbps`, `20 TB`.
- Product names are written as the owner writes them. The guide's example is 豆瓣FM, which is officially written without a space.

Two more cases come from Markdown itself rather than from the guide. Inside code spans and fenced code blocks you must not change anything, because a space is data there. And inside URLs, file paths, link targets and wikilink titles a stray space breaks the link.

## What MiaoYan does

MiaoYan 4.5.0 has two commands in the Edit menu that both change spacing, and they do different amounts of work.

**Format** (`⌘⇧L`, Chinese UI: 文档排版) runs a bundled Prettier Markdown formatter over the note and tidies Markdown structure such as list markers and table alignment. The Prettier it bundles is from the 2.x line, which still inserts a space between Chinese and Latin letters or digits, so `使用Swift开发` comes out as `使用 Swift 开发` here too; Prettier 3.0 dropped that behavior. Format does nothing else for Chinese text: `你好,世界` keeps its half-width comma, a space before a full-width comma stays, and inline code gets no space around it.

**Clean Typography** (Chinese UI: 排版净化) is the command built for Chinese text. It has no keyboard shortcut. It rewrites the whole open note in one step, and the rewrite lands in the undo stack, so `⌘Z` reverts it. If nothing needs changing, it shows a message that the typography is already clean. Like Format, it refuses to run in preview mode, so leave preview first.

The rules in the source are these:

- A space is inserted between a Han or kana character and an ASCII letter or digit, in either order. `使用Swift开发` becomes `使用 Swift 开发` and `第3章共10节` becomes `第 3 章共 10 节`. Existing spacing is left alone.
- Half-width `, ; : ! ? .` directly after a Han character becomes the full-width form when it ends a clause, so `你好,世界` becomes `你好，世界`. Decimal points and times such as `3.5` and `10:00` are untouched.
- Spaces next to full-width punctuation are removed.
- Full-width letters and digits become ASCII, `等等...` becomes `等等……`, and a single em dash between Han characters becomes a comma. A doubled em dash, the proper Chinese dash, is kept.
- Runs of blank lines collapse to one.

It does not insert a space between a digit and a Latin unit, so `10Gbps` stays as it is, and `90°` and `15%` are untouched because those symbols are not letters or digits. It also does not know product names such as 豆瓣FM, so review the result.

## What it leaves alone

The cleaner splits each line into protected and plain segments before touching anything. Protected: fenced code (backticks or tildes, including inside block quotes), indented code, inline code, `$...$` math and `$$` blocks, link and image targets, `[[wikilinks]]`, bare `http` and `https` URLs, reference definitions such as `[ref]: target` and `[^1]: note`, and front matter. Trailing double spaces, which Markdown reads as a hard line break, are kept.

Inline code is a special case. The text inside is untouched, but the boundary gets a space, so ``使用`git status`命令`` becomes ``使用 `git status` 命令``, matching the guide. The link text is cleaned while the link target is not: `看[文档3](path/图3.png)吧` becomes `看[文档 3](path/图3.png)吧`.

One quirk: a dollar amount like `$100和$200` is not treated as math, so it is spaced like normal text.

## The preview adds its own spacing

Separately from the edit, MiaoYan's preview page uses a typography stylesheet based on Heti, a Chinese typesetting project. Its `.heti` container sets `text-autospace: normal`. That CSS property asks the browser engine to add a small gap between Han characters and Latin letters or digits itself, without any space in the file. MDN lists support from Safari 18.4, so whether you see it depends on the system's web engine. Either way it affects only the preview; your file still contains whatever you typed.

This is why a note without spaces can look fine in the preview and wrong in GitHub, a chat paste or another editor. Putting the real spaces in the file is the portable choice.

## Applying it to many notes

At 4.5.0 both commands work on the open note only. There is no batch command in the menu. For a folder of existing notes you can run it note by note, or use a script outside the app. The guide links [pangu.js](https://github.com/vinta/pangu.js), the library behind the same idea, so test whichever tool you pick on a copy first and check how it treats code blocks. Because notes are plain `.md` files, a copy of the folder is an easy backup.

After any bulk pass, diff the result and look at code fences, URLs and product names first.

## Checking the result

- In any editor with regular expression search, look for a Han character directly next to a letter or digit with `[一-鿿][A-Za-z0-9]|[A-Za-z0-9][一-鿿]`; an empty result means the spacing is consistent.
- Run Clean Typography a second time. The "already clean" message tells you the note is stable.
- Look at one code fence and one link with Chinese text near it.

For the rest of the syntax and what MiaoYan renders, see the [Markdown cheat sheet](/blog/markdown-cheat-sheet/); plain files also make a bulk pass safer, as [local-first Markdown notes](/blog/local-first-markdown-notes/) explains.

## FAQ

### Do I need the space in headings and filenames?

Headings follow the same convention. Filenames and wikilink titles are your call, but be consistent, because a wikilink has to match the note title, spaces included.

### Is a space before a full-width comma ever correct?

No. The guide treats it as wrong, and Clean Typography removes it. Format leaves it in place.

### Is the space part of Markdown?

No. Markdown parsers keep the characters you typed, so the spacing has to be in the file or come from the renderer's typography, as in the preview described above.
