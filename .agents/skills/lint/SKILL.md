---
name: lint
description: Run SwiftLint and swift-format checks on MiaoYan. There is no auto-fix hook; run `swiftlint --fix` or `swift-format format --in-place` manually when fixes are needed.
version: 1.1.0
allowed-tools:
  - Bash
---

# Lint Skill

Use this skill to check or fix code style in MiaoYan.

## SwiftLint

```bash
# Check (report only)
swiftlint lint

# Strict mode (treat warnings as errors)
swiftlint lint --strict

# Auto-fix safe violations
swiftlint --fix

# Check specific file
swiftlint lint --path Controllers/ViewController.swift
```

Config: `.swiftlint.yml` at project root.

## swift-format

```bash
# Check formatting (no changes)
swift-format lint --recursive .

# Apply formatting
swift-format format --recursive --in-place .
```

Config: `.swift-format` at project root (line length: 240).

## Run Both

```bash
swiftlint lint --strict && swift-format lint --recursive .
```

## Safety Rules

1. **ALWAYS** run lint check before proposing a commit
2. **NEVER** auto-apply `--fix` or `--in-place` without user confirmation
