<h4 align="right">English | <strong><a href="https://github.com/tw93/MiaoYan/blob/main/README_CN.md">简体中文</a></strong> | <strong><a href="https://github.com/tw93/MiaoYan/blob/main/README_JP.md">日本語</a></strong></h4>

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

<img src="https://raw.githubusercontent.com/tw93/static/master/miaoyan/newmiaoyan.gif" width="900px" />

## Features

- **Fantastic**: Local-first, privacy-focused, syntax highlighting, split editor & preview, PPT mode, LaTeX, Mermaid diagrams
- **Beautiful**: Minimalist design, three-column layout, dark mode, distraction-free
- **Fast**: Swift 6 native, better performance than Electron-based apps
- **Simple**: Lightweight, keyboard shortcuts, auto-formatting

## Installation & Setup

1. Download the latest DMG package from [GitHub Releases](https://github.com/tw93/MiaoYan/releases/latest) (Requires macOS 11.5+)
2. Double-click to install MiaoYan.app to Applications
3. Create a `MiaoYan` folder in iCloud Drive or your preferred location
4. Open MiaoYan Preferences and set the storage location to this folder
5. Click the "New Folder" icon in the top-left corner to create document categories and start writing

After installation, we recommend exploring Preferences (⌘,) to discover MiaoYan's rich customization options, including edit modes, themes, fonts, and more to create your perfect writing environment.

## Split Editor & Preview Mode

Edit and preview side by side with real-time preview and bidirectional scroll sync. Enable it in Preferences → Interface → Edit Mode → Split Mode.

Why not WYSIWYG like Typora? We prioritize pure Markdown editing experience, and implementing WYSIWYG in native Swift is overly complex with reliability concerns. Split mode maintains clean editing while providing instant visual feedback.

<img src="https://cdn.tw93.fun/pic/1jZnC4.png" width="100%" alt="Split Editor & Preview Mode" />

## Documentation

- [Markdown Syntax Guide](Resources/Initial/MiaoYan%20Markdown%20Syntax%20Guide.md) - Complete syntax reference with advanced features
- [PPT Presentation Mode](Resources/Initial/MiaoYan%20PPT.md) - Guide to creating presentations with `---` slide separators

## Support

- If MiaoYan improves your workflow, consider [supporting the project](https://miaoyan.app/cats.html)
- Star this repository on GitHub
- [Share MiaoYan](https://twitter.com/intent/tweet?text=%23MiaoYan%20-%20a%20lightweight%20Markdown%20editor%20for%20macOS,%20built%20with%20native%20Swift,%20featuring%20syntax%20highlighting,%20dark%20mode,%20and%20presentation%20mode.&url=https://github.com/tw93/MiaoYan) with others
- Follow [@HiTw93](https://twitter.com/HiTw93) for updates or join our [Telegram group](https://t.me/+GclQS9ZnxyI2ODQ1)

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
