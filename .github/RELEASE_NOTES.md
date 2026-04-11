# V3.2.0 Zinogre ⚡

## Changelog
1. Faster preview: Two-phase rendering shows text instantly while local images load lazily in the background, cutting perceived latency significantly
2. Open in Terminal: New Cmd+J shortcut opens the current folder in Terminal from anywhere in the app, with a folder context menu entry as well
3. Copy Path: Right-click any note to copy its full file path to the clipboard
4. Spanish localization: Full Spanish (es) UI translation covering all menus, settings, and system strings
5. Mermaid upgraded to v11.14.0, fixing subgraph edge rendering and adding new diagram features
6. Live reload fixed: Notes modified by external tools now reload correctly, including files inside symlinked directories
7. Export reliability: Fixed blank preview on note switch, PPT/Presentation mode exit timing, and export timeout handling
8. Concurrency fixes: Resolved ExportCache data race, scoped URL leaks, and stale-note assignment after async rendering

## 更新日志
1. 预览更快：两阶段渲染让文字立即显示，本地图片在后台懒加载，明显减少预览首屏等待时间
2. 终端快捷入口：新增 Cmd+J 全局快捷键，随时打开当前文件夹所在终端，文件夹右键菜单也有对应入口
3. 复制路径：右键任意笔记可直接复制完整文件路径
4. 西班牙语本地化：完整覆盖菜单、设置页和系统字符串的西班牙语翻译
5. Mermaid 升级至 v11.14.0，修复子图连线渲染问题并新增图表功能
6. 实时重载修复：其他工具修改的笔记现在能正确触发重载，含符号链接目录内的文件（closes #502）
7. 导出稳定性：修复切换笔记时预览空白、PPT 演示模式退出时序混乱、导出超时处理异常等问题
8. 并发安全：修复 ExportCache 数据竞争、安全作用域 URL 泄漏、异步渲染后笔记状态错乱等问题
