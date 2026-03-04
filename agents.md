# AGENTS.md - MiaoYan Project Knowledge Base

## Project Identity

**MiaoYan** - Lightweight macOS Markdown editor built with Swift 6 + AppKit.

- **Features**: Local-first, split editor & preview, LaTeX, Mermaid, dark mode, distraction-free
- **Stack**: Swift 6, AppKit, native macOS
- **Platform**: macOS 11.5+
- **Distribution**: Homebrew (`brew install --cask miaoyan`) and GitHub Releases

## Repository Structure

```
MiaoYan/
├── Controllers/        # View Controllers & Window Controllers
├── Views/             # UI Components (Custom Views, UI Elements)
├── Business/          # Business Logic (Models, Data Structures)
├── Helpers/           # Utilities & Services (Managers, Processors)
├── Extensions/        # Swift Extensions
├── AppDelegate.swift  # Application entry point
└── Info.plist         # App configuration
```

## Technology Stack

- **Language**: Swift 6 (native, better performance than Electron)
- **UI Framework**: AppKit
- **Architecture**: MVC pattern
- **Minimum macOS**: 11.5+

## Development Commands

```bash
# Build
xcodebuild -project MiaoYan.xcodeproj -scheme MiaoYan -configuration Debug build

# Run
open build/Debug/MiaoYan.app

# Clean
xcodebuild clean
```

## Code Style

- Follow existing Swift patterns in the codebase
- Use `.swift-format` configuration (project root)
- Run SwiftLint checks (`.swiftlint.yml`)

## Core Principles

- **Incremental Improvements** > Major Refactoring
- **Understand First** > Implement Immediately
- **Pragmatism** > Dogmatism
- **Clear Intent** > Clever Code

## Development Workflow

1. **Analysis**: Use Grep/Read to analyze code and understand existing patterns
2. **Planning**: Break tasks into 3-5 steps
3. **Implementation**: Small iterative changes, one file at a time
4. **Verification**: Ensure code compiles and functions work correctly

## Absolute Rules

- NEVER commit non-compiling code
- Stop after 3 consecutive failures - reassess approach
- Keep every commit in a working state
- Follow existing code patterns and conventions

## Release Process

See `.github/workflows/release.yml` for automated release workflow.

### Tag Format

Use `Vx.y.z` format (uppercase V):
```bash
git tag -a V1.15.0 -m "Release V1.15.0"
git push origin V1.15.0
```

### Automated Release

When a `V*` tag is pushed to `main`, GitHub Actions automatically:
- Builds and signs the app
- Notarizes with Apple
- Creates Sparkle signature
- Updates `appcast.xml` on `vercel` branch
- Creates/updates GitHub Release with `MiaoYan.dmg`

### Prerequisites

- `~/.config/miaoyan/build.sh` - Contains Apple ID, Team ID, app-specific password
- `~/.config/miaoyan/sparkle_private.key` - EdDSA private key for Sparkle

## CLI Tool

MiaoYan provides a command-line interface:

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/tw93/MiaoYan/main/scripts/install.sh | bash

# Commands
miao open <title|path>    # Open note
miao new <title> [text]   # Create new note
miao search <query>       # Search notes
miao list [folder]        # List notes
miao cat <title|path>     # Print note content
miao update               # Update CLI
```

## Documentation

- `CONTRIBUTING.md` - Development guidelines
- `DEPENDENCIES.md` - Third-party dependencies
- `CODE_OF_CONDUCT.md` - Community guidelines
