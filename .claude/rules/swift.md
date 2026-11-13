---
paths:
  - "**/*.swift"
---

# MiaoYan Swift Rules

> 只写 MiaoYan 特有的部分。通用的 Swift 内存与线程纪律按常规来,不在这里重复。

## AppKit vs SwiftUI

- macOS 主 app 的编辑器核心(`EditTextView`)和预览管线(`MPreviewView`)保持 AppKit,不要重写。app 外壳(窗口、侧栏、列表、设置、菜单命令)在 `Shell/` 里迁往 SwiftUI,以 `-MiaoYanShell YES` 打开,storyboard 窗口在外壳达到对等前保持可发布,具体约束见 `.claude/rules/shell.md`。
- **新增的独立面板**(版本 diff 视图、quick-open、大纲侧栏这类自包含 UI)允许用 `NSHostingView` 挂 SwiftUI,这是维护者 2026-07 定下的下一代方向边界;不要以此为由把 SwiftUI 渗进 EditTextView / MPreviewView / ViewController 热路径。

## Threading

- 文件 IO、版本历史、Mermaid 渲染、PDF 导出走后台队列。大笔记 / 大预览**不允许**主线程同步读。
- AppKit 在指定队列上调用的闭包（`NSFilePromiseReceiver.receivePromisedFiles` 的 reader 这类）不要内联写在 `@MainActor` 类型里，Swift 6 下它会继承主 actor 隔离，后台队列一调用就在隔离检查上 trap：拖照片进编辑器的第一版即如此，发布前在沙盒测试包上崩出来（#578）。在 `nonisolated static` 函数里构造并返回 `@Sendable` 闭包，只捕获主 actor 上的对象，再 `Task { @MainActor in }` 回主线程，参照 `PromiseArrivals.reader`，测试从后台 `OperationQueue` 调用它。

## CJK 文本处理

- Swift 源码和测试里写**全角标点**(,;:!?()等有半角孪生的字符)一律用 `\u{FF0C}` 这类 unicode 转义,不要写字面量。字面量在生成/编辑过程中极易退化成半角且 review 看不出来,这个坑在 TypographyCleaner 上真实发生过:集合里混入半角逗号,导致英文句子的空格被误删。无半角孪生的字符(。、「」……)可以写字面量。
- 处理可能含 CRLF 的文本时记住 `"\r\n"` 是单个 grapheme:`content[i] == "\n"` 和 `range(of: "\n...")` 都匹配不到它,需要显式加 `"\r\n"` 分支或双 needle 搜索。
