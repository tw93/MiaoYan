# MiaoYan - Claude AI Assistant Guide

## 项目概述

MiaoYan (妙言) 是一款轻量级的 macOS Markdown 编辑器，使用 Swift 5 原生开发。它提供了简洁美观的 3 列布局界面：文件夹 + 文件列表 + 编辑器，支持实时预览、语法高亮、黑暗模式、PPT 演示等功能。

### 核心特性

- 🏂 **功能丰富**：纯本地使用、语法高亮、黑暗模式、演示模式、PPT 模式、文档导出、LaTeX、Mermaid、PlantUML 支持
- 🎊 **界面美观**：极简设计风格，3 列布局
- 🚄 **性能优秀**：Swift 5 原生开发，高性能体验
- 🥛 **使用简洁**：轻量级，快捷键丰富

## 项目架构

### 目录结构

```
MiaoYan/
├── Mac/                          # macOS 主要源代码
│   ├── Business/                 # 业务逻辑层
│   ├── View/                     # UI 视图组件
│   ├── Extensions/               # Swift 扩展
│   ├── Helpers/                  # 工具类
│   └── Images.xcassets/          # 图片资源
├── Common/                       # 共享代码
├── Resources/                    # 资源文件
│   ├── DownView.bundle/          # Web 视图资源 (CSS/JS)
│   ├── Fonts/                    # 自定义字体
│   ├── Initial/                  # 初始示例文档
│   └── Prettier.bundle/          # 代码格式化资源
├── Release/                      # 发布版本
└── Pods/                         # CocoaPods 依赖
```

## 技术栈

### 核心技术

- **开发语言**: Swift 5
- **UI 框架**: AppKit (macOS 原生)
- **依赖管理**: Swift Package Manager
- **最低支持**: macOS 11.5+

### 主要依赖 (Swift Package Manager)

```swift
// 自动更新框架
.package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.7.1")

// 应用分析和崩溃报告
.package(url: "https://github.com/microsoft/appcenter-sdk-apple.git", from: "5.0.6")

// HTTP 网络请求库
.package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.2")

// JSON 解析库
.package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.2")

// 代码语法高亮
.package(url: "https://github.com/raspu/Highlightr.git", from: "2.3.0")

// ZIP 文件压缩和解压
.package(url: "https://github.com/ZipArchive/ZipArchive.git", from: "2.6.0")

// GitHub Flavored Markdown 解析库
.package(url: "https://github.com/stackotter/swift-cmark-gfm", from: "1.0.2")

// 全局键盘快捷键
.package(url: "https://github.com/shpakovski/MASShortcut.git", branch: "master")
```

## 核心模块

### 1. 业务逻辑 (Business/)

- `Note.swift` - 笔记数据模型
- `Project.swift` - 项目/文件夹管理
- `Storage.swift` - 文件存储管理
- `Markdown.swift` - Markdown 处理
- `LanguageType.swift` - 编程语言类型定义

### 2. 视图组件 (View/)

- `EditTextView.swift` - 主编辑器视图
- `MPreviewView.swift` - Markdown 预览视图
- `NotesTableView.swift` - 文件列表视图
- `SidebarProjectView.swift` - 侧边栏项目视图
- `EditorView.swift` - 编辑器容器视图

### 3. 主要控制器

- `ViewController.swift` - 主视图控制器
- `MainWindowController.swift` - 主窗口控制器
- `AppDelegate.swift` - 应用委托
- `PrefsViewController.swift` - 偏好设置控制器

### 4. 工具类 (Helpers/)

- `TextFormatter.swift` - 文本格式化
- `ImagesProcessor.swift` - 图片处理
- `FileSystemEventManager.swift` - 文件系统监听
- `UserDefaultsManagement.swift` - 用户设置管理

## 构建和开发

### 环境要求

- Xcode 12.0+
- Swift 5.0+
- macOS 11.5+ (开发环境)

### 构建步骤

```bash
# 1. 克隆项目
git clone https://github.com/tw93/MiaoYan.git
cd MiaoYan

# 2. 打开项目 (依赖会自动解析)
open MiaoYan.xcodeproj

# 3. 在 Xcode 中构建和运行
# Xcode 会自动通过 Swift Package Manager 下载和管理依赖
```

