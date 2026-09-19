# MiaoYan Swift Rules

> 只写 MiaoYan 特有的部分。通用的 Swift 内存与线程纪律按常规来,不在这里重复。

## AppKit vs SwiftUI

- macOS 主 app 的编辑器核心、预览管线、既有窗口和 storyboard 场景保持 AppKit + NSViewController/NSWindowController,不要重写。
- **新增的独立面板**(版本 diff 视图、quick-open、大纲侧栏这类自包含 UI)允许用 `NSHostingView` 挂 SwiftUI,这是维护者 2026-07 定下的下一代方向边界;不要以此为由把 SwiftUI 渗进 EditTextView / MPreviewView / ViewController 热路径。
- `MiaoYanMobile/` 是 iOS target,一律 SwiftUI。它有自己的 models 和 services,不编译 `Business/`;两端只共享文件系统约定,UI 层同样不跨 target 共享。

## Threading

- 文件 IO、版本历史、Mermaid 渲染、PDF 导出走后台队列。大笔记 / 大预览**不允许**主线程同步读。

## CJK 文本处理

- Swift 源码和测试里写**全角标点**(,;:!?()等有半角孪生的字符)一律用 `\u{FF0C}` 这类 unicode 转义,不要写字面量。字面量在生成/编辑过程中极易退化成半角且 review 看不出来,这个坑在 TypographyCleaner 上真实发生过:集合里混入半角逗号,导致英文句子的空格被误删。无半角孪生的字符(。、「」……)可以写字面量。
- 处理可能含 CRLF 的文本时记住 `"\r\n"` 是单个 grapheme:`content[i] == "\n"` 和 `range(of: "\n...")` 都匹配不到它,需要显式加 `"\r\n"` 分支或双 needle 搜索。
