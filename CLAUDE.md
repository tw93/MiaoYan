# MiaoYan - Claude AI Assistant Development Guide

## Project Overview

MiaoYan (妙言) is a lightweight macOS Markdown editor built with Swift 5 + AppKit. Features a three-panel layout: sidebar + file list + editor.

## 🎯 Claude Development Principles

### Core Philosophy

- **Incremental Improvements** > Major Refactoring
- **Understand First** > Implement Immediately  
- **Pragmatism** > Dogmatism
- **Clear Intent** > Clever Code

### Development Workflow

1. **Analysis Phase**: Use Grep/Read to analyze relevant code and understand existing patterns
2. **Planning Phase**: Break down tasks into 3-5 steps using TodoWrite
3. **Implementation Phase**: Small iterative changes, modify one file at a time
4. **Verification Phase**: Ensure code compiles and functions work correctly

### ⛔ Absolute Prohibitions

- **NEVER commit changes unless explicitly asked by user**
- Never commit non-compiling code
- Don't make unverified assumptions
- **Stop after 3 consecutive failures** - reassess the approach

### ✅ Must Follow

- Keep every commit in a working state
- Learn patterns from existing implementations
- Maintain consistent code style throughout

## Project Structure

```
Controllers/        # View Controllers & Window Controllers (incl. ViewController.swift)
Views/             # UI Components (Custom Views, UI Elements)  
Business/          # Business Logic (Models, Data Structures)
Helpers/           # Utilities & Services (Managers, Processors)
Extensions/        # Swift Extensions
AppDelegate.swift  # Application entry point
AppDelegate+URLRoutes.swift # Application extensions
Info.plist         # Application configuration

Resources/
├── Images.xcassets/# Image and Color Resources
├── Localization/   # All localization files (*.lproj)
├── Fonts/          # Custom fonts
├── DownView.bundle/# Web view resources
└── Initial/        # Initial data files
```

### Directory Guidelines

**Code Organization (Root Level):**
- **Controllers/**: All ViewControllers and WindowControllers (including ViewController.swift and extensions)
- **Views/**: Pure UI components (NSView subclasses, custom controls)
- **Business/**: Data models, enums, business logic structures  
- **Helpers/**: Service classes, managers, processors, utilities
- **Extensions/**: Swift language extensions
- **AppDelegate files**: Application lifecycle and routing
- **Info.plist**: Application configuration and metadata

**Resource Organization (Resources/):**
- **Images.xcassets/**: All images, colors, and visual assets
- **Localization/**: Internationalization files organized by locale
- **Fonts/**: Custom typography resources
- **Static Resources**: Bundles, initial data, and other assets

## Swift macOS Development Best Practices

### Code Standards

- Follow existing project conventions and use established utility classes
- Use camelCase for variables/functions, PascalCase for classes
- Prefer self-documenting code over extensive comments
- Retrieve colors from `Images.xcassets`
- Use `NSLocalizedString` for internationalization

### Comment Guidelines

- **All comments must be written in English**
- Only add comments for complex logic or non-obvious behavior
- Avoid commenting obvious code that is self-explanatory
- Use `// MARK:` for organizing code sections
- Document public APIs and complex algorithms
- Prefer clear variable/function names over explanatory comments

### AppKit Guidelines

- Use `NSViewController` lifecycle methods appropriately
- Implement proper delegate patterns for UI components
- Handle keyboard shortcuts with either NSEvent or KeyboardShortcuts framework
- Use Auto Layout constraints for responsive UI
- Follow MVC pattern with clear separation of concerns

### Performance Considerations

- Use `DispatchQueue.main.async` for UI updates
- Implement lazy loading for expensive operations
- Cache frequently accessed data appropriately
- Use weak references to prevent retain cycles

### Error Handling & Debugging

- Use `guard` statements for early returns
- Implement proper error handling with `do-catch` blocks
- Add meaningful `print()` statements for debugging complex flows
- Use `assert()` for development-time checks

## Error Recovery

**3-Strike Rule**: Stop after 3 consecutive failures and reassess approach.

## Important Reminders

**Pragmatism > Perfectionism**  
**Working Simple Solutions > Complex Designs**

- Always understand existing code before implementing
- Ensure compilation success after each modification
- Use TodoWrite to track task progress
- Revert to working state immediately when encountering issues
- When in doubt, choose the simpler, more maintainable approach

## Development Commands

```bash
# Build project
xcodebuild -scheme MiaoYan -configuration Debug build

# Clean build
xcodebuild clean

# Run tests (if available)
xcodebuild test -scheme MiaoYan

# Update package dependencies
xcodebuild -resolvePackageDependencies
```

---
*This guide ensures consistent, reliable development practices for the MiaoYan project.*
