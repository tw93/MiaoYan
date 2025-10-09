<p align="center">
    <div align="center"><img src=https://gw.alipayobjects.com/zos/k/t0/43.png width=138  /></div>
    <h2 align="center">MiaoYan</h2>
    <div align="center">Lightweight Markdown note-taking app for macOS</div>
    <div align="center"><a href="https://github.com/tw93/MiaoYan/blob/master/README_CN.md">中文</a> | <strong>English</strong></div>
</p>

## Features

- **Fantastic**: Local-first, privacy-focused, syntax highlighting, PPT mode, LaTeX, Mermaid diagrams
- **Beautiful**: Minimalist design, three-column layout, dark mode, distraction-free
- **Fast**: Swift 6 native, better performance than Electron-based apps
- **Simple**: Lightweight, keyboard shortcuts, auto-formatting

## Getting Started

1. Download the latest package from <a href="https://github.com/tw93/MiaoYan/releases" target="_blank">GitHub Releases</a>. Requires macOS 11.5+. For installation issues, refer to [this guide](https://zhuanlan.zhihu.com/p/135948430)
2. Create a `MiaoYan` folder in iCloud or preferred location, then set it as default storage in Settings
3. Click the new folder icon in the upper left to create document categories
4. Customize the default font in Settings if needed

## Keyboard Shortcuts

#### Window Operations

- `command + 1` - Toggle folder sidebar
- `command + 2` - Toggle file list
- `command + 3` - Toggle preview mode
- `command + 4` - Toggle presentation mode
- `command + option + m` - Show/hide MiaoYan globally

#### Document Operations

- `command + n` - New document
- `command + r` - Rename document
- `command + d` - Duplicate document
- `command + o` - Open in separate window
- `command + delete` - Delete document
- `command + shift + n` - New folder
- `command + shift + l` - Auto-format
- `command + option + r` - Show in Finder
- `command + option + i` - Show document properties
- `command + option + p` - Launch PPT preview

Explore more shortcuts in the app.

## MiaoYan PPT

1. New users get templates by default. Existing users can copy [this file](https://raw.githubusercontent.com/tw93/MiaoYan/master/Resources/Initial/%E5%A6%99%E8%A8%80%20PPT.md) to try it out
2. Press `command + option + p` to launch PPT preview, or right-click a document and select "MiaoYan PPT"
3. PPT mode works with documents containing `---` separators. Press Enter to preview outline, ESC to exit
4. Use HTML for custom effects. See [Reveal](https://revealjs.com/markdown/) docs for advanced usage

## Why MiaoYan

After trying many note apps (WizNote, Evernote, Ulysses, Quiver, MWeb, Bear, Typora), I couldn't find a Markdown tool that felt right, so I built MiaoYan.

As a front-end developer with some iOS experience, I wanted to explore Swift and macOS development while creating a tool I'd actually use.

## Support

- If MiaoYan improves your workflow, consider [supporting the project](https://miaoyan.app/cats.html)
- Star this repository on GitHub
- Recommend to like-minded friends

## Acknowledgments

- <a href="https://github.com/glushchenko/fsnotes" target="_blank">glushchenko/fsnotes</a> - Initial project structure reference
- <a href="https://github.com/stackotter/swift-cmark-gfm" target="_blank">stackotter/swift-cmark-gfm</a> - Swift Markdown parser
- <a href="https://github.com/simonbs/Prettier" target="_blank">simonbs/Prettier</a> - Markdown formatting tool
- <a href="https://github.com/raspu/Highlightr" target="_blank">raspu/Highlightr</a> - Syntax highlighting
- <a href="https://tsanger.cn/product" target="_blank">Tsanger Font Library</a> - TsangerJinKai font (default font)
- <a href="https://github.com/hakimel/reveal.js" target="_blank">hakimel/reveal.js</a> - PPT presentation framework
- Thanks to Vercel for hosting [miaoyan.app](https://miaoyan.app/)
    <a href="https://vercel.com?utm_source=tw93&utm_campaign=oss"><img
        src=https://gw.alipayobjects.com/zos/k/wr/powered-by-vercel.svg
        width="118px"/></a>

## License

MIT License - Free to use and contribute
