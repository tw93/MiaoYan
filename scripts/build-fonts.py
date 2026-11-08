#!/usr/bin/env python3
"""Subset Source Han Serif for the Chinese pages (/zh/ and /tw/).

Only macOS and iOS ship a Chinese serif (Songti); Android and Windows do not,
so a page that asks for Songti renders in a different face on every platform.
The site carries its own serif instead: Source Han Serif (Adobe, OFL), cut down
to the characters the Chinese pages use and served from /fonts/, with no
third-party font CDN in front of the page (Google Fonts is unreachable from
mainland China). mole.fit does the same.

    python3 scripts/build-fonts.py          regenerate the subsets
    python3 scripts/build-fonts.py --check  verify the shipped subsets cover
                                            every character on the pages

The source fonts are not committed (24 MB each). Put ClearHanSerif-Regular.ttf
(https://github.com/izfsk-ium/Clear-Han-Serif, Simplified reading text only),
SourceHanSerifSC-SemiBold.otf and the two TC files in `.fontcache/`, from
https://github.com/adobe-fonts/source-han-serif/releases. Run this after every
Chinese copy change: a character missing from the subset falls back to the
system face, which is the mixed-font look this file exists to prevent. The
build step in scripts/build-site.py runs --check for that reason.
"""

import hashlib
import html
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FONT_DIR = ROOT / "fonts"
FONT_CACHE = ROOT / ".fontcache"

# (script, weight, source font, pages). Weights 500 to 700 all map to SemiBold.
# Pages are glob patterns: the Chinese blog (scripts/build-blog.py) sets the SC
# face too, its index and every article.
SC_PAGES = ["zh/index.html", "zh/blog/**/index.html"]
SUBSETS = [
    ("sc", "regular", "ClearHanSerif-Regular.ttf", SC_PAGES),
    ("sc", "semibold", "SourceHanSerifSC-SemiBold.otf", SC_PAGES),
    ("tc", "regular", "SourceHanSerifTC-Regular.otf", ["tw/index.html"]),
    ("tc", "semibold", "SourceHanSerifTC-SemiBold.otf", ["tw/index.html"]),
]

# Latin and digits stay with the Latin serif; the subset carries CJK and CJK
# punctuation only. Mirrors the unicode-range in site.css.
CJK_RANGES = [
    (0x2E80, 0x2EFF), (0x3000, 0x303F), (0x3400, 0x4DBF),
    (0x4E00, 0x9FFF), (0xF900, 0xFAFF), (0xFE30, 0xFE4F), (0xFF00, 0xFFEF),
    # Curly quotes and the ellipsis, drawn full width as Chinese text sets them.
    (0x201C, 0x201D), (0x2026, 0x2026),
]

# Attribute values that end up painted as text: image alts, and the gallery
# captions, which live in a JSON blob inside the page script.
PAINTED_ATTRS = re.compile(r'\b(?:alt|aria-label|placeholder)="([^"]*)"')


def in_range(cp):
    return any(lo <= cp <= hi for lo, hi in CJK_RANGES)


def charset(pages):
    chars = set()
    for page in sorted({path for pattern in pages for path in ROOT.glob(pattern)}):
        text = page.read_text(encoding="utf-8")
        painted = " ".join(PAINTED_ATTRS.findall(text))
        # Script bodies are kept: the gallery captions are written by script.
        text = re.sub(r"<style.*?</style>", " ", text, flags=re.S)
        text = re.sub(r"<[^>]+>", " ", text)
        chars.update(c for c in html.unescape(text + " " + painted) if in_range(ord(c)))
    # A regular expression in a code example ends its range at U+9FFF. Clear Han
    # Serif has no such glyph, and that line is set in the code font anyway.
    chars.discard("\u9fff")
    return chars


def subset_path(script, weight):
    return FONT_DIR / f"miaoyan-serif-{script}-{weight}.woff2"


# The hero's 語 is the only Chinese the other languages set. It gets a
# one-glyph file in the Traditional face, so those pages skip the subsets.
MARK = "語"
MARK_SOURCE = "SourceHanSerifTC-Regular.otf"
MARK_FILE = FONT_DIR / "miaoyan-mark.woff2"


def regenerate():
    FONT_DIR.mkdir(exist_ok=True)
    for script, weight, source, pages in SUBSETS:
        src = FONT_CACHE / source
        if not src.exists():
            print(f"missing source font: .fontcache/{source}", file=sys.stderr)
            return 1
        chars = charset(pages)
        # The character list goes to a temp file: .fontcache may be shared
        # with another site's checkout.
        with tempfile.NamedTemporaryFile("w", suffix=".txt", encoding="utf-8", delete=False) as handle:
            handle.write("".join(sorted(chars)))
            text_file = pathlib.Path(handle.name)
        out = subset_path(script, weight)
        subprocess.run(
            [
                "pyftsubset", str(src),
                f"--text-file={text_file}",
                "--flavor=woff2",
                "--layout-features=kern,liga,vert,halt",
                "--no-hinting",
                "--desubroutinize",
                f"--output-file={out}",
            ],
            check=True,
        )
        text_file.unlink()
        rename_reserved(out)
        print(f"  fonts/{out.name}  {len(chars)} glyphs  {out.stat().st_size / 1024:.0f} KB")
    subprocess.run(
        [
            "pyftsubset", str(FONT_CACHE / MARK_SOURCE), f"--text={MARK}",
            "--flavor=woff2", "--no-hinting", "--desubroutinize", f"--output-file={MARK_FILE}",
        ],
        check=True,
    )
    rename_reserved(MARK_FILE)
    print(f"  fonts/{MARK_FILE.name}  1 glyph  {MARK_FILE.stat().st_size / 1024:.0f} KB")
    return 0


