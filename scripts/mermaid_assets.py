#!/usr/bin/env python3
"""Mermaid diagrams drawn ahead of time, shared by the blog and the editor page.

The site draws Mermaid with the files MiaoYan's preview uses, copied byte for
byte from Resources/DownView.bundle/js/ on the app's branch into
assets/vendor/: mermaid-11.14.0.min.js and miaoyan-theme-config.js. Their
hashes are pinned in VENDOR, so a copy that changes by accident fails the
check; the app moving ahead only prints a note.

Every ```mermaid example in content/blog/*.md (written inside a ````markdown
fence, so readers see the source) and every editor template is drawn once
into img/mermaid/<hash>.svg. The hash covers the code, both vendored files,
CONFIG and render-mermaid.mjs, so a new Mermaid, a theme change, a new override
or a renderer change redraws everything under new names.

    python3 -I scripts/mermaid_assets.py          write data/mermaid-manifest.json
    node scripts/render-mermaid.mjs                draw the missing SVGs, drop orphans
    python3 -I scripts/mermaid_assets.py --check   fail on a changed vendored file, a stale
                                                   manifest, a missing or orphaned SVG
"""

import base64
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "data" / "mermaid-manifest.json"
SVG_DIR = ROOT / "img" / "mermaid"
TEMPLATES = ROOT / "content" / "tools" / "mermaid-templates.json"

VENDOR = {
    "assets/vendor/mermaid-11.14.0.min.js": (
        "Resources/DownView.bundle/js/mermaid.min.js",
        "217b66ef4279c33c141b4afe22effad10a91c02558dc70917be2c0981e78ed87",
    ),
    "assets/vendor/miaoyan-theme-config.js": (
        "Resources/DownView.bundle/js/theme-config.js",
        "6fd8cd13a7a7e390b8eb09917cceeff2e07c4870c27a8e010eb9c3d440e382c2",
    ),
}

# Laid over the app's getMermaidConfig(false). Labels are SVG text, not HTML in
# foreignObject: a drawn file is read on Windows and Android with other fonts,
# where a foreignObject box measured on a Mac clips, and Safari refuses to turn
# a foreignObject SVG into a PNG. Arial leads because Windows has the same
# metrics and Android's Roboto is close; CJK glyphs are one em in every face.
CONFIG = {
    "securityLevel": "strict",
    "htmlLabels": False,
    "fontFamily": "Arial, Helvetica, 'PingFang SC', 'Microsoft YaHei', 'Noto Sans CJK SC', sans-serif",
}

WRAPPED_RE = re.compile(r"^````markdown\n```mermaid\n(.*?)\n```\n````$", re.M | re.S)

KINDS = {
    "flowchart": "flowchart", "graph": "flowchart", "sequenceDiagram": "sequence diagram",
    "gantt": "Gantt chart", "timeline": "timeline", "classDiagram": "class diagram",
    "stateDiagram": "state diagram", "stateDiagram-v2": "state diagram", "erDiagram": "ER diagram",
    "pie": "pie chart", "mindmap": "mind map", "xychart-beta": "XY chart", "xychart": "XY chart",
}
KINDS_ZH = {
    "flowchart": "流程图", "sequence diagram": "时序图", "Gantt chart": "甘特图", "timeline": "时间线",
    "class diagram": "类图", "state diagram": "状态图", "ER diagram": "ER 图", "pie chart": "饼图",
    "mind map": "思维导图", "XY chart": "XY 图表",
}


class AssetError(Exception):
    pass


def vendor_hashes():
    return {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in VENDOR}


def digest(code):
    """The SVG's file name. It covers everything that changes the drawing: the
    code, the vendored files, CONFIG and the render script, since the files are
    cached as immutable and a redraw under the same name would never reach a reader."""
    renderer = hashlib.sha256((ROOT / "scripts" / "render-mermaid.mjs").read_bytes()).hexdigest()
    key = json.dumps([code, sorted(vendor_hashes().items()), CONFIG, renderer], ensure_ascii=False, sort_keys=True)
    return hashlib.sha1(key.encode()).hexdigest()[:12]


def payload(code):
    """The editor's #m= fragment: raw deflate, base64url without padding, the same
    format the page reads back through DecompressionStream('deflate-raw')."""
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    raw = c.compress(code.encode()) + c.flush()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def kind(code, lang="en"):
    first = code.strip().split(None, 1)[0] if code.strip() else ""
    name = KINDS.get(first, "diagram")
    return KINDS_ZH.get(name, "图") if lang == "zh" else name


def blocks(text):
    return [m.group(1) for m in WRAPPED_RE.finditer(text)]


def templates():
    return json.loads(TEMPLATES.read_text(encoding="utf-8"))["templates"]


def collect():
    codes = []
    for path in sorted((ROOT / "content" / "blog").glob("*.md")):
        codes += blocks(path.read_text(encoding="utf-8"))
    for t in templates():
        codes += [t["en"]["code"], t["zh"]["code"]]
    return {digest(code): code for code in codes}


def manifest_text():
    return json.dumps(
        {"vendor": sorted(VENDOR), "config": CONFIG, "diagrams": collect()},
        ensure_ascii=False, indent=1, sort_keys=True,
    ) + "\n"


def svg_path(h):
    return SVG_DIR / f"{h}.svg"


def svg_size(h):
    """Width and height the renderer wrote on the root element."""
    head = svg_path(h).read_text(encoding="utf-8")[:2000]
    w = re.search(r'<svg[^>]*?\swidth="([\d.]+)"', head)
    hh = re.search(r'<svg[^>]*?\sheight="([\d.]+)"', head)
    if not (w and hh):
        raise AssetError(f"img/mermaid/{h}.svg has no width and height")
    return round(float(w.group(1))), round(float(hh.group(1)))


def problems():
    found = []
    for path, (_, pinned) in VENDOR.items():
        if hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != pinned:
            found.append(f"{path} changed: copy it again from the app and update VENDOR")
    if not MANIFEST.exists() or MANIFEST.read_text(encoding="utf-8") != manifest_text():
        found.append("data/mermaid-manifest.json is stale: run python3 -I scripts/mermaid_assets.py")
    wanted = set(collect())
    have = {p.stem for p in SVG_DIR.glob("*.svg")}
    found += [f"img/mermaid/{h}.svg is missing: run node scripts/render-mermaid.mjs" for h in sorted(wanted - have)]
    found += [f"img/mermaid/{h}.svg is orphaned: run node scripts/render-mermaid.mjs" for h in sorted(have - wanted)]
    return found


def app_drift():
    """Notes, never failures: the app's copies on origin/main moved ahead."""
    notes = []
    for path, (app_path, pinned) in VENDOR.items():
        try:
            data = subprocess.run(["git", "show", f"origin/main:{app_path}"], cwd=ROOT, capture_output=True, check=True).stdout
        except (OSError, subprocess.CalledProcessError):
            continue
        if hashlib.sha256(data).hexdigest() != pinned:
            notes.append(f"note: origin/main {app_path} differs from {path}; copy it to follow the app")
    return notes


def main():
    if "--check" in sys.argv:
        for note in app_drift():
            print(note, file=sys.stderr)
        found = problems()
        for line in found:
            print(line, file=sys.stderr)
        if found:
            return 1
        print(f"mermaid-ok ({len(collect())} diagrams)")
        return 0
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(manifest_text(), encoding="utf-8")
    print(f"mermaid: manifest with {len(collect())} diagrams")
    return 0


if __name__ == "__main__":
    sys.exit(main())
