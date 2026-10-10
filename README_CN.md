<div align="center">
  <a href="https://miaoyan.app/" target="_blank"><img src="https://raw.githubusercontent.com/tw93/MiaoYan/main/Resources/app.icon/Assets/43.png" width="138" /></a>
  <h1>妙言</h1>
  <p><b>轻灵的 Markdown 笔记本，伴你写出妙言</b></p>
  <p><a href="README.md">English</a> · 中文 · <a href="README_TW.md">繁體</a> · <a href="README_JA.md">日本語</a> · <a href="README_KR.md">한국어</a> · <a href="README_DE.md">Deutsch</a> · <a href="README_FR.md">Français</a></p>
  <a href="https://twitter.com/HiTw93" target="_blank"><img alt="Twitter 关注" src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter"></a>
  <a href="https://t.me/+9f9gf4ZrFSQ2OWVl" target="_blank"><img alt="Telegram 群组" src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram"></a>
  <a href="https://github.com/tw93/MiaoYan/releases" target="_blank"><img alt="GitHub 下载量" src="https://img.shields.io/github/downloads/tw93/MiaoYan/total.svg?style=flat-square"></a>
  <a href="https://github.com/tw93/MiaoYan/commits" target="_blank"><img alt="GitHub 提交活跃度" src="https://img.shields.io/github/commit-activity/m/tw93/MiaoYan?style=flat-square"></a>
  <a href="https://github.com/tw93/MiaoYan/issues?q=is%3Aissue+is%3Aclosed" target="_blank"><img alt="GitHub 已关闭议题" src="https://img.shields.io/github/issues-closed/tw93/MiaoYan.svg?style=flat-square"></a>
  <img alt="macOS 12.0+" src="https://img.shields.io/badge/macOS-12.0%2B-orange?style=flat-square">
</div>

<img src="https://raw.githubusercontent.com/tw93/static/master/miaoyan/newmiaoyan.gif" width="900px" />

## 特点

- **纯本地**：笔记就是你选定文件夹里的 Markdown 文件，不收集数据，要跨设备就交给 iCloud 云盘或坚果云同步
- **专注**：文件夹、笔记列表和编辑器分成三栏，带深色模式，不用维护插件
- **原生**：Swift 6 开发，比网页套壳更轻，分栏预览支持 60fps 双向滚动同步
- **够用**：双链、LaTeX 公式、Mermaid 图表、版本历史、自动排版和 PPT 演示都内置

## 安装使用

1. **Mac App Store**（付费，自动更新，含 iPhone 与 iPad 版）：

   <a href="https://apps.apple.com/cn/app/miaoyan/id6759252269"><img src="https://cdn.tw93.fun/uPic/C3Renh.png" width="160" alt="Download on the Mac App Store" /></a>

2. **Homebrew**：
   ```bash
   brew install --cask miaoyan
   ```

3. **GitHub Releases**：从 [GitHub Releases](https://github.com/tw93/MiaoYan/releases/latest) 下载最新 DMG（macOS 12.0+）

Homebrew 和 GitHub Releases 装的是开源版本，目前只修问题，App Store 版另外开发，新功能都在那边。

## 用坚果云或其他云盘同步妙言

妙言不会登录 WebDAV 或网盘账号，只读写你指定的 Markdown 文件夹，跨设备同步交给 iCloud 云盘、坚果云、Dropbox 等云盘客户端。安装后在 iCloud 云盘、坚果云桌面客户端的同步目录或其他位置创建 `MiaoYan` 文件夹，打开设置（⌘,）把存储位置指向它，就可以开始写了。

- **iPhone**：在系统“文件”App 中选择同一个云盘文件夹，云盘 App 没有提供可写文件夹的话，就用 iCloud 云盘，或先在云盘 App 里把该文件夹设为离线可用再选
- **目录检查**：妙言会在切换目录前确认文件夹可读写，不可用时保留原路径，也不会把问题误报成妙言自己的云同步失败

## 命令行工具

```bash
# 安装
curl -fsSL https://raw.githubusercontent.com/tw93/MiaoYan/main/scripts/install.sh | bash

# 使用
miao open <标题|路径>    # 打开笔记或文件夹
miao new <标题> [内容]   # 创建新笔记
miao search <关键词>     # 在终端搜索笔记
miao list [folder]      # 列出一级目录，或列出指定目录下的 Markdown
miao cat <标题|路径>     # 输出笔记内容
miao update             # 更新 CLI
```

## 分栏编辑预览模式

编辑区和预览区并排显示，按 `⌘\` 切换分栏模式，或在设置的通用页把编辑模式设为分栏模式。为什么不做 Typora 式所见即所得？我想让你一直看着 Markdown 原文写，用原生 Swift 做所见即所得很重，也难保证稳定，分栏模式能专心写字，旁边就是实时预览。

<img src="https://raw.githubusercontent.com/tw93/MiaoYan/main/assets/split-preview.png" width="100%" alt="分栏编辑预览模式" />

## 使用指南

- [介绍妙言](Resources/Initial/介绍妙言.md) - 使用说明和快捷键
- [Markdown 语法指南](Resources/Initial/妙言%20Markdown%20语法指南.md) - 语法演示，含数学公式和图表
- [PPT 演示模式](Resources/Initial/妙言%20PPT.md) - 使用 `---` 分隔幻灯片的演示指南
- [妙言 Agent Skill](skills/miaoyan) - 让 Agent 掌握妙言语法、附件、PPT 与 CLI 使用方式

运行 `npx skills add tw93/MiaoYan/skills/miaoyan -g` 安装官方 Skill。

## 支持

- 购买我做的 Mac 清理应用 [Mole for Mac](https://mole.fit)，是对我最直接的支持
- 如果你喜欢妙言，欢迎给它一个 Star，推荐给身边喜欢纯文本的朋友，[分享出去](https://twitter.com/intent/tweet?url=https://github.com/tw93/MiaoYan&text=%E5%A6%99%E8%A8%80%20-%20%E8%BD%BB%E7%81%B5%E7%9A%84%20Markdown%20%E7%AC%94%E8%AE%B0%E6%9C%AC%EF%BC%8C%E4%BC%B4%E4%BD%A0%E5%86%99%E5%87%BA%E5%A6%99%E8%A8%80)，或者提 issue 和 PR
- 我有两只猫，汤圆和可乐，若妙言让你开心，可以<a href="https://cats.tw93.fun?name=MiaoYan" target="_blank">请她们吃罐头 🥩</a>

<details>
<summary>这些可爱的朋友已经投喂过了 🐱</summary>
<br/>
<a href="https://cats.tw93.fun?name=MiaoYan"><img src="https://cdn.jsdelivr.net/gh/tw93/sponsors@main/assets/sponsors.svg" width="1000" loading="lazy" /></a>
</details>

## 致谢

- [glushchenko/fsnotes](https://github.com/glushchenko/fsnotes) - 项目初始结构参考
- [stackotter/swift-cmark-gfm](https://github.com/stackotter/swift-cmark-gfm) - Swift Markdown 解析器
- [simonbs/Prettier](https://github.com/simonbs/Prettier) - Markdown 格式化工具
- [raspu/Highlightr](https://github.com/raspu/Highlightr) - 语法高亮支持
- [hakimel/reveal.js](https://github.com/hakimel/reveal.js) - PPT 演示框架

## 协议

MIT License
