<div align="center">
  <a href="https://miaoyan.app/" target="_blank"><img src="https://raw.githubusercontent.com/tw93/MiaoYan/main/Resources/app.icon/Assets/43.png" width="138" /></a>
  <h1>妙言</h1>
  <p><b>輕靈的 Markdown 筆記本，伴你寫出妙言</b></p>
  <p><a href="README.md">English</a> · <a href="README_CN.md">中文</a> · 繁體 · <a href="README_JA.md">日本語</a> · <a href="README_KR.md">한국어</a> · <a href="README_DE.md">Deutsch</a> · <a href="README_FR.md">Français</a></p>
  <a href="https://twitter.com/HiTw93" target="_blank"><img alt="Twitter 追蹤" src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter"></a>
  <a href="https://t.me/+9f9gf4ZrFSQ2OWVl" target="_blank"><img alt="Telegram 群組" src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram"></a>
  <a href="https://github.com/tw93/MiaoYan/releases" target="_blank"><img alt="GitHub 下載量" src="https://img.shields.io/github/downloads/tw93/MiaoYan/total.svg?style=flat-square"></a>
  <a href="https://github.com/tw93/MiaoYan/commits" target="_blank"><img alt="GitHub 提交活躍度" src="https://img.shields.io/github/commit-activity/m/tw93/MiaoYan?style=flat-square"></a>
  <a href="https://github.com/tw93/MiaoYan/issues?q=is%3Aissue+is%3Aclosed" target="_blank"><img alt="GitHub 已關閉議題" src="https://img.shields.io/github/issues-closed/tw93/MiaoYan.svg?style=flat-square"></a>
  <img alt="macOS 12.0+" src="https://img.shields.io/badge/macOS-12.0%2B-orange?style=flat-square">
</div>

<img src="https://raw.githubusercontent.com/tw93/static/master/miaoyan/newmiaoyan.gif" width="900px" />

## 特點

- **純本地**：筆記就是你選定資料夾裡的 Markdown 檔案，不收集資料，要跨裝置就交給 iCloud 雲碟或堅果雲同步
- **專注**：資料夾、筆記列表和編輯器分成三欄，內建深色模式，不用維護外掛
- **原生**：Swift 6 開發，比網頁套殼更輕，分欄預覽支援 60fps 雙向捲動同步
- **夠用**：雙向連結、LaTeX 公式、Mermaid 圖表、版本歷史、自動排版和 PPT 簡報都內建

## 安裝使用

1. **Mac App Store**（付費，自動更新，含 iPhone 與 iPad 版）：

   <a href="https://apps.apple.com/cn/app/miaoyan/id6759252269"><img src="https://cdn.tw93.fun/uPic/C3Renh.png" width="160" alt="Download on the Mac App Store" /></a>

2. **Homebrew**：
   ```bash
   brew install --cask miaoyan
   ```

3. **GitHub Releases**：從 [GitHub Releases](https://github.com/tw93/MiaoYan/releases/latest) 下載最新 DMG（macOS 12.0+）

Homebrew 和 GitHub Releases 裝的是開源版本，目前只修問題。App Store 版另外開發，含 iPhone 與 iPad 版，新功能都在那邊。安裝後在 iCloud 雲碟、堅果雲桌面同步目錄或其他位置建立 `MiaoYan` 資料夾，開啟設定（⌘,）指定儲存位置，就可以開始寫了。

## 用堅果雲或其他雲端硬碟同步妙言

妙言保持本機優先，不會登入 WebDAV 或雲端硬碟帳號。它只讀寫你指定的 Markdown 資料夾，跨裝置同步由 iCloud 雲碟、堅果雲、Dropbox 等雲端硬碟用戶端負責。

- **Mac**：在堅果雲桌面用戶端的同步目錄中建立 `MiaoYan` 資料夾，然後在妙言設定中將儲存位置指向它。
- **iPhone**：在系統「檔案」App 中選擇同一個雲端硬碟資料夾。若某個雲端硬碟 App 沒有提供可寫入資料夾，建議使用 iCloud 雲碟，或先在雲端硬碟 App 中讓該資料夾可離線存取後再選擇。
- **目錄檢查**：妙言會在切換目錄前確認資料夾可讀取、可寫入。無法使用時不會儲存新路徑，也不會將問題誤報為妙言自己的雲端同步失敗。

## 命令列工具

妙言提供命令列工具，方便在終端機中快速操作筆記。

```bash
# 安裝
curl -fsSL https://raw.githubusercontent.com/tw93/MiaoYan/main/scripts/install.sh | bash

# 使用
miao open <標題|路徑>    # 開啟筆記或資料夾
miao new <標題> [內容]   # 建立新筆記
miao search <關鍵字>     # 在終端機搜尋筆記
miao list [folder]      # 列出一級目錄，或列出指定目錄下的 Markdown
miao cat <標題|路徑>     # 輸出筆記內容
miao update             # 更新 CLI
```

## 分欄編輯預覽模式

編輯區與預覽區並排顯示，支援 60fps 雙向捲動同步，即時預覽編輯效果。

**快速切換**：按 `⌘\` 即可快速切換分欄模式，或在設定的通用頁將編輯模式設為分欄模式。

為什麼不做 Typora 式所見即所得？我想讓你一直看著 Markdown 原文寫，用原生 Swift 做所見即所得很重，也難保證穩定，分欄模式能專心寫字，旁邊就是即時預覽。

<img src="https://raw.githubusercontent.com/tw93/MiaoYan/main/assets/split-preview.png" width="100%" alt="分欄編輯預覽模式" />

## 使用指南

- [介紹妙言](Resources/Initial/介绍妙言.md) - 完整使用指南，包含快捷鍵等
- [Markdown 語法指南](Resources/Initial/妙言%20Markdown%20语法指南.md) - 完整語法示範，數學公式、圖表等
- [PPT 簡報模式](Resources/Initial/妙言%20PPT.md) - 使用 `---` 分隔投影片的簡報指南
- [妙言 Agent Skill](skills/miaoyan) - 讓 Agent 掌握妙言語法、附件、PPT 與 CLI 使用方式

執行 `npx skills add tw93/MiaoYan/skills/miaoyan -g` 安裝官方 Skill。

## 支持

1. 購買我製作的 Mac 清理工具 [Mole for Mac](https://mole.fit)，是對我最直接的支持。
2. 如果你喜歡妙言，歡迎給它一個 Star，也歡迎推薦給身邊喜歡純文字的朋友。
3. 可以追蹤我的 [Twitter](https://twitter.com/HiTw93) 取得最新動態，也歡迎加入 [Telegram](https://t.me/+9f9gf4ZrFSQ2OWVl) 群組。
4. 我有兩隻貓：湯圓、可樂，若妙言讓你開心，<a href="https://cats.tw93.fun" target="_blank">請牠們吃罐頭 🥩</a>。

## 致謝

- [glushchenko/fsnotes](https://github.com/glushchenko/fsnotes) - 專案初始結構參考
- [stackotter/swift-cmark-gfm](https://github.com/stackotter/swift-cmark-gfm) - Swift Markdown 解析器
- [simonbs/Prettier](https://github.com/simonbs/Prettier) - Markdown 格式化工具
- [raspu/Highlightr](https://github.com/raspu/Highlightr) - 語法高亮支援
- [hakimel/reveal.js](https://github.com/hakimel/reveal.js) - PPT 簡報框架

## 授權

MIT License - 歡迎自由使用與貢獻