# Source is a Reserved Font Name under the OFL and a subset is a Modified
# Version, so a cut font may not keep Adobe's names (2026-10-30). The copyright
# and licence records (name IDs 0, 13, 14) stay as they are.
PRODUCT = "MiaoYan"
RESERVED = ("Source Han Serif", "SourceHanSerif")


def _renamed(text):
    return text.replace(RESERVED[0], f"{PRODUCT} Serif").replace(RESERVED[1], f"{PRODUCT}Serif")


def _cff_dicts(font):
    top = font["CFF "].cff.topDictIndex[0]
    return [top] + list(getattr(top, "FDArray", None) or [])


def rename_reserved(path):
    from fontTools.ttLib import TTFont
    font = TTFont(path, recalcTimestamp=False)
    for rec in font["name"].names:
        if rec.nameID not in (0, 13, 14):
            rec.string = _renamed(rec.toUnicode())
    if "CFF " in font:
        cff = font["CFF "].cff
        cff.fontNames = [_renamed(n) for n in cff.fontNames]
        for d in _cff_dicts(font):
            for key in ("FullName", "FamilyName", "FontName"):
                if isinstance(getattr(d, key, None), str):
                    setattr(d, key, _renamed(getattr(d, key)))
    font.save(path)


def reserved_names(path):
    from fontTools.ttLib import TTFont
    font = TTFont(path)
    names = [r.toUnicode() for r in font["name"].names if r.nameID not in (0, 13, 14)]
    if "CFF " in font:
        names += font["CFF "].cff.fontNames
        names += [getattr(d, k) for d in _cff_dicts(font) for k in ("FullName", "FamilyName", "FontName")
                  if isinstance(getattr(d, k, None), str)]
    return [n for n in names if _renamed(n) != n]


# site.css asks for each font as `/fonts/<name>?v=<content hash>`, the same hash
# build-site.py gives the preload links, so vercel.json can cache /fonts as
# immutable and a regenerated font still reaches every visitor.
SITE_CSS = ROOT / "site.css"
FONT_URL = re.compile(r'url\("/fonts/([\w.-]+\.woff2)(?:\?v=([0-9a-f]+))?"\)')


def font_hash(name):
    return hashlib.sha256((FONT_DIR / name).read_bytes()).hexdigest()[:12]


def stamp():
    css = SITE_CSS.read_text()
    new = FONT_URL.sub(lambda m: f'url("/fonts/{m.group(1)}?v={font_hash(m.group(1))}")', css)
    if new != css:
        SITE_CSS.write_text(new)
    return 0


def stale_font_urls(css):
    return [m.group(1) for m in FONT_URL.finditer(css)
            if not (FONT_DIR / m.group(1)).exists() or m.group(2) != font_hash(m.group(1))]


def song_faces_not_blocking(css):
    """A Chinese face that is not `block` paints the system face first, which is
    the flash first visits showed (maintainer 2026-11-08)."""
    faces = re.findall(r'@font-face \{[^}]*"MiaoYan Serif (?:SC|TC)"[^}]*\}', css)
    return not faces or any("font-display: block" not in face or "local(" in face for face in faces)


def check():
    from fontTools.ttLib import TTFont

    failed = False
    for script, weight, _source, pages in SUBSETS:
        out = subset_path(script, weight)
        if not out.exists():
            print(f"missing font subset: fonts/{out.name}", file=sys.stderr)
            failed = True
            continue
        covered = set()
        for table in TTFont(out)["cmap"].tables:
            covered.update(table.cmap)
        missing = {c for c in charset(pages) if ord(c) not in covered}
        if missing:
            print(
                f"fonts/{out.name} is missing {len(missing)} character(s) used on the page: "
                f"{''.join(sorted(missing)[:20])}; run python3 scripts/build-fonts.py",
                file=sys.stderr,
            )
            failed = True
    if not MARK_FILE.exists():
        print(f"missing font subset: fonts/{MARK_FILE.name}", file=sys.stderr)
        failed = True
    for path in sorted(FONT_DIR.glob("*.woff2")):
        found = reserved_names(path)
        if found:
            print(f"fonts/{path.name} still carries a reserved font name ({found[0]}); regenerate it", file=sys.stderr)
            failed = True
    css = SITE_CSS.read_text()
    stale = stale_font_urls(css)
    if stale:
        print(f"site.css has stale font URLs ({', '.join(stale)}); run python3 scripts/build-fonts.py --stamp, then build-site.py and build-blog.py", file=sys.stderr)
        failed = True
    if song_faces_not_blocking(css):
        print('site.css: every "MiaoYan Serif" face must be font-display: block with no local() source', file=sys.stderr)
        failed = True
    if failed:
        return 1
    print("site-fonts-ok")
    return 0


if __name__ == "__main__":
    sys.exit(check() if "--check" in sys.argv else stamp() if "--stamp" in sys.argv else regenerate())
