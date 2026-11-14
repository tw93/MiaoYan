A README is a Markdown file named `README.md` that GitHub shows on the front page of a repository, so it works as the project's landing page. A good one answers four things in order: what this is, how to install it, how to use it, and how to contribute. Write it in plain Markdown plus a few GitHub-friendly features, keep links and images relative so they survive branches and clones, and read it rendered before you push.

## What a README is for and where GitHub shows it

GitHub's documentation lists what a README should tell a visitor: what the project does, why it is useful, how to get started, where to get help, and who maintains and contributes to it. 

GitHub looks for the file in three places. If a repository has more than one README, the one displayed is chosen from the `.github` directory first, then the repository's root directory, and finally the `docs` directory. Most projects use the root, where people look first after cloning.

One limit is worth knowing: GitHub truncates README content beyond 500 KiB when it is viewed on the site, which you will only hit with embedded data.

## A section order that works

This order follows what a first-time visitor asks, and MiaoYan's own README follows most of it:

1. **Name and one-line description.** MiaoYan's is "A native Mac app for local Markdown notes", right under the title. Say what the thing is, not what it hopes to be.
2. **Screenshot or demo.** One image under the title. MiaoYan's README has a single picture of the app on Mac, iPad and iPhone directly below the badges.
3. **Features.** Three to five bullets, each a fact. "Notes are Markdown files in a folder you choose" tells a reader more than "powerful and flexible".
4. **Install.** Numbered when there are several routes. The MiaoYan README lists the App Store, Homebrew and GitHub Releases, with `brew install --cask miaoyan` in a code block.
5. **Usage.** The shortest working example, in a fenced code block. For a command-line tool, show real commands; for an app, show the one shortcut a new user needs.
6. **Configuration.** Only the options people actually change, with defaults.
7. **Contributing.** How to report a bug or send a patch, or a link to `CONTRIBUTING.md`.
8. **License.** One line, such as "MIT License", matched by a `LICENSE` file.

Skip sections that have nothing to say, and if one grows past a screen, move it to a file under `docs/` and link to it.

Code goes in fenced blocks with a language tag, so GitHub highlights it. The fence rules, including longer fences for nested code, are in [Markdown code blocks](/blog/markdown-code-blocks/).

## Relative links and images

Point to files in your own repository with relative paths. GitHub's documentation says it transforms a relative link or image path based on the branch you are currently on, so the link keeps working on a feature branch, and it notes that relative links are easier for people who clone the repository. A link that starts with `/` is relative to the repository root.

```markdown
![Split editor and preview](docs/images/split.png)
See [the syntax guide](docs/syntax.md) and [contributing](CONTRIBUTING.md).
```

Absolute links to your own files, such as a full `github.com/.../blob/main/...` URL, are a trap: they pin the file to one branch and may not work in a clone. Keep link text on a single line, as GitHub's docs ask.

MiaoYan's README does use an absolute URL for its main screenshot, hosted on the project website. That is a choice, not a rule: a hosted image still loads where the README is copied outside the repository, where a relative path may not resolve. If you publish the README in several places, hosted images are safer; if it lives on GitHub only, relative paths are simpler. Image syntax, alt text and sizing are in [Markdown images](/blog/markdown-images/), and heading anchors for deep links are in [Markdown links and anchors](/blog/markdown-links-and-anchors/).

When the README has several translations, link them from the top. MiaoYan's README has one line of language links, each pointing to a sibling file such as `README_CN.md`.

## Badges

A badge is a small image, usually from shields.io, that shows a status next to the title: downloads, build state, a license, the platform. Shields.io describes itself as "concise, consistent, and legible badges", and its site shows a static badge as a URL of the form `https://img.shields.io/badge/any%20text-you%20like-blue`, with text, a second text segment and a colour after `/badge/`.

```markdown
![macOS 12.0+](https://img.shields.io/badge/macOS-12.0%2B-orange?style=flat-square)
```

