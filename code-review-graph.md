# MiaoYan 代码审查图谱

## 项目概览

**MiaoYan** 是一个基于 Swift 6 + AppKit 的 macOS Markdown 编辑器，采用本地优先的文件存储架构。

---

## 1. 架构分层图

```mermaid
flowchart TB
    subgraph UI层["UI 层 (Controllers + Views)"]
        AD[AppDelegate<br/>应用生命周期管理]
        MWC[MainWindowController<br/>主窗口控制]
        VC[ViewController<br/>核心视图控制器]
        ETW[EditTextView<br/>编辑器视图]
        MPV[MPreviewView<br/>预览视图]
        SV[SidebarProjectView<br/>侧边栏视图]
        NTV[NotesTableView<br/>笔记列表视图]
    end

    subgraph 业务层["业务逻辑层 (Business)"]
        AC[AppContext<br/>应用上下文]
        ST[Storage<br/>存储管理器]
        NT[Note<br/>笔记模型]
        PR[Project<br/>项目/文件夹模型]
        SB[Sidebar<br/>侧边栏逻辑]
        SI[SidebarItem<br/>侧边栏项]
        ESS[EditorSessionState<br/>编辑器状态]
    end

    subgraph 辅助层["辅助层 (Helpers)"]
        UD[UserDefaultsManagement<br/>配置管理]
        TM[Theme<br/>主题管理]
        I18[Localization<br/>本地化]
        NP[NotesTextProcessor<br/>文本处理]
        CBH[CodeBlockHighlighter<br/>代码高亮]
        FSE[FileSystemEventManager<br/>文件系统监听]
        IPM[ImagePreviewManager<br/>图片预览]
    end

    subgraph 扩展层["扩展层 (Extensions)"]
        EXT1[String+.swift]
        EXT2[NSColor+.swift]
        EXT3[URL+.swift]
        EXT4[NSTextStorage+.swift]
    end

    UI层 --> 业务层
    业务层 --> 辅助层
    UI层 --> 扩展层
    辅助层 --> 扩展层
```

---

## 2. 核心依赖关系图

```mermaid
flowchart LR
    subgraph 入口点["应用入口"]
        AD["AppDelegate<br/>@main"]
    end

    subgraph 核心控制器["核心控制器"]
        VC["ViewController<br/>~1200行"]
        MWC["MainWindowController"]
    end

    subgraph 上下文["全局上下文"]
        AC["AppContext.shared<br/>单例"]
        ESS["EditorSessionState"]
    end

    subgraph 数据管理["数据管理层"]
        ST["Storage<br/>笔记存储"]
        NT["Note<br/>笔记模型"]
        PR["Project<br/>项目模型"]
    end

    subgraph 视图组件["视图组件"]
        ETW["EditTextView<br/>编辑器"]
        MPV["MPreviewView<br/>预览"]
        SBV["SidebarProjectView<br/>侧边栏"]
        NTV["NotesTableView<br/>笔记列表"]
    end

    AD --> MWC
    MWC --> VC
    VC --> AC
    AC --> ST
    AC --> ESS
    ST --> NT
    ST --> PR
    VC --> ETW
    VC --> MPV
    VC --> SBV
    VC --> NTV
    ETW --> NT
```

---

## 3. 数据流图

```mermaid
sequenceDiagram
    participant User as 用户
    participant VC as ViewController
    participant ST as Storage
    participant NT as Note
    participant FS as 文件系统

    User->>VC: 打开应用
    VC->>ST: loadProjects()
    ST->>FS: 读取目录结构
    FS-->>ST: 文件列表
    ST->>ST: 创建 Note 对象
    ST->>VC: 返回笔记列表
    VC->>VC: 更新 UI

    User->>VC: 编辑笔记
    VC->>NT: save(content)
    NT->>NT: debounceSave(1.5s)
    NT->>FS: 写入文件
    FS-->>NT: 保存完成

    User->>VC: 切换预览
    VC->>VC: togglePreview()
    VC->>MPV: updateContent()
    MPV-->>VC: 渲染完成
```

---

## 4. 模块复杂度热力图

| 模块 | 文件数 | 代码行数 | 复杂度 | 风险等级 |
|------|--------|----------|--------|----------|
| **ViewController** | 5个扩展文件 | ~1500行 | 🔴 高 | 核心逻辑过于集中 |
| **EditTextView** | 1 | ~800行 | 🟡 中高 | 编辑器核心 |
| **Storage** | 1 | ~1100行 | 🟡 中高 | 文件管理逻辑复杂 |
| **Note** | 1 | ~980行 | 🟡 中 | 模型职责较多 |
| **Business** | 10 | ~2500行 | 🟢 中 | 相对均衡 |
| **Helpers** | 20+ | ~3000行 | 🟢 中 | 工具函数分散 |
| **Views** | 20+ | ~3500行 | 🟢 中 | UI组件较多 |

