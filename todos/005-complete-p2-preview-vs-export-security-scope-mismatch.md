---
status: complete
priority: p2
issue_id: "005"
tags: [code-review, docs, security, privacy, export]
dependencies: ["002"]
---

# Align Security Scope Between Preview and Export Paths

## Problem Statement

The plan captures baseline behavior for both preview and export network surfaces, but hardening requirements are mostly preview-scoped. This leaves ambiguity about whether export/presentation must follow the same remote-content and sanitization policy.

## Findings

- Baseline explicitly asks to capture remote request behavior for preview and export paths (`docs/plans/2026-02-09-feat-liquid-glass-flexoki-modernization-plan.md:329`).
- Security hardening tasks mostly target preview behavior (`docs/plans/2026-02-09-feat-liquid-glass-flexoki-modernization-plan.md:293`).
- Acceptance criteria mention markdown/export fidelity but not an explicit export security policy mapping (`docs/plans/2026-02-09-feat-liquid-glass-flexoki-modernization-plan.md:511`).

## Proposed Solutions

### Option 1: Extend Security Policy Explicitly to Export/Presentation

**Approach:** Add policy statements and QA checks that define export/presentation behavior for remote content, CSP, and sanitization.

**Pros:**
- Removes ambiguity and policy drift.
- Prevents privacy regressions in export workflow.

**Cons:**
- May require extra compatibility decisions for presentation mode.

**Effort:** 3-6 hours

**Risk:** Medium

---

### Option 2: Explicitly Declare Export as Separate Trust Domain

**Approach:** Keep preview strict-default-deny but document and justify separate rules for export/presentation with clear user messaging.

**Pros:**
- More flexibility for export feature parity.
- Easier migration for existing workflows.

**Cons:**
- Higher policy complexity.
- Increased risk of user confusion.

**Effort:** 4-8 hours

**Risk:** Medium

## Recommended Action

Applied Option 1: made security policy explicitly cross-surface by extending hardening language, acceptance criteria, and QA checks to cover both preview and export/presentation paths.

## Technical Details

**Affected files:**
- `docs/plans/2026-02-09-feat-liquid-glass-flexoki-modernization-plan.md:291`
- `docs/plans/2026-02-09-feat-liquid-glass-flexoki-modernization-plan.md:311`

## Resources

- `docs/plans/2026-02-09-feat-liquid-glass-flexoki-modernization-plan.md`

## Acceptance Criteria

- [x] Security policy explicitly states whether export/presentation follows preview restrictions.
- [x] QA matrix includes export/presentation security/privacy regression tests.
- [x] User-facing behavior is documented for both preview and export contexts.

## Work Log

### 2026-02-09 - Initial Review Finding

**By:** Codex

**Actions:**
- Compared baseline scope to hardening and acceptance sections.
- Identified scope ambiguity across preview vs export paths.
- Drafted two policy resolution options.

**Learnings:**
- Security scope drift is most likely when features span multiple rendering surfaces.

### 2026-02-09 - Resolution

**By:** Codex

**Actions:**
- Updated WebView hardening scope and Phase 2.5 tasks in `docs/plans/2026-02-09-feat-liquid-glass-flexoki-modernization-plan.md` to include preview and export/presentation paths.
- Added security acceptance criteria requiring export/presentation parity with preview sanitization/CSP defaults.
- Added QA parity checks (`Remote Content Privacy Test`, `Cross-Surface Security Parity Test`) covering both surfaces.

**Learnings:**
- Security controls should be specified by rendering surface contract, not by feature label.
