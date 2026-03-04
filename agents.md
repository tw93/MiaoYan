# AGENTS.md - MiaoYan Project Knowledge Base

## Project Identity

**MiaoYan (妙言)** - lightweight macOS Markdown editor built with Swift 5 + AppKit.

## Technology Stack

- **Language**: Swift 5
- **UI Framework**: AppKit
- **Architecture**: MVC pattern

## Project Structure

```
MiaoYan/
├── Controllers/        # View Controllers & Window Controllers
├── Views/             # UI Components
├── Business/          # Business Logic (Models, Data Structures)
├── Helpers/           # Utilities & Services
├── Extensions/        # Swift Extensions
├── AppDelegate.swift  # Entry point
└── Info.plist         # App configuration
```

## Core Principles

- **Incremental Improvements** > Major Refactoring
- **Understand First** > Implement Immediately
- **Pragmatism** > Dogmatism
- **Clear Intent** > Clever Code

## Development Workflow

1. **Analysis**: Use Grep/Read to analyze code
2. **Planning**: Break tasks into 3-5 steps
3. **Implementation**: Small iterative changes
4. **Verification**: Ensure code compiles

## Absolute Rules

- NEVER commit non-compiling code
- Stop after 3 consecutive failures - reassess approach
- Keep every commit in a working state
- Follow existing code patterns

## Release Process

See `.github/workflows/release.yml` for automated release. Tag with `Vx.y.z` format.
