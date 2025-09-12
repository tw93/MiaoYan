# MiaoYan - Claude Development Guide

## Project Overview

MiaoYan (妙言) is a lightweight macOS Markdown editor built with Swift 5 + AppKit. Features a three-panel layout: sidebar + file list + editor.

## 🎯 Core Principles

- **Incremental Improvements** > Major Refactoring
- **Understand First** > Implement Immediately  
- **Pragmatism** > Dogmatism
- **Clear Intent** > Clever Code

## Claude Code Eight Honors and Eight Shames

- **Shame** in guessing APIs, **Honor** in careful research
- **Shame** in vague execution, **Honor** in seeking confirmation  
- **Shame** in assuming business logic, **Honor** in human verification
- **Shame** in creating interfaces, **Honor** in reusing existing ones
- **Shame** in skipping validation, **Honor** in proactive testing
- **Shame** in breaking architecture, **Honor** in following specifications
- **Shame** in pretending to understand, **Honor** in honest ignorance
- **Shame** in blind modification, **Honor** in careful refactoring

## Development Workflow

1. **Analysis**: Use Grep/Read to analyze code and understand existing patterns
2. **Planning**: Break down tasks into 3-5 steps using TodoWrite
3. **Implementation**: Small iterative changes, modify one file at a time
4. **Verification**: Ensure code compiles and functions work correctly

## ⛔ Absolute Rules

- **NEVER commit changes unless explicitly asked by user**
- Never commit non-compiling code
- Stop after 3 consecutive failures - reassess the approach
- Follow existing code patterns and conventions
- Keep every commit in a working state

## Project Structure

```text
Controllers/        # View Controllers & Window Controllers
Views/             # UI Components (Custom Views, UI Elements)  
Business/          # Business Logic (Models, Data Structures)
Helpers/           # Utilities & Services (Managers, Processors)
Extensions/        # Swift Extensions
AppDelegate.swift  # Application entry point
Info.plist         # Application configuration

Resources/
├── Images.xcassets/# Image and Color Resources
├── Localization/   # All localization files (*.lproj)
├── DownView.bundle/# Web view resources
└── Initial/        # Initial data files
```

## Key Conventions

- Follow existing project conventions and use established utility classes
- Use `NSLocalizedString` for internationalization
- Retrieve colors from `Images.xcassets`
- All comments must be written in English
- Use `// MARK:` for organizing code sections

## Development Commands

```bash
# Build project
xcodebuild -scheme MiaoYan -configuration Debug build

# Clean build
xcodebuild clean

# Run tests (if available)
xcodebuild test -scheme MiaoYan
```

---
*Pragmatism > Perfectionism • Working Simple Solutions > Complex Designs*