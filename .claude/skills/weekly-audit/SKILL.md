---
name: weekly-audit
description: >-
  Whole-repo audit of MiaoYan across five dimensions (stale rules and dead code,
  performance, broken behaviour, editing experience, preview experience), every
  finding refuted once before it is reported, then the approved fixes landed.
  Use for the periodic check or a whole-app review. Not for one reported bug
  (/hunt), a diff review (/check), or a release's incident review (AGENTS.md
  Release Notes).
when_to_use: "全面检查, 最终检查所有代码, 看看还有冗余的不, 过时的沉淀, 过时的代码, 性能差的地方, 影响功能, 编辑体验, 预览体验, 体检, weekly audit"
metadata:
  version: "1.0.0"
---

# Weekly Audit

Modelled on Mole Mac's weekly audit (2026-10-16), whose value was the few
findings that survived refutation, not the volume. The first MiaoYan run was on
2026-11-05, after V4.7.0. Run it after each release, or weekly while work is
heavy.

## Phase 1: Freeze and scope

- Read the newest entry of `docs/weekly-audit.md`: its "Next window from" commit
  is this run's window, its "Decided, do not re-report" list goes to every agent,
  and its "Open" items are rechecked first.
- Record `git rev-parse HEAD`, `origin/main`, `git status --short` and
  `git log --oneline <window>..HEAD`.
- Exclude `.claude/worktrees/`, `build/`, `.build/` and the vendored files in
  `Resources/DownView.bundle` (every `*.min.js` and `*.min.css`, `js/vendor/`,
  `js/mermaid-layout-elk*.js`, `ppt/`) from every grep and read; the bundle's own
  code is `index.html`, `ppt.html`, the other `js/*.js` and `css/*.css`.
- Run the mechanical checks first and hand their output to the agents:
  `python3 scripts/check_incidents.py`, `swiftlint lint --strict`,
  `swift-format lint --recursive . --strict`.
- Scope: the whole tree on the first run, after a release, or when the window
  touched more than about 40 source files; otherwise the window's files, their
  direct callers and every Open item. The iPhone and iPad app lives in the private
  MiaoYan-Pro checkout (`MiaoYanMobile/`); include it when that checkout sits beside
  this one, read-only, and never quote its code or paths in this public repository.
- Read-only until Phase 4. 「看看 / 检查」 never authorizes a write.

## Phase 2: Five read-only audits in parallel

One Agent per dimension, `model: "opus"`, read-only (no edit, build or test),
each started from the shared header plus its body in `references/prompts.md`, so
coverage does not drift between runs. Each tries to refute every candidate once
(the guard that already blocks it, the test that locks it, the AGENTS.md line
recording the decision) and reports only survivors with `file:line`, a concrete
failure scenario and the smallest fix.

1. **Stale.** Current-state claims in AGENTS.md, ARCHITECTURE.md, `.claude/rules`,
   `docs/`, `skills/miaoyan` and README against the code; zero-caller symbols,
   dead CSS and JS, forward-only wrappers, duplicated helpers, comments naming
   removed functions. AGENTS.md deliberately records rejected designs; a missing
   symbol there is usually a correct record.
2. **Performance.** Main-thread file IO and synchronous reads, per-keystroke work
   in the editor (highlighting, regex compiles, full-storage scans), per-row work
   in the note list and sidebar, preview updates that reload instead of patching,
   unbounded caches, launch work, file-watcher storms.
3. **Behaviour.** Defects that lose or misplace user data or make a feature not
   work: the risk areas in `.claude/rules/` (buffer ownership, Trash, iCloud,
   symlinks, folder moves, `loadFailed`), menu and shortcut parity between the
   storyboard window and the shell, localisation gaps.
4. **Editing.** What a writer feels: input latency, CJK input and marked text,
   undo grouping, cursor and scroll jumps on save, reload or highlight, auto-pair
   and list continuation, paste, formatting commands, find, focus after actions.
5. **Preview.** What a reader feels: flashes, scroll jumps on edit or note switch,
   images and media reserving space, code, math, Mermaid, tables, TOC, split-view
   sync, PPT, and PDF / PNG / HTML export fidelity in light and dark.

## Phase 3: Report

One merged report ranked by risk: behaviour, editing, preview, performance,
stale. Each row: what, where, evidence, smallest fix, and whether it needs the
maintainer (user-visible behaviour, a recorded decision, release timing). Before
reporting, verify the weakest high-severity claim yourself and grep AGENTS.md for
every candidate's symbol: a decision or measurement may live in another section.
End with what was checked and found fine, and the questions only the maintainer
can answer. Rendered-only defects (alignment, flashes, motion) are listed for a
real-app check rather than asserted from reading.

When `references/prompts.md` or the model changed since the last run, rescore
first: for each `docs/incidents.md` row, run the matching dimension's prompt on
the files the fix touched as they were at `<Fixed>^`, and record how many rows it
found.

## Phase 4: Land what the maintainer approves

- Fix agents work in detached worktrees under the scratchpad
  (`git worktree add --detach <scratch>/wt-<n> origin/main`), commit locally
  without pushing, and never share a file. Start each from the fix header in
  `references/prompts.md`.
- Every behaviour fix carries a test that fails on the old code (red-run it), and
  a fix for something a user or the daily build met adds its `docs/incidents.md`
  row in the same commit.
- Agent reports are leads: check every "unused", "dead" or "already broken"
  claim yourself, read each agent's deviations, and close its "not done" list.
- Stack the commits on current `origin/main`, run the full `xcodebuild test`,
  `swift test --package-path Packages/MiaoYanCore`, SwiftLint and swift-format,
  plus the extra gates `scripts/risk_tier.py` names for the touched paths, then
  push. UI fixes go through AGENTS.md Verification (the built app replaces
  `/Applications/MiaoYan.app`).
- Append the run to `docs/weekly-audit.md` (audited and landed commits, next
  window, fixed / decided / open) in the last commit of the run.

## Known traps

- `xcodebuild test` hangs while `/Applications/MiaoYan.app` runs unless the
  command adds `PRODUCT_BUNDLE_IDENTIFIER=com.tw93.miaoyan.qa`.
- CI builds with Xcode 16.3, whose concurrency checks are stricter than local;
  read the run with `gh run view` after pushing.
- A new source or test file needs the four `project.pbxproj` registrations
  (AGENTS.md Commands).
- Two builds sharing the `com.tw93.miaoyan.qa` bundle id share the `wkPreview`
  copy of `DownView.bundle`; clear it when switching.

## Output

The report, then after landing: commits, push status, worktree leftovers, each
finding's state (fixed and verified / decided not to fix with reason / blocked
and what is missing), and the next window, all also written to
`docs/weekly-audit.md`.