---

## 5. 关键问题识别

### 5.1 🚨 高风险区域

```mermaid
flowchart TD
    subgraph 问题1["ViewController 臃肿"]
        A["ViewController.swift<br/>1216行"]
        B["ViewController+Action.swift<br/>操作处理"]
        C["ViewController+Data.swift<br/>数据逻辑"]
        D["ViewController+Editor.swift<br/>编辑器逻辑"]
        E["ViewController+Layout.swift<br/>布局逻辑"]
    end

    subgraph 问题2["状态管理分散"]
        F["UserDefaultsManagement<br/>200+ 配置项"]
        G["EditorSessionState<br/>运行时状态"]
        H["AppContext<br/>全局上下文"]
    end

    subgraph 问题3["隐式依赖"]
        I["EditTextView.note<br/>静态变量"]
        J["Storage.sharedInstance<br/>全局单例"]
    end

    style A fill:#ff6b6b,stroke:#c92a2a,stroke-width:2px
    style F fill:#ffd43b,stroke:#f76707,stroke-width:2px
    style I fill:#ff6b6b,stroke:#c92a2a,stroke-width:2px
```

### 5.2 代码异味清单

| 问题 | 位置 | 影响 | 建议 |
|------|------|------|------|
| **静态变量依赖** | `EditTextView.note` | 全局状态难以测试 | 改为依赖注入 |
| **单例过度使用** | `Storage.sharedInstance()` | 紧耦合 | 考虑协议抽象 |
| **VC 职责过重** | `ViewController` 及扩展 | 维护困难 | 拆分为多个 Coordinator |
| **延期计算属性** | `Note.content` | 懒加载陷阱 | 明确加载时机 |
| **强制解包** | 多处 `!` 使用 | 潜在崩溃 | 使用 Optional 链 |

---

## 6. 推荐审查优先级

```mermaid
flowchart LR
    subgraph P0["P0 - 立即审查"]
        P0_1["ViewController.swift<br/>主逻辑"]
        P0_2["Note.swift<br/>保存逻辑"]
        P0_3["Storage.swift<br/>文件操作"]
    end

    subgraph P1["P1 - 重要"]
        P1_1["EditTextView.swift<br/>编辑器"]
        P1_2["MPreviewView.swift<br/>预览"]
        P1_3["AppDelegate.swift<br/>生命周期"]
    end

    subgraph P2["P2 - 一般"]
        P2_1["Helpers/*<br/>工具类"]
        P2_2["Views/*<br/>UI组件"]
        P2_3["Extensions/*<br/>扩展"]
    end

    style P0 fill:#ff6b6b,stroke:#c92a2a
    style P1 fill:#ffd43b,stroke:#f76707
    style P2 fill:#69db7c,stroke:#2b8a3e
```

---

## 7. 测试覆盖建议

```mermaid
flowchart TB
    subgraph 单元测试优先级["单元测试优先级"]
        T1["Note.save()<br/>文件保存"]
        T2["Storage.loadLabel()<br/>笔记加载"]
        T3["EditorSessionState<br/>状态管理"]
        T4["Project<br/>项目模型"]
    end

    subgraph 集成测试["集成测试场景"]
        I1["新建笔记 → 编辑 → 保存"]
        I2["切换项目 → 加载笔记列表"]
        I3["预览模式切换"]
        I4["文件系统变更监听"]
    end

    T1 --> I1
    T2 --> I2
    T3 --> I3
```

---

## 8. 架构改进建议

### 8.1 短期优化
1. **拆分 ViewController**: 将 Action/Data/Editor/Layout 逻辑拆分为独立 Coordinator
2. **统一状态管理**: 将分散在 UserDefaultsManagement 和 EditorSessionState 的状态合并
3. **消除静态变量**: 移除 `EditTextView.note` 等静态引用

### 8.2 中期重构
1. **引入 Repository 模式**: Storage 层抽象为协议，便于测试
2. **MVVM 迁移**: ViewController 减负，引入 ViewModel 层
3. **事件总线**: 使用 NotificationCenter 或 Combine 解耦组件通信

### 8.3 长期演进
1. **SwiftUI 迁移**: 逐步替换 AppKit 视图
2. **插件架构**: 支持扩展机制
3. **数据持久化**: Core Data 或 SwiftData 替代文件系统直接操作

---

## 9. 文件依赖矩阵

```
                    AppDelegate  ViewController  Storage  Note  Project  EditTextView
AppDelegate              -            ✅          ✅       -       -          -
ViewController            ✅           -           ✅      ✅      ✅         ✅
Storage                   -            ✅          -       ✅      ✅          -
Note                      -            ✅          ✅      -       ✅          ✅
Project                   -            ✅          ✅      ✅      -           -
EditTextView              -            ✅          -       ✅      -           -
```

---

*生成时间: 2026-03-19*
*版本: v1.0*
