#!/usr/bin/env python3
"""Run a UIScript (Helpers/UIScript.swift) against a Debug build, or two.

    python3 scripts/ui_script.py run <MiaoYan.app> <script.txt> [--library DIR] [--out DIR] [--shell]
    python3 scripts/ui_script.py compare <old.app> <new.app> <script.txt> [--library DIR] [--out DIR] [--shell]

Each run copies the library (default: scripts/ui_scripts/library) into a
fresh scratch folder, so the maintainer's notes are never opened, launches
the build in the background with `open -g -n` (no focus, no mouse), waits
for it to quit and prints its log. `compare` runs the same script on both
builds and compares every capture pixel by pixel: a refactor that should
not change the look must report every capture identical. Pixel diffs are
written as `diff-<name>.png` next to the captures.

Builds that share the bundle id `com.tw93.miaoyan.qa` also share the
`wkPreview` copy of DownView.bundle (AGENTS.md); clear it between builds
whose preview files differ.
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LIBRARY = ROOT / "scripts" / "ui_scripts" / "library"


def run_once(app: Path, script: Path, library: Path, out: Path, shell: bool, timeout: int) -> int:
    scratch = Path(tempfile.mkdtemp(prefix="miaoyan-ui-"))
    notes = scratch / "library"
    shutil.copytree(library, notes)
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()
    log = out / "script.log"
    if log.exists():
        log.unlink()
    args = [
        "open", "-g", "-n", "-W", str(app), "--args",
        "-storageUrl", str(notes),
        "-SUEnableAutomaticChecks", "NO",
        "-hasCreatedInitContent", "YES",
        "-MiaoYanScript", str(script.resolve()),
        "-MiaoYanShots", str(out.resolve()),
    ]
    if shell:
        args += ["-MiaoYanShell", "YES"]
    started = time.time()
    try:
        subprocess.run(args, timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        print(f"timed out after {timeout}s; the build is still running, quit it by hand", file=sys.stderr)
        return 2
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    if not log.exists():
        print(f"no script.log in {out}: the build did not run the script (a Release build has no UIScript)", file=sys.stderr)
        return 1
    text = log.read_text()
    print(text, end="")
    print(f"({time.time() - started:.1f}s, captures in {out})")
    return 1 if "\nerror " in "\n" + text else 0


def compare(old: Path, new: Path, out: Path) -> int:
    try:
        from PIL import Image, ImageChops
    except ImportError:
        print("compare needs Pillow (python3 -m pip install Pillow)", file=sys.stderr)
        return 1
    changed = 0
    names = sorted({p.name for p in old.glob("*.png")} | {p.name for p in new.glob("*.png")})
    for name in names:
        a, b = old / name, new / name
        if not a.exists() or not b.exists():
            print(f"{name}: only in {'new' if b.exists() else 'old'}")
            changed += 1
            continue
        ia, ib = Image.open(a).convert("RGBA"), Image.open(b).convert("RGBA")
        if ia.size != ib.size:
            print(f"{name}: size {ia.size} became {ib.size}")
            changed += 1
            continue
        diff = ImageChops.difference(ia, ib)
        box = diff.getbbox()
        if box is None:
            print(f"{name}: identical")
            continue
        count = sum(1 for px in diff.getdata() if px != (0, 0, 0, 0))
        print(f"{name}: {count} pixels differ in {box}")
        mask = diff.convert("L").point(lambda v: 255 if v else 0)
        marked = ib.copy()
        marked.paste((255, 0, 0, 255), mask=mask)
        marked.save(out / f"diff-{name}")
        changed += 1
    return 1 if changed else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=["run", "compare"])
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--library", type=Path, default=DEFAULT_LIBRARY)
    parser.add_argument("--out", type=Path, default=Path(tempfile.gettempdir()) / "miaoyan-ui")
    parser.add_argument("--shell", action="store_true", help="open the SwiftUI shell window")
    parser.add_argument("--timeout", type=int, default=180)
    a = parser.parse_args()

    if a.mode == "run":
        if len(a.paths) != 2:
            parser.error("run takes <app> <script>")
        return run_once(Path(a.paths[0]), Path(a.paths[1]), a.library, a.out, a.shell, a.timeout)

    if len(a.paths) != 3:
        parser.error("compare takes <old app> <new app> <script>")
    old_app, new_app, script = map(Path, a.paths)
    old_out, new_out = a.out / "old", a.out / "new"
    for app, out in ((old_app, old_out), (new_app, new_out)):
        print(f"== {app}")
        if run_once(app, script, a.library, out, a.shell, a.timeout) == 2:
            return 2
    print("== compare")
    return compare(old_out, new_out, a.out)


if __name__ == "__main__":
    sys.exit(main())
