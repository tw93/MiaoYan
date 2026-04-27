# V3.3.0 Glavenus 🦕

## Changelog
1. PDF export now produces real paginated output: properly sized A4 pages with margins, heading bookmarks, and correct rendering of images and diagrams — no more endless single-column scrolls
2. Split view scroll sync upgraded to line-based algorithm, keeping editor and preview locked in position even in documents with images or code blocks
3. Symbolic link directories now work in the sidebar without duplication, and opening a single .md from Finder shows all sibling files as expected
4. Switching to large notes no longer blocks the UI — content loads asynchronously so the app stays responsive
5. Cmd+E wraps selected text as inline code; Shift+Cmd+E wraps it in a fenced code block

## 更新日志
1. PDF 导出终于真正分页了：标准 A4 尺寸、留白边距、标题生成书签，图片和图表也能正确渲染，再也不是一张拉很长的滚动页
2. 分栏滚动从比例模式升级为行级同步，含图片或代码块的文档也能精准对齐，不再偏位
3. 符号链接目录在侧栏正常显示不重复，从 Finder 打开单个 .md 也能看到同目录所有文件
4. 切换大文件时主线程不再卡顿，内容异步加载，界面保持流畅
5. Cmd+E 格式化行内代码，Shift+Cmd+E 包裹代码块
