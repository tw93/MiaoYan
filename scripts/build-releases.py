#!/usr/bin/env python3
"""Writes the release notes pages, /releases/ (English) and /zh/releases/.

The notes come from the app repository's GitHub releases, kept in
data/releases.json so a site build needs no network. After publishing a release:

    python3 -I scripts/build-releases.py --fetch
    python3 -I scripts/build-fonts.py && python3 -I scripts/build-fonts.py --stamp
    python3 -I scripts/build-site.py && python3 -I scripts/build-blog.py
    python3 -I scripts/build-releases.py

--check fails when the pages are out of date against the data file.
"""
import html
import importlib.util
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data" / "releases.json"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


CJK_RE = re.compile(r"[\u3400-\u9fff]")
KANA_RE = re.compile(r"[\u3040-\u30ff]")
# Leading emoji and marks; the notes keep their own words, not the old decoration.
LEAD_RE = re.compile(r"^[^\w<\[`\"'(（「]+", re.U)
EMOJI_RE = re.compile("[\U0001f000-\U0001faff☀-➿️‍]+")
HTML_HEADING_RE = re.compile(r"<h[1-6][^>]*>.*?</h[1-6]>", re.I | re.S)
MD_HEADING_RE = re.compile(r"^\s*#{1,6}\s.*$", re.M)
LIST_RE = re.compile(r"<(ol|ul)\b[^>]*>(.*?)</\1>", re.I | re.S)
# Install help that older releases appended is not a change to the app.
NOT_A_NOTE_RE = re.compile(r"首次安装|安装不能打开|Github 下载|GitHub 下载|first install|xattr|cannot open.*install|备用地址|backup address|consider giving|\bgive\b.*\bstar\b", re.I)
VERSION_RE = re.compile(r"V\.?\s*(\d+(?:\.\d+)*)", re.I)


def clean(item):
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", item)
    text = html.unescape(re.sub(r"<[^>]+>", "", text))
    text = EMOJI_RE.sub("", text)
    text = re.sub(r"<?https?://\S+>?", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return LEAD_RE.sub("", text).strip()


def note_lines(raw):
    lines = []
    for part in raw:
        part = re.sub(r"^\s*(?:\d+[.、]|[-*])\s+", "", part)
        text = clean(part)
        # Some releases also carried a Japanese list; the pages are English and Chinese.
        if text and not text.isdigit() and not KANA_RE.search(text) and not NOT_A_NOTE_RE.search(text):
            lines.append(text)
    return lines


def is_chinese(text):
    """A Chinese note carries mostly CJK; an English one may just name 妙言."""
    letters = len(re.findall(r"[A-Za-z]", text))
    cjk = len(CJK_RE.findall(text))
    return cjk > 0 and cjk * 3 >= letters


def languages_of(body):
    """(zh, en) notes of a release body, whatever markup that year used."""
    body = re.sub(r'<p align="center">.*?</p>', "", body or "", flags=re.S)
    body = re.sub(r"^\s*>.*$", "", body, flags=re.M)
    zh, en = [], []
    lists = LIST_RE.findall(body)
    if lists:
        # Text outside the lists is install help; `</li>` opens an item in one old typo.
        for _, inner in lists:
            lines = note_lines(re.split(r"</?li[^>]*>", inner))
            chinese = sum(is_chinese(line) for line in lines) * 2 >= len(lines)
            (zh if chinese else en).extend(lines)
        return zh, en
    body = MD_HEADING_RE.sub("\n", HTML_HEADING_RE.sub("\n", body))
    for line in note_lines(re.split(r"<br\s*/?>|\n", body)):
        if " / " in line and CJK_RE.search(line.split(" / ", 1)[0]):
            left, right = line.split(" / ", 1)
            zh.append(left.strip())
            en.append(right.strip())
        elif is_chinese(line):
            zh.append(line)
        else:
            en.append(line)
    return zh, en


def normalize(release):
    name = release.get("name") or ""
    tag = release["tag_name"]
    found = VERSION_RE.search(name)
    version = found.group(1) if found else VERSION_RE.search(tag).group(1)
    codename = ""
    if found:
        codename = clean(name[found.end():]).strip("~ ")
    zh, en = languages_of(release.get("body"))
    return {
        "version": version,
        "tag": tag,
        "codename": codename,
        "date": release["published_at"][:10],
        "en": en,
        "zh": zh,
    }


def fetch():
    raw = subprocess.run(
        ["gh", "api", "--paginate", "--slurp", "repos/tw93/MiaoYan/releases?per_page=100"],
        check=True, capture_output=True, text=True,
    ).stdout
    releases = [r for page in json.loads(raw) for r in page if not r["draft"] and not r["prerelease"]]
    rows = [normalize(r) for r in releases]
    rows.sort(key=lambda r: r["date"], reverse=True)
    empty = [r["tag"] for r in rows if not r["en"] and not r["zh"]]
    if empty:
        sys.exit(f"no notes parsed from: {', '.join(empty)}")
    DATA.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"releases: {len(rows)} in {DATA.relative_to(ROOT)}")


