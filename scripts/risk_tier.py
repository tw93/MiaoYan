#!/usr/bin/env python3
"""Name the verification a change needs from the paths it touches, not from who wrote it.

    python3 scripts/risk_tier.py [path ...]

With no paths it reads the change not yet on the upstream branch: commits since the merge base with @{upstream}
(origin/main when there is none) plus staged, unstaged and untracked files. It prints one line per tier the change
reaches, highest first, and nothing when only the default checks in AGENTS.md apply. It is advice, never a failure:
the gates it names need signing keys, a running app or the maintainer, which CI cannot prove ran. When the worktree
holds someone else's work, pass your own files. It reads git and writes nothing.
"""

from __future__ import annotations

import datetime as dt
import fnmatch
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Highest first. A path takes every tier it matches. `*` in fnmatch also crosses `/`.
TIERS = [
    ("release", "the maintainer's review of the diff; version alignment and the release scripts read through "
                "(AGENTS.md Release Notes); verify_sparkle_signature.sh against the published ZIP before an "
                "appcast push; packaging changes land in the maintainer's own build script too", [
        ".github/workflows/*", "scripts/build.sh", "scripts/release-ci/*", "Info.plist", "MiaoYan.entitlements",
    ]),
    ("installer", "bash -n and shellcheck, then the installer and `miao update` run once in a scratch prefix, "
                  "helpers defined above their first use", [
        "scripts/install.sh", "scripts/miaoyan",
    ]),
    ("notes", "a test red on the old code (AGENTS.md Testing); a review against Current Risk Areas: recoverable "
              "Trash, fail-closed saves, buffer ownership; the flow run in the built app", [
        "Business/Storage.swift", "Business/Note.swift", "Business/Project.swift", "Business/NoteVersionManager.swift",
        "Helpers/FileSystemEventManager.swift", "Helpers/FileWatcher*.swift", "Helpers/ClipboardManager.swift",
        "Helpers/TypographyCleaner.swift", "Views/EditTextView.swift", "Views/SidebarProjectView.swift",
        "Controllers/ViewController+Action.swift", "Shell/ShellModel+Folders.swift",
    ]),
    ("sync", "a run with iCloud unavailable and one through a symlinked library", [
        "Business/CloudSyncManager.swift",
    ]),
    ("export", "Mermaid, images, PDF pagination and async readiness checked together, PNG export repeated", [
        "Business/HtmlManager.swift", "Helpers/PdfExportController.swift", "Extensions/MPreviewView+Export.swift",
        "Shell/ShellModel+Export.swift", "Resources/DownView.bundle/*",
    ]),
    ("core", "swift test --package-path Packages/MiaoYanCore, with the public API kept stable for the iPhone app", [
        "Packages/MiaoYanCore/Sources/*",
    ]),
]


def git(*args: str) -> list[str]:
    out = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)
    return out.stdout.split("\n") if out.returncode == 0 else []


def pending_paths() -> list[str]:
    base = (git("merge-base", "HEAD", "@{upstream}") or git("merge-base", "HEAD", "origin/main") or [""])[0]
    paths = set(git("diff", "--name-only", base)) if base else set()
    paths.update(git("ls-files", "--others", "--exclude-standard"))
    return sorted(p for p in paths if p)


def tiers_for(paths: list[str]) -> list[tuple[str, str, list[str]]]:
    hits = []
    for name, gates, patterns in TIERS:
        matched = [p for p in paths if any(fnmatch.fnmatchcase(p, pattern) for pattern in patterns)]
        if matched:
            hits.append((name, gates, matched))
    return hits


# Circuit breaker: once users met BREAKER_ROWS defects within BREAKER_DAYS (docs/incidents.md, by Reported date),
# every change that reaches a tier also needs the full gate, and the layers those defects slipped past are named
# so they are tightened first. It clears on its own as the rows age out; a future date is never counted.
BREAKER_DAYS, BREAKER_ROWS = 7, 5
BREAKER_GATE = 'the whole `xcodebuild test` and `swift test --package-path Packages/MiaoYanCore` instead of single tests, and the maintainer reading each listed fix before the next release'
LEDGER = ROOT / 'docs/incidents.md'


def recent_incidents(today: dt.date | None = None, ledger: Path | None = None) -> list[tuple[str, str]]:
    """(ID, layer) of every ledger row reported within the last BREAKER_DAYS days."""
    today = today or dt.date.today()
    try:
        text = (ledger or LEDGER).read_text("utf-8")
    except OSError:
        return []
    header: list[str] | None = None
    found = []
    for line in text.split("\n## Incidents", 1)[-1].splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if header is None:
            header = cells
            continue
        if set("".join(cells)) <= set("-: "):
            continue
        row = dict(zip(header, cells))
        try:
            age = (today - dt.date.fromisoformat(row.get("Reported", ""))).days
        except ValueError:
            continue
        if 0 <= age < BREAKER_DAYS:
            found.append((row.get("ID", ""), row.get("Layer", "")))
    return found


def breaker_line(recent: list[tuple[str, str]]) -> str | None:
    if len(recent) < BREAKER_ROWS:
        return None
    ids = ", ".join(ident for ident, _ in recent)
    layers = ", ".join(f"{layer} {count}" for layer, count in Counter(layer for _, layer in recent).most_common())
    return (f"risk: breaker ({len(recent)} incidents in the last {BREAKER_DAYS} days: {ids}): until the rate drops "
            f"every tiered change needs {BREAKER_GATE}; tighten first the layers they slipped past ({layers})")


def main(argv: list[str]) -> int:
    paths = argv or pending_paths()
    hits = tiers_for(paths)
    for name, gates, matched in hits:
        more = f" and {len(matched) - 1} more" if len(matched) > 1 else ""
        print(f"risk: {name} ({matched[0]}{more}) needs {gates}")
    breaker = breaker_line(recent_incidents())
    if hits and breaker:
        print(breaker)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