### 代码规范

- 项目已迁移到 Swift Package Manager，不再使用 SwiftLint 作为 Pod 依赖
- 遵循 Swift 官方代码规范
- 变量和函数使用驼峰命名法
- 类名使用大驼峰命名法
- 不要出现大量的注释，对于代码看得懂的，可以不要注释，假如有注释地方使用英文

## 关键功能实现

### 1. Markdown 渲染

- 使用 `swift-cmark-gfm` 解析 GitHub Flavored Markdown
- `Highlightr` 提供语法高亮支持
- 支持 LaTeX 数学公式、Mermaid 图表、PlantUML 等

### 2. 文件管理

- 基于文件系统的笔记存储
- 支持文件夹嵌套和文件监听
- 自动保存和版本控制

### 3. 编辑器功能

- 实时预览
- 代码语法高亮
- 快捷键支持
- 自动格式化 (Prettier 集成)

### 4. PPT 演示模式

- 基于 Reveal.js 框架
- 支持 Markdown 语法的幻灯片
- 使用 `---` 分隔符分页

## 常用快捷键

### 窗口操作

- `Cmd + 1` - 收起/展开目录
- `Cmd + 2` - 收起/展开文档列表
- `Cmd + 3` - 切换编辑和预览
- `Cmd + 4` - 切换到演示模式
- `Cmd + Option + M` - 全局唤起/隐藏

### 文档操作

- `Cmd + N` - 新建文档
- `Cmd + R` - 重命名文档
- `Cmd + D` - 复制文档
- `Cmd + Delete` - 删除文档
- `Cmd + Shift + N` - 新建文件夹
- `Cmd + Shift + L` - 自动排版
- `Cmd + Option + P` - 启动 PPT 预览

## 开发建议

### 代码修改指南

1. **视图修改**: 主要在 `Mac/View/` 目录下的 Swift 文件
2. **业务逻辑**: 修改 `Mac/Business/` 目录下的模型文件
3. **UI 样式**: 修改 `Resources/DownView.bundle/css/` 下的样式文件
4. **快捷键**: 在 `AppDelegate.swift` 或相关视图控制器中添加

### 测试和调试

- 使用 Xcode 内置调试器
- 检查 AppCenter 崩溃报告
- 关注控制台日志输出
- 测试不同 macOS 版本兼容性

### 发布流程

1. 更新版本号 (`Info.plist`)
2. 运行完整测试
3. 使用 SwiftLint 检查代码规范
4. 构建 Release 版本
5. 使用 Sparkle 框架推送更新

## 资源文件

### Web 资源 (DownView.bundle/)

- `highlight.min.js` - 代码高亮
- `katex.min.js` - LaTeX 渲染
- `mermaid.min.js` - 图表渲染
- `markmap-view.min.js` - 思维导图
- 各种 CSS 主题文件

### 字体资源

- `LXGWWenKaiScreen.ttf` - 霞鹜文楷屏幕阅读版 (默认中文字体)
- `TsangerJinKai02-W04.ttf` - 仓耳今楷 02 (备选字体)

## 国际化支持

- 支持中文 (简体/繁体)、英文、日文
- 本地化文件在各语言的 `.lproj` 目录下
- 字符串本地化使用 `NSLocalizedString`

## 贡献指南

### 代码贡献

1. Fork 项目
2. 创建功能分支
3. 遵循代码规范
4. 提交 Pull Request
5. 通过代码审查

### 问题反馈

- 使用 GitHub Issues 报告 Bug
- 提供详细的复现步骤
- 包含系统版本和应用版本信息

## 相关链接

- [官方网站](https://miaoyan.app/)
- [GitHub 仓库](https://github.com/tw93/MiaoYan)
- [发布页面](https://github.com/tw93/MiaoYan/releases)
- [作者 Twitter](https://twitter.com/HiTw93)

---

_此文档最后更新: 2025-08-05_
_MiaoYan 版本: 基于最新开发分支_
