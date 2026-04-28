<h4 align="right">English | <strong><a href="https://github.com/tw93/MiaoYan/blob/main/README_CN.md">简体中文</a></strong></h4>

<p align="center">
  <a href="https://miaoyan.app/" target="_blank"><img src="https://gw.alipayobjects.com/zos/k/t0/43.png" width="138" /></a>
  <h1 align="center">MiaoYan</h1>
  <div align="center">
    <a href="https://twitter.com/HiTw93" target="_blank">
      <img alt="Twitter Follow" src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter"></a>
    <a href="https://t.me/+GclQS9ZnxyI2ODQ1" target="_blank">
      <img alt="Telegram" src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram"></a>
    <a href="https://github.com/tw93/MiaoYan/releases" target="_blank">
      <img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/tw93/MiaoYan/total.svg?style=flat-square"></a>
    <a href="https://github.com/tw93/MiaoYan/commits" target="_blank">
      <img alt="GitHub Commit Activity" src="https://img.shields.io/github/commit-activity/m/tw93/MiaoYan?style=flat-square"></a>
    <a href="https://github.com/tw93/MiaoYan/issues?q=is%3Aissue+is%3Aclosed" target="_blank">
      <img alt="GitHub Closed Issues" src="https://img.shields.io/github/issues-closed/tw93/MiaoYan.svg?style=flat-square"></a>
    <img alt="macOS 11.5+" src="https://img.shields.io/badge/macOS-11.5%2B-orange?style=flat-square">
  </div>
  <div align="center">Lightweight Markdown note-taking app for macOS</div>
</p>

<img src="https://raw.githubusercontent.com/tw93/static/main/miaoyan/miaoyan.gif" width="900px" />

## Features

- **Fantastic**: Local-first, no data collection, split editor & preview, LaTeX, Mermaid
- **Beautiful**: Minimalist design, three-column layout, dark mode, distraction-free
- **Fast**: Swift 6 native, better performance than Electron-based apps
- **Simple**: Lightweight, keyboard shortcuts, auto-formatting

## Installation

Download from the **Mac App Store** — all future updates ship there. A paid download is the best way to support ongoing development; the open-source build offers the same experience.

<a href="https://apps.apple.com/cn/app/miaoyan/id6759252269"><img src="https://cdn.tw93.fun/uPic/C3Renh.png" width="160" alt="Download on the Mac App Store" /></a>

After installing, create a `MiaoYan` folder in iCloud Drive or your preferred location, open Preferences (⌘,), set the storage path, and start writing. Existing sponsors can DM me directly for an App Store redemption code.

### Build from source / older versions

From **4.0** onward MiaoYan is distributed through the App Store. You can still build from the MIT-licensed source, or grab a pre-4.0 DMG from [GitHub Releases](https://github.com/tw93/MiaoYan/releases).

## CLI

MiaoYan provides a command-line interface for quick note operations.

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/tw93/MiaoYan/main/scripts/install.sh | bash

# Usage
miao open <title|path>    # Open note
miao new <title> [text]   # Create new note
miao search <query>       # Search notes in terminal
miao list [folder]        # List top-level folders, or markdown in folder
miao cat <title|path>     # Print note content
miao update               # Update CLI
```

## Split Editor & Preview Mode

Edit and preview side by side with real-time preview and 60fps bidirectional scroll sync.

**Quick Toggle**: Press `⌘\` to instantly toggle split view mode, or enable it in Preferences → Interface → Edit Mode → Split Mode.

Why not WYSIWYG like Typora? We prioritize pure Markdown editing experience, and implementing WYSIWYG in native Swift is overly complex with reliability concerns. Split mode maintains clean editing while providing instant visual feedback.

<img src="https://gw.alipayobjects.com/zos/k/eg/jV8Gra.png" width="100%" alt="Split Editor & Preview Mode" />

## Documentation

- [Markdown Syntax Guide](Resources/Initial/MiaoYan%20Markdown%20Syntax%20Guide.md) - Complete syntax reference with advanced features
- [PPT Presentation Mode](Resources/Initial/MiaoYan%20PPT.md) - Guide to creating presentations with `---` slide separators

## Support

- If MiaoYan helped you, [share it](https://twitter.com/intent/tweet?url=https://github.com/tw93/MiaoYan&text=MiaoYan%20-%20A%20fast%2C%20elegant%20Markdown%20editor%20for%20Mac.) with friends or give it a star.
- Got ideas or bugs? Open an issue or PR, feel free to contribute your best AI model.
- I have two cats, TangYuan and Coke. If you think MiaoYan delights your life, you can feed them <a href="https://miaoyan.app/cats.html?name=MiaoYan" target="_blank">canned food 🥩</a>.

<a href="https://miaoyan.app/cats.html?name=MiaoYan"><img src="https://cdn.jsdelivr.net/gh/tw93/MiaoYan@main/assets/sponsors.svg" width="1000" loading="lazy" /></a>

## Acknowledgments

- [glushchenko/fsnotes](https://github.com/glushchenko/fsnotes) - Initial project structure reference
- [stackotter/swift-cmark-gfm](https://github.com/stackotter/swift-cmark-gfm) - Swift Markdown parser
- [simonbs/Prettier](https://github.com/simonbs/Prettier) - Markdown formatting utilities
- [raspu/Highlightr](https://github.com/raspu/Highlightr) - Syntax highlighting
- [TsangerType](https://tsanger.cn/product) - TsangerJinKai font (default font)
- [hakimel/reveal.js](https://github.com/hakimel/reveal.js) - PPT presentation framework
- [Vercel](https://vercel.com?utm_source=tw93&utm_campaign=oss) - Static hosting for [miaoyan.app](https://miaoyan.app/)  
  <a href="https://vercel.com?utm_source=tw93&utm_campaign=oss">
    <img src="https://gw.alipayobjects.com/zos/k/wr/powered-by-vercel.svg" width="136" alt="Powered by Vercel" />
  </a>

## License

MIT License - Feel free to use and contribute.