MiaoYan's README uses that badge URL, written there as an HTML `<img>` tag, with `flat-square` as a style parameter. Keep badges to the few a visitor would act on, since a long row is noise. For anything beyond the static form, read shields.io's own documentation, because the URL formats for live badges differ by service.

## The outline GitHub generates

For rendered Markdown files, GitHub automatically generates a table of contents from the section headings. A visitor opens it from the Outline menu icon in the top corner of the rendered page. Two consequences follow. You do not need to maintain a hand-written table of contents in a README, and your heading hierarchy now doubles as navigation, so use `##` for sections and `###` for sub-sections without skipping levels. Each heading also has a link icon on hover that gives its anchor for linking straight to a section.

## GitHub-specific Markdown that will not render elsewhere

GitHub Flavored Markdown covers tables, task lists, strikethrough and autolinks, and plenty of renderers support those. Several things people use in READMEs are GitHub features, not standards, and show up as raw text in viewers that do not support them. The split between the standard and the extras is in [CommonMark vs GFM](/blog/commonmark-vs-gfm/).

- **Alerts.** A blockquote whose first line is `> [!NOTE]`, with `TIP`, `IMPORTANT`, `WARNING` and `CAUTION` as the other types, renders with a colour and icon on GitHub. The docs advise one or two per article, not consecutively, and they cannot be nested inside other elements. Elsewhere you may see an ordinary quote starting with `[!NOTE]`.
- **Mermaid diagrams.** A fenced code block with the `mermaid` language is drawn as a diagram. GitHub says rendering is available in issues, discussions, pull requests, wikis and Markdown files. Tools without Mermaid support show a plain code block. See [Mermaid diagrams in Markdown](/blog/mermaid-diagrams-in-markdown/).
- **Issue references in task lists.** A task list is `- [ ]` and `- [x]` items, and GitHub's docs show references to issues inside task items rendered as issue titles. That substitution is GitHub's; the checkboxes themselves are portable.
- **Line breaks.** In issues and pull requests GitHub turns a newline into a line break, but in a `.md` file you need two trailing spaces, a backslash or `<br/>`. A README that looks right in a comment box can run together in the file.

If the README will also be read elsewhere, test it there.

## Check it before you push

A README breaks in small ways: a table whose delimiter row has a different number of cells from the header, which then falls back to plain text, a wrong relative path, an unclosed code fence that swallows the rest of the page. Preview the file before GitHub shows you these.

In MiaoYan, open the README as a note and press `⌘\` to toggle the split view, with the Markdown and the rendered page side by side. Per its V4.9.0 source, the preview uses the cmark-gfm parser with tables, footnotes, strikethrough and task lists enabled, renders Mermaid, and passes raw HTML through, so the centred `<div>` and `<img width="...">` patterns in many READMEs show up as written. It also converts `> [!NOTE]` style quotes into styled callouts like GitHub's. It cannot check what depends on GitHub itself: relative links resolve against the branch you push, shields.io badges need a network connection, and the Outline menu only exists on github.com. After pushing, open the repository page once to confirm.

Any local Markdown preview does the job; the point is to look at the rendered result before others do. If you are choosing a Mac editor for this, see [choosing a Markdown editor for Mac](/blog/markdown-editor-for-mac/).

## FAQ

### Should the file be README.md or README?

Use `README.md`. GitHub's README documentation only speaks of a README file, but the `.md` extension is what tells GitHub and editors to treat it as Markdown.

### How long should a README be?

As long as a visitor needs to install and run the project, and no longer. Detailed guides belong in `docs/` with a link.

### Can I have one README per language?

Yes. Keep the main README at the root and link `README_CN.md` style siblings from its first lines, as MiaoYan's does.

### Do alerts and Mermaid work outside GitHub?

Not everywhere. They are GitHub features, and tools that do not support them show a plain quote or code block.
