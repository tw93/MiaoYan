# MiaoYan - Claude AI Assistant Guide

## 项目概述

MiaoYan (妙言) 是一款轻量级的 macOS Markdown 编辑器，使用 Swift 5 + AppKit 原生开发。三列布局：文件夹 + 文件列表 + 编辑器。

## 🎯 Claude 开发原则

### 核心理念

- **渐进式改进** > 大幅重构
- **先理解现有代码** > 立即实现
- **务实主义** > 教条主义
- **清晰意图** > 聪明代码

### 开发工作流

1. **理解阶段**: 使用 Grep/Read 分析相关代码，理解现有模式
2. **规划阶段**: 用 TodoWrite 分解任务为 3-5 个步骤
3. **实现阶段**: 小步快跑，每次只改一个文件
4. **验证阶段**: 确保代码编译通过，功能正常

### ⛔ 绝对禁止

- 提交无法编译的代码
- 做出未经验证的假设
- 连续 3 次失败后不重新评估

### ✅ 必须遵守

- 保持每个提交都是可工作状态
- 从现有实现中学习模式
- 保持代码风格一致性

## 项目结构

```
Mac/
├── View/           # UI组件 (*View.swift, *Controller.swift)
├── Business/       # 业务逻辑 (Note.swift, Storage.swift)
├── Helpers/        # 工具类 (UserDefaultsManagement.swift)
└── Images.xcassets/ # 图片和颜色资源
```

## 代码规范

- 遵循现有项目风格，优先使用已有工具类
- 变量函数用驼峰命名，类名用大驼峰
- 代码自解释，避免大量注释
- 颜色从 `Images.xcassets` 获取
- 使用 `NSLocalizedString` 本地化

## 重要提醒

**务实主义 > 完美主义，可工作的简单解决方案 > 复杂设计**

- 优先学习现有代码再实现
- 每次修改后确保编译通过
- 使用 TodoWrite 管理任务进度
- 遇到问题立即恢复到工作状态
