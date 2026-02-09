---
status: complete
priority: p1
issue_id: "002"
tags: [code-review, docs, architecture, security, rollout]
dependencies: []
---

# Resolve Blocking Policy Decisions Before Build

## Problem Statement

The plan lists critical policy decisions as unresolved while downstream phases and acceptance criteria assume behavior that depends on those decisions. This can cause rework, incompatible implementation choices, and rollout delays.

## Findings

- Missing decisions include macOS target/fallback, remote-content default policy, sanitization compatibility, theme precedence, and rollback UX (`docs/plans/2026-02-09-feat-liquid-glass-flexoki-modernization-plan.md:495`).
- Remote-content behavior is treated as effectively decided in security acceptance criteria (`docs/plans/2026-02-09-feat-liquid-glass-flexoki-modernization-plan.md:541`).
- Rollout promises a one-click fallback but the rollback UX location/restart behavior is still undecided (`docs/plans/2026-02-09-feat-liquid-glass-flexoki-modernization-plan.md:502`).

## Proposed Solutions

### Option 1: Add a Decisions Gate Before Phase 2.5

**Approach:** Insert a short mandatory “Decision Freeze” section before implementation that resolves all listed missing decisions.

**Pros:**
- Prevents implementation churn.
- Improves cross-team alignment.

**Cons:**
- Slightly delays implementation kickoff.

**Effort:** 2-4 hours

**Risk:** Low

---

### Option 2: Track Decisions as Separate ADRs Linked From Plan

**Approach:** Create one ADR per unresolved policy and link each from the plan with decision date and owner.

**Pros:**
- Strong historical traceability.
- Easier future audits.

**Cons:**
- More documents to maintain.

**Effort:** 4-8 hours

**Risk:** Low

## Recommended Action

Applied Option 1: added a mandatory Phase 0 Decision Freeze gate with explicit owner-assigned decisions, then synchronized dependent sections (security scope, metrics contract, and rollout/rollback mechanics) to those decisions.

## Technical Details

**Affected files:**
- `docs/plans/2026-02-09-feat-liquid-glass-flexoki-modernization-plan.md:493`
- `docs/plans/2026-02-09-feat-liquid-glass-flexoki-modernization-plan.md:603`

## Resources

- `docs/plans/2026-02-09-feat-liquid-glass-flexoki-modernization-plan.md`

## Acceptance Criteria

- [x] Every item in “Missing Decisions to Finalize Early” has an explicit decision and owner.
- [x] Plan sections that assume policy behavior are updated to match those decisions.
- [x] Rollout and rollback behavior is fully specified and testable.

## Work Log

### 2026-02-09 - Initial Review Finding

**By:** Codex

**Actions:**
- Consolidated architecture/security/spec findings into one blocker.
- Linked unresolved decisions to conflicting downstream assumptions.
- Drafted resolution options.

**Learnings:**
- Plan readiness depends more on early policy closure than additional implementation detail.

### 2026-02-09 - Resolution

**By:** Codex

**Actions:**
- Added `Phase 0: Decision Freeze (Blocking Gate)` with an 8-item decision register (resolution + owner).
- Replaced “Missing Decisions to Finalize Early” with resolved outcomes.
- Updated rollout and acceptance sections to align with frozen policy decisions.

**Learnings:**
- Converting policy ambiguity into a single explicit gate reduces downstream rework risk.
