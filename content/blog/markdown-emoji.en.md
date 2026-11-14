There are two ways to put an emoji in Markdown. You can type the Unicode character itself, such as 🎉, or you can write a shortcode such as `:tada:` and let the renderer swap it in. The character works anywhere text renders. The shortcode is not part of Markdown, so it only works where the viewer has added support for it, and everywhere else it stays as literal text with colons around it.

## Typing the character

An emoji is an ordinary Unicode character, so Markdown does nothing special with it. It is stored in the `.md` file as text and survives copy and paste. On a Mac, Apple's page [Use emoji and symbols on Mac](https://support.apple.com/guide/mac-help/use-emoji-and-symbols-mchlp1560/mac) gives two routes:

- Type a common word and press Fn/Globe-E. Apple says this offers emoji suggestions, and opens the Character Viewer if there are none.
- Press Fn/Globe-E with nothing typed, or choose Edit > Emoji & Symbols, to open the Character Viewer and search it.

## Writing a shortcode

A shortcode is a name between two colons. GitHub's documentation says you add an emoji by typing `:EMOJICODE:`, a colon followed by the name, and its example is `:+1: This PR looks great - it's ready to merge! :shipit:`.

This is a GitHub feature, not a Markdown one. The word "emoji" does not appear anywhere in the [CommonMark 0.31.2 spec](https://spec.commonmark.org/0.31.2/) or the [GFM spec](https://github.github.com/gfm/), so a parser that follows only the spec prints `:tada:` as plain text. The [CommonMark and GFM comparison](/blog/commonmark-vs-gfm/) covers what each layer does define.

GitHub's REST API lists its names. `gh api emojis` returned 1,936 names on 14 November 2026. 1,913 point to a Unicode image and 23 are GitHub's own pictures with no Unicode equivalent, such as `octocat`, `shipit` and `bowtie`. A few real entries:

```text
smile             .../emoji/unicode/1f604.png
tada              .../emoji/unicode/1f389.png
rocket            .../emoji/unicode/1f680.png
white_check_mark  .../emoji/unicode/2705.png
```

The count will drift as emoji are added. The last part of each address is the code point, so `:tada:` is U+1F389.

## Where shortcodes render

GitHub substitutes when it renders. Sending `Text :smile: here` to the Markdown API with `-f mode=gfm` and with `-f mode=markdown` returns `<p>Text 😄 here</p>`, the Unicode character and not an image tag.

Pandoc makes it an optional extension. Its [manual](https://pandoc.org/MANUAL.html) describes `emoji` as "Parses textual emojis like :smile: as Unicode emoticons". In Pandoc 3.13, `pandoc --list-extensions=gfm` shows `+emoji` and `pandoc --list-extensions=commonmark` shows `-emoji`, so `pandoc -f gfm` converts the codes and `pandoc -f commonmark` leaves them alone. The gfm reader produced `<span class="emoji" data-emoji="smile">😄</span>`.

## Which one to use

The trade-off is about what stays in the file.

**Shortcodes** stay ASCII. `:white_check_mark:` is readable in any editor and any diff, even where the font lacks the glyph, and you can type it without a picker. The cost is that it renders only where someone added support, and each tool brings its own name table.

**Unicode characters** have no dependency. What you see in the editor is what is stored, and any renderer that shows text shows the emoji in the platform's own font. The cost is that the source is harder to type and to search by name.

For notes that stay in your own folder, type the character. For a README or issue on GitHub either works. For text that several tools will convert, the character is the safer choice. To show a literal `:tada:`, put it in a code span: GitHub and MiaoYan both leave a shortcode inside a code span or fenced block alone. A backslash does not help here. The [escape characters guide](/blog/markdown-escape-characters/) explains that `\:` is a valid escape, but the parser drops the backslash and the text is still `:tada:` when the shortcode is substituted, so GitHub's Markdown API returns 🎉 for both `\:tada:` and `:tada\:`.

## Emoji in headings and anchors

This is where emoji cause real breakage. Reading the rendered README of a public repository through `gh api repos/<owner>/<repo>/readme` with the HTML media type returns the ids GitHub generated. Two READMEs give these:

| Heading in the source | Anchor GitHub generated |
| --- | --- |
| `## 🌟 Preview` | `#-preview` |
| `### What's included 🚀` | `#whats-included-` |
| `## Quickstart 🛠️` | `#quickstart-` plus an invisible character |

The emoji is dropped from the id, but the space next to it becomes a hyphen, so a leading emoji gives an anchor that starts with a hyphen and a trailing one gives an anchor that ends with one. The third row is the trap. 🛠️ is the wrench followed by U+FE0F, the variation selector that asks for the colour form, and that selector stayed in the id, whose last three bytes are `ef b8 8f`. A link typed by hand as `#quickstart-` looks the same but does not match that id exactly.

To avoid the problem, keep emoji out of headings you link to, or put `<a name="..."></a>` above the heading and link to that. The general rules are in [Markdown links and anchors](/blog/markdown-links-and-anchors/).

## What MiaoYan V4.9.0 does

The preview converts shortcodes. It loads `emoji.min.js`, a copy of the open-source js-emoji library, and after the note is rendered a function in `common.js` walks the text nodes and replaces each `:name:` the library knows with the Unicode character, not an image, so `:tada:` becomes 🎉 in the system emoji font. It skips anything inside `<code>` and `<pre>`. It runs when a note loads and again on blocks inserted while you edit in split view, and a unit test in the repository asserts that `:smile:` is gone from the preview text after both.

PDF and image export capture that rendered preview, so they carry the converted emoji, and Toggle Presentation uses the same page. MiaoYan PPT, the slide mode built from `---`, loads a different page without js-emoji, so a shortcode on a slide stays as text.

Two limits follow from the source. The name table belongs to js-emoji, not GitHub's list. The file has `tada`, `rocket`, `white_check_mark`, `memo`, `warning` and `+1`, and lacks `octocat`, `shipit` and `bowtie`. A name the library does not know stays as text, so test an unusual one before relying on it. The conversion also happens only in the preview: the saved `.md` still contains `:smile:`, and another app opening the file sees a shortcode.

Heading ids in the preview are the visible heading text, not a GitHub-style slug. A heading typed with the Unicode character keeps it in the id, and since the shortcode pass runs before ids are assigned, a heading written with `:tada:` gets 🎉 in its id too.

If you want the emoji to survive in the file and in other tools, type the character with the Character Viewer shortcut above.

## FAQ

### Does `:smile:` work in all Markdown?

No. CommonMark and the GFM spec do not define it, and Pandoc converts it only with the `emoji` extension, which is on for `gfm` and off for `commonmark`.

### How do I get the list of GitHub emoji names?

Run `gh api emojis`. It returns a JSON object of names and image addresses.

### Why does my link to a heading with an emoji not work?

GitHub removes the emoji from the id but keeps the hyphen from the space next to it, and may keep an invisible variation selector. Copy the anchor from the heading's link icon instead of typing it.
