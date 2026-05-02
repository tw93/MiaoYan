<h4 align="right"><strong><a href="https://github.com/tw93/MiaoYan">English</a></strong> | 简体中文</h4>

<p align="center">
  <a href="https://miaoyan.app/" target="_blank"><img src="https://gw.alipayobjects.com/zos/k/t0/43.png" width="138" /></a>
  <h1 align="center">妙言</h1>
  <div align="center">
    <a href="https://twitter.com/HiTw93" target="_blank">
      <img alt="Twitter 关注" src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter"></a>
    <a href="https://t.me/+GclQS9ZnxyI2ODQ1" target="_blank">
      <img alt="Telegram 群组" src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram"></a>
    <a href="https://github.com/tw93/MiaoYan/releases" target="_blank">
      <img alt="GitHub 下载量" src="https://img.shields.io/github/downloads/tw93/MiaoYan/total.svg?style=flat-square"></a>
    <a href="https://github.com/tw93/MiaoYan/commits" target="_blank">
      <img alt="GitHub 提交活跃度" src="https://img.shields.io/github/commit-activity/m/tw93/MiaoYan?style=flat-square"></a>
    <a href="https://github.com/tw93/MiaoYan/issues?q=is%3Aissue+is%3Aclosed" target="_blank">
      <img alt="GitHub 已关闭议题" src="https://img.shields.io/github/issues-closed/tw93/MiaoYan.svg?style=flat-square"></a>
    <img alt="macOS 11.5+" src="https://img.shields.io/badge/macOS-11.5%2B-orange?style=flat-square">
  </div>
  <div align="center">轻灵的 Markdown 笔记本伴你写出妙言</div>
</p>

<img src="https://raw.githubusercontent.com/tw93/static/master/miaoyan/newmiaoyan.gif" width="900px" />

## 特点

- **妙**：纯本地使用、不收集任何数据、语法高亮、分栏编辑预览、Wikilink 双向链接、PPT 演示、LaTeX、Mermaid 图表
- **美**：极简设计风格、三栏模式、深色模式、macOS 26 玻璃质感、专注写作
- **快**：Swift 6 原生开发、相比 Web 套壳性能体验更好
- **简**：轻量纯粹、版本历史、众多快捷键、自动排版

## 安装使用

1. **Mac App Store**(付费,自动更新):

   <a href="https://apps.apple.com/cn/app/miaoyan/id6759252269"><img src="https://cdn.tw93.fun/uPic/C3Renh.png" width="160" alt="Download on the Mac App Store" /></a>

2. **Homebrew**:
   ```bash
   brew install --cask miaoyan
   ```

3. **GitHub Releases**: 从 [GitHub Releases](https://github.com/tw93/MiaoYan/releases/latest) 下载最新 DMG(macOS 11.5+)

三种方式共享同一份代码,功能完全一致,同步更新。安装后在 iCloud 云盘或其他位置创建 `MiaoYan` 文件夹,打开设置 (⌘,) 指定存储位置,就可以开始写了。

## 命令行工具

妙言提供命令行工具，方便在终端中快速操作笔记。

```bash
# 安装
curl -fsSL https://raw.githubusercontent.com/tw93/MiaoYan/main/scripts/install.sh | bash

# 使用
miao open <标题|路径>    # 打开笔记
miao new <标题> [内容]   # 创建新笔记
miao search <关键词>     # 在终端搜索笔记
miao list [folder]      # 列出一级目录，或列出指定目录下的 Markdown
miao cat <标题|路径>     # 输出笔记内容
miao update             # 更新 CLI
```

## 分栏编辑预览模式

编辑区和预览区并排显示，支持 60fps 双向滚动同步，实时预览编辑效果。

**快速切换**：按 `⌘\` 即可快速切换分栏模式，或在设置 → 界面 → 编辑模式 → 分栏模式中开启。

为什么不做 Typora 式即时预览？我们追求纯粹的 Markdown 编辑体验，用 Swift 原生实现即时预览过于复杂且稳定性难以保证。分栏模式在保持纯净编辑体验的同时，提供了实时的视觉反馈。

<img src="https://gw.alipayobjects.com/zos/k/eg/jV8Gra.png" width="100%" alt="分栏编辑预览模式" />

## 使用指南

- [介绍妙言](Resources/Initial/介绍妙言.md) - 完整使用指南,包含快捷键等
- [Markdown 语法指南](Resources/Initial/妙言%20Markdown%20语法指南.md) - 完整语法演示,数学公式、图表等
- [PPT 演示模式](Resources/Initial/妙言%20PPT.md) - 使用 `---` 分隔幻灯片的演示指南

## 支持

1. 我有两只猫：汤圆、可乐，若妙言让你开心，<a href="https://miaoyan.app/cats.html" target="_blank">请她们吃罐头 🥩</a>。
2. 如果你喜欢妙言，欢迎给它一个 Star，更欢迎推荐给你志同道合的朋友使用。
3. 可以关注我的 [Twitter](https://twitter.com/HiTw93) 获取最新的更新消息，也欢迎加入 [Telegram](https://t.me/+GclQS9ZnxyI2ODQ1) 聊天群。

## 致谢

- [glushchenko/fsnotes](https://github.com/glushchenko/fsnotes) - 项目初始结构参考
- [stackotter/swift-cmark-gfm](https://github.com/stackotter/swift-cmark-gfm) - Swift Markdown 解析器
- [simonbs/Prettier](https://github.com/simonbs/Prettier) - Markdown 格式化工具
- [raspu/Highlightr](https://github.com/raspu/Highlightr) - 语法高亮支持
- [仓耳字库](https://tsanger.cn/product) - 仓耳今楷字体(默认字体)
- [hakimel/reveal.js](https://github.com/hakimel/reveal.js) - PPT 演示框架
## 协议

MIT License - 欢迎自由使用与贡献