# The notes name a device once per item for GitHub and the App Store; here the
# device heads its group, or a release reads as the same words ten times.
DEVICE_RE = re.compile(r"^(Mac|iPhone and iPad|iPhone 和 iPad|iPhone|iPad)\s*[:：]\s*")


def grouped(items):
    """Items as (device, notes): the ones every device got first, under no head."""
    groups = {"": []}
    for item in items:
        found = DEVICE_RE.match(item)
        device = found.group(1) if found else ""
        groups.setdefault(device, []).append(item[found.end():] if found else item)
    return [(device, notes) for device, notes in groups.items() if notes]


COPY = {
    "en": ("Release Notes", "What changed in each version of MiaoYan, newest first.", "MiaoYan"),
    "zh": ("更新日志", "妙言每个版本改了什么，最新的在最前面。", "妙言"),
}


def page(lang, rows, site, blog):
    title, lede, home_name = COPY[lang]
    path = site.releases_path(lang)
    canonical = site.SITE + path
    jsonld = {
        "@context": "https://schema.org",
        "@graph": [
            blog.breadcrumb([(home_name, site.SITE + blog.home_path(lang)), (title, canonical)]),
            {"@type": "WebPage", "@id": canonical, "name": f"{title} · {home_name}", "description": lede,
             "url": canonical, "inLanguage": site.lang_entry(lang)[2]},
        ],
    }
    head = blog.head(
        lang, title=f"{title} · {home_name}", desc=lede, canonical=canonical,
        en_url=site.SITE + site.releases_path("en"), zh_url=site.SITE + site.releases_path("zh"),
        og_type="website", image=blog.share_image(lang), jsonld=jsonld,
    )
    sections = []
    other = "zh" if lang == "en" else "en"
    for row in rows:
        items = row[lang] or row[other]
        anchor = "v" + row["version"].replace(".", "-")
        name = f' <span class="release-name">{site.esc(row["codename"])}</span>' if row["codename"] else ""
        notes = ""
        for device, lines in grouped(items):
            if device:
                notes += f'<h3 class="release-device">{site.esc(device)}</h3>'
            notes += "<ol>" + "".join(f"<li>{site.esc(line)}</li>" for line in lines) + "</ol>"
        sections.append(
            f'  <section class="release" id="{anchor}">\n'
            f'    <h2 class="release-title">V{site.esc(row["version"])}{name}'
            f' <time class="release-date" datetime="{row["date"]}">{row["date"]}</time></h2>\n'
            f'    <div class="release-notes">{notes}</div>\n'
            f"  </section>\n"
        )
    main = (
        '<main class="blog-index releases">\n'
        f'  <h1 class="section-title">{site.esc(title)}</h1>\n'
        f'  <p class="section-lede">{site.esc(lede)}</p>\n'
        + "".join(sections)
        + "</main>"
    )
    menu = [(k, site.releases_path(k)) for k in COPY]
    header = site.header_html(lang, home=blog.home_path(lang), menu=menu)
    footer = site.footer_html(lang, faq_href=f"{blog.home_path(lang)}#faq")
    return head + f"""<body>
<div class="wrap">
{header}
{main}
</div>
{footer}
{site.page_script(site.STORE_JS, site.LANG_JS)}
{site.ANALYTICS}
</body>
</html>
"""


def main():
    if "--fetch" in sys.argv:
        fetch()
        return 0
    blog = load_module("build_blog", ROOT / "scripts" / "build-blog.py")
    site = blog.site
    rows = json.loads(DATA.read_text(encoding="utf-8"))
    files = {ROOT / site.releases_path(lang).strip("/") / "index.html": page(lang, rows, site, blog) for lang in COPY}
    if "--check" in sys.argv:
        stale = [p for p, text in files.items() if not p.exists() or p.read_text(encoding="utf-8") != text]
        for p in stale:
            print(f"stale: {p.relative_to(ROOT)}", file=sys.stderr)
        if stale:
            return 1
        print(f"releases-ok ({len(rows)} versions)")
        return 0
    for p, text in files.items():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
    print(f"releases: {len(rows)} versions, {len(files)} pages")
    return 0


if __name__ == "__main__":
    sys.exit(main())
