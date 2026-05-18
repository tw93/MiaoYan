# V4.0.0

1. 新增 iPhone 和 iPad 版本,并与 macOS 使用统一 Bundle ID 和 Universal Purchase
2. iPad 改为文件夹边栏、笔记列表、阅读详情的三栏布局,不再是放大的手机界面
3. iOS 新增设置页,集中管理阅读字体、iCloud 资料库文件夹和版本信息
4. iOS 支持置顶笔记,可滑动或长按操作,与 macOS 使用一致的置顶机制
5. 重做 iOS iCloud 冷启动、同步状态和本地文件读取,大库首次加载更稳
6. 优化 iOS 笔记卡片预览、搜索、阅读和编辑性能,减少列表跳动
7. macOS 新增"切换目录"菜单项和 cmd+5 快捷键,目录不再只能靠悬停触发
8. 修复 Sparkle build 版本不一致导致同版本反复更新提示的问题
9. 修复 PDF 导出中 Mermaid 解析失败时输出大段错误面板的问题
10. 修复附件文件名包含空格或标点时 Markdown 图片预览失败的问题
11. 优化 macOS 26 侧边栏、笔记列表、设置窗口和现代工具栏视觉
12. 改进 macOS Split 模式预览重进、滚动条、切换和新建笔记状态
13. 加强保存、删除、版本历史和 Finder 打开场景的数据安全,并改进符号链接、iCloud placeholder 和带空格路径的加载性能

---

1. Add iPhone and iPad support with the unified Bundle ID and Universal Purchase
2. Give iPad a three-column layout (folder sidebar, note list, reading detail) instead of a stretched phone UI
3. Add an iOS settings screen for reading font size, the iCloud library folder, and version info
4. Add pinned notes on iOS via swipe or long-press, using the same pin mechanism as macOS
5. Rework iOS iCloud cold start, sync status, and local file reads for steadier first loads on large libraries
6. Improve iOS note card previews, search, reading, and editing performance to reduce list jumps
7. Add a "Toggle TOC" menu item and cmd+5 shortcut on macOS so the table of contents is no longer hover-only
8. Fix repeated same-version Sparkle update prompts caused by build version drift
9. Fix PDF export when Mermaid parsing fails, preserving source instead of exporting the large error panel
10. Fix Markdown image previews when attachment filenames contain spaces or punctuation
11. Refine macOS 26 sidebar, notes list, settings window, and modern toolbar visuals
12. Improve macOS Split mode preview re-entry, scrollbars, mode switching, and new-note state
13. Strengthen save, delete, version history, and Finder-open data safety, and improve symlink, iCloud placeholder, and space-containing path loading performance
