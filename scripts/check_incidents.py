#!/usr/bin/env python3
"""Every row of docs/incidents.md names real commits, a known layer and a catcher the code defines.

    python3 scripts/check_incidents.py [--ledger PATH]

The incident table is the eval set for the review layers (docs/incidents.md says why and what each layer means).
A row fails when its ID repeats, its Reported cell is not a date, its Fixed commit is missing or does not resolve,
its Introduced commit is neither `unknown` nor a commit, its layer is not one of LAYERS, or a backticked catcher is
defined nowhere: not an XCTest method, a Python test function, a CI job id or a file in this repository.

In a shallow clone the commits cannot be resolved and are only shape-checked, which the output says. It reads the
repository and writes nothing.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "docs" / "incidents.md"
LAYERS = ("write-time", "unit", "ci", "review", "release-check", "hand-test", "field")
COLUMNS = ["ID", "Reported", "Symptom", "Introduced", "Fixed", "Layer", "Caught by"]
SHA = re.compile(r"^[0-9a-f]{7,40}$")
SWIFT_TEST = re.compile(r"^\s*(?:@\w+\s+)*(?:override\s+)?func\s+(test[A-Za-z0-9_]*)\s*\(", re.MULTILINE)
PY_TEST = re.compile(r"^\s*def\s+(test_[A-Za-z0-9_]*)\s*\(", re.MULTILINE)
CI_JOB = re.compile(r"^  ([A-Za-z0-9_-]+):\s*$", re.MULTILINE)


def _files(directory: str, pattern: str):
    base = ROOT / directory
    return sorted(base.rglob(pattern)) if base.is_dir() else []


def defined_catchers() -> set[str]:
    names: set[str] = set()
    for directory in ("MiaoYanTests", "Packages/MiaoYanCore/Tests"):
        for path in _files(directory, "*.swift"):
            names.update(SWIFT_TEST.findall(path.read_text("utf-8", errors="replace")))
    for path in _files("scripts", "*.py"):
        names.update(PY_TEST.findall(path.read_text("utf-8", errors="replace")))
    for path in _files(".github/workflows", "*.yml"):
        text = path.read_text("utf-8", errors="replace")
        jobs = text.split("\njobs:\n", 1)
        if len(jobs) == 2:
            names.update(CI_JOB.findall(jobs[1]))
    return names


def is_defined(catcher: str, defined: set[str]) -> bool:
    if catcher in defined:
        return True
    # A gate file named by its repository path.
    return "/" in catcher and (ROOT / catcher).is_file()


def rows(text: str):
    """The table under '## Incidents' as (line number, cells), header and rule excluded."""
    section = False
    for number, line in enumerate(text.splitlines(), 1):
        if line.startswith("## "):
            section = line.strip() == "## Incidents"
            continue
        if section and line.startswith("|"):
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if cells == COLUMNS or set("".join(cells)) <= set("-: "):
                continue
            yield number, cells


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)


def is_shallow() -> bool:
    return git("rev-parse", "--is-shallow-repository").stdout.strip() == "true"


def resolves(sha: str) -> bool:
    return git("cat-file", "-e", sha + "^{commit}").returncode == 0


def problems(text: str, label: str, defined: set[str], check_commits: bool) -> list[str]:
    found: list[str] = []
    seen: set[str] = set()
    for number, cells in rows(text):
        where = f"{label}:{number}"
        if len(cells) != len(COLUMNS):
            found.append(f"{where}: expected {len(COLUMNS)} cells, found {len(cells)}")
            continue
        row = dict(zip(COLUMNS, cells))
        if row["ID"] in seen:
            found.append(f"{where}: {row['ID']} repeats")
        seen.add(row["ID"])
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", row["Reported"]):
            found.append(f"{where}: Reported is not a date: {row['Reported']}")
        for column, optional in (("Fixed", False), ("Introduced", True)):
            value = row[column]
            if optional and value == "unknown":
                continue
            if not SHA.match(value):
                found.append(f"{where}: {column} is not a commit: {value}")
            elif check_commits and not resolves(value):
                found.append(f"{where}: {column} {value} does not resolve")
        if row["Layer"] not in LAYERS:
            found.append(f"{where}: layer {row['Layer']} is not one of {', '.join(LAYERS)}")
        catchers = re.findall(r"`([^`]+)`", row["Caught by"])
        if not catchers:
            found.append(f"{where}: no catcher named")
        found.extend(
            f"{where}: catcher `{name}` is not a test or gate in this repository"
            for name in catchers
            if not is_defined(name, defined)
        )
    return found


def main(argv: list[str]) -> int:
    ledger = LEDGER
    if len(argv) == 2 and argv[0] == "--ledger":
        ledger = Path(argv[1]).resolve()
    elif argv:
        print("usage: check_incidents.py [--ledger PATH]", file=sys.stderr)
        return 2
    text = ledger.read_text("utf-8")
    try:
        label = str(ledger.relative_to(ROOT))
    except ValueError:
        label = ledger.name
    shallow = is_shallow()
    found = problems(text, label, defined_catchers(), check_commits=not shallow)
    for line in found:
        print(line)
    note = ", commits shape-checked only (shallow clone)" if shallow else ""
    print(f"checked {sum(1 for _ in rows(text))} incidents, {len(found)} problems{note}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
