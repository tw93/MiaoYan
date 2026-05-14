# V4.0.0

1. 新增 iPhone 和 iPad 版本,并与 macOS 使用统一 Bundle ID 和 Universal Purchase
2. 重做 iOS iCloud 冷启动、同步状态和本地文件读取,大库首次加载更稳
3. 优化 iOS 笔记卡片预览、搜索、阅读和编辑性能,减少列表跳动
4. 修复 Sparkle build 版本不一致导致同版本反复更新提示的问题
5. 修复 PDF 导出中 Mermaid 解析失败时输出大段错误面板的问题
6. 修复附件文件名包含空格或标点时 Markdown 图片预览失败的问题
7. 优化 macOS 26 侧边栏、笔记列表、设置窗口和现代工具栏视觉
8. 改进 macOS Split 模式预览重进、滚动条、切换和新建笔记状态
9. 加强保存、删除、版本历史和 Finder 打开场景的数据安全
10. 改进符号链接、iCloud placeholder 和带空格路径的加载性能

---

1. Add iPhone and iPad support with the unified Bundle ID and Universal Purchase
2. Rework iOS iCloud cold start, sync status, and local file reads for steadier first loads on large libraries
3. Improve iOS note card previews, search, reading, and editing performance to reduce list jumps
4. Fix repeated same-version Sparkle update prompts caused by build version drift
5. Fix PDF export when Mermaid parsing fails, preserving source instead of exporting the large error panel
6. Fix Markdown image previews when attachment filenames contain spaces or punctuation
7. Refine macOS 26 sidebar, notes list, settings window, and modern toolbar visuals
8. Improve macOS Split mode preview re-entry, scrollbars, mode switching, and new-note state
9. Strengthen save, delete, version history, and Finder-open data safety
10. Improve symlink, iCloud placeholder, and space-containing path loading performance
