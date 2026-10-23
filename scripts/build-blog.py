#!/usr/bin/env python3
"""Build the MiaoYan blog: /blog/ in English and /zh/blog/ in Simplified Chinese.

Sources:
  content/blog/index.json      the post list, in reading order within a category:
                               {"posts": [{"slug", "date", "modified", "category",
                                 "en": {"title", "description"},
                                 "zh": {"title", "description"}}]}
  content/blog/<slug>.en.md    English body
  content/blog/<slug>.zh.md    Chinese body

Bodies are Markdown. A line `[[figure:<name>|<alt>|<caption>]]` embeds
/img/blog/<name>.webp, saved at twice the size it shows at. A post's cover is
/img/blog/cards/<slug>.webp and appears only once that file exists. An h2 named
FAQ (常见问题 in Chinese) followed by h3 questions becomes FAQPage data.

Writes blog/index.html, blog/feed.xml and blog/<slug>/index.html, the same under
zh/blog/, and the marked blog blocks of sitemap.xml and llms.txt. The header,
footer and scripts come from scripts/build-site.py, so the chrome stays one copy.
The output is committed; Vercel serves it as static files.

    python3 scripts/build-blog.py           write
    python3 scripts/build-blog.py --check   fail on stale output, an unknown
                                            category, a missing figure or a
                                            broken internal link

The Chinese pages use the SC font subset: run python3 scripts/build-fonts.py
after a Chinese post changes (build-fonts.py --check says when).
"""

import html
import importlib.util
import json
import math
import pathlib
import re
import sys
from datetime import date, datetime, timezone
from email.utils import format_datetime

import markdown
from markdown.extensions.toc import slugify_unicode

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "content" / "blog"

_spec = importlib.util.spec_from_file_location("build_site", ROOT / "scripts" / "build-site.py")
site = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(site)
SITE = site.SITE
esc = site.esc

LANGS = ("en", "zh")

# Index order. Each category has one pillar post that every post in it links to.
CATEGORIES = ("writing", "notes")
CATEGORY_COPY = {
    "writing": {
        "pillar": "markdown-editor-for-mac",
        "en": ("Writing in Markdown", "Syntax, math, diagrams and slides in plain Markdown files."),
        "zh": ("Markdown 写作", "在普通 Markdown 文件里写公式、画图和做幻灯片。"),
    },
    "notes": {
        "pillar": "local-first-markdown-notes",
        "en": ("Managing notes", "Keep notes as local files, link them, sync them and find them again."),
        "zh": ("笔记管理", "把笔记存成本地文件，互相链接、同步，回头还能找到。"),
    },
}

UI = {
    "en": {
        "home_name": "MiaoYan",
        "blog": "Blog",
        "index_title": "MiaoYan Blog",
        "index_lede": "Notes on writing in plain Markdown and keeping notes as local files, by Tw93.",
        "index_desc": "Guides to writing in Markdown and keeping Markdown notes as local files on Mac, iPhone and iPad.",
        "read": "{n} min read",
        "related": "Keep reading",
        "faq": "FAQ",
    },
    "zh": {
        "home_name": "妙言",
        "blog": "博客",
        "index_title": "妙言博客",
        "index_lede": "关于 Markdown 写作和本地笔记管理的一些记录，作者 Tw93。",
        "index_desc": "在 Mac、iPhone 和 iPad 上用 Markdown 写作，把笔记存成本地文件的指南。",
        "read": "约 {n} 分钟",
        "related": "继续阅读",
        "faq": "常见问题",
    },
}

AUTHOR = {"@type": "Person", "name": "Tw93", "url": "https://tw93.fun/"}
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
FIGURE_RE = re.compile(r"^\[\[figure:([a-z0-9-]+)\|([^|\]]+)\|([^\]]+)\]\]$", re.M)
# The site links to the App Store and GitHub only, never to a Mac download.
DOWNLOAD_RE = re.compile(r'href="[^"]*(?:\.dmg|\.zip|/releases(?:/|"))', re.I)


class BuildError(Exception):
    pass


# ---------------------------------------------------------------- paths

def home_path(lang):
    return site.lang_entry(lang)[1]


def route(lang, slug=None):
    base = site.blog_path(lang)
    return f"{base}{slug}/" if slug else base


def output(lang, slug=None):
    return ROOT / route(lang, slug).strip("/") / "index.html"


def cover_file(slug):
    return ROOT / "img" / "blog" / "cards" / f"{slug}.webp"


def share_image(lang, slug=None):
    if slug and cover_file(slug).exists():
        return f"{SITE}/img/blog/cards/{slug}.webp"
    return f"{SITE}/assets/shots/og-{lang}.jpg"


# ---------------------------------------------------------------- sources

def load_posts():
    posts = json.loads((SRC / "index.json").read_text(encoding="utf-8"))["posts"]
    seen = set()
    for p in posts:
        slug = p.get("slug", "")
        if not SLUG_RE.match(slug) or slug in seen:
            raise BuildError(f"index.json: bad or duplicate slug {slug!r}")
        seen.add(slug)
        if p.get("category") not in CATEGORIES:
            raise BuildError(f"{slug}: category {p.get('category')!r} is not one of {', '.join(CATEGORIES)}")
        date.fromisoformat(p["date"])
        if p.get("modified"):
            if date.fromisoformat(p["modified"]) < date.fromisoformat(p["date"]):
                raise BuildError(f"{slug}: modified is earlier than date")
        for lang in LANGS:
            meta = p.get(lang) or {}
            if not meta.get("title") or not meta.get("description"):
                raise BuildError(f"{slug}: {lang} title or description missing")
            if not (SRC / f"{slug}.{lang}.md").exists():
                raise BuildError(f"{slug}: content/blog/{slug}.{lang}.md is missing")
    return posts


def source(slug, lang):
    return (SRC / f"{slug}.{lang}.md").read_text(encoding="utf-8")


def modified(p):
    return p.get("modified") or p["date"]


def fmt_date(d, lang):
    dt = date.fromisoformat(d)
    if lang == "zh":
        return f"{dt.year}年{dt.month}月{dt.day}日"
    return f"{dt.strftime('%b')} {dt.day}, {dt.year}"


def minutes(slug, lang):
    """Reading time from the Markdown source, as on mole.fit: Chinese counts
    Han at 300 a minute plus words at 200, so a translation shows about the
    same minutes as its English (500 read about 40% shorter)."""
    text = re.sub(r"```.*?```", " ", source(slug, lang), flags=re.S)
    text = FIGURE_RE.sub(" ", text)
    words = len(re.findall(r"[A-Za-z0-9]+", text))
    if lang == "zh":
        chars = len(re.findall(r"[㐀-䶿一-鿿]", text))
        return max(1, round(chars / 300 + words / 200))
    return max(1, round(words / 200))


def read_label(slug, lang):
    return UI[lang]["read"].format(n=minutes(slug, lang))


# ---------------------------------------------------------------- body

def webp_size(path):
    """Pixel size from a WebP header, so the build needs no imaging library."""
    b = path.read_bytes()[:30]
    if b[:4] != b"RIFF" or b[8:12] != b"WEBP":
        raise BuildError(f"{path.relative_to(ROOT)} is not a WebP file")
    kind = b[12:16]
    if kind == b"VP8 ":
        return int.from_bytes(b[26:28], "little") & 0x3FFF, int.from_bytes(b[28:30], "little") & 0x3FFF
    if kind == b"VP8L":
        bits = int.from_bytes(b[21:25], "little")
        return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    if kind == b"VP8X":
        return int.from_bytes(b[24:27], "little") + 1, int.from_bytes(b[27:30], "little") + 1
    raise BuildError(f"{path.relative_to(ROOT)}: unknown WebP chunk {kind!r}")


def figure_html(m, where):
    name, alt, caption = m.group(1), m.group(2).strip(), m.group(3).strip()
    path = ROOT / "img" / "blog" / f"{name}.webp"
    if not path.exists():
        raise BuildError(f"{where}: figure img/blog/{name}.webp is missing")
    w, h = webp_size(path)
    img = (f'<img src="/img/blog/{name}.webp" width="{math.ceil(w / 2)}" height="{math.ceil(h / 2)}" '
           f'loading="lazy" alt="{esc(alt)}">')
    # A stacked <name>-mobile.webp, when present, replaces the wide layout on phones.
    mobile = ROOT / "img" / "blog" / f"{name}-mobile.webp"
    if mobile.exists():
        mw, mh = webp_size(mobile)
        img = (f'<picture><source media="(max-width: 640px)" srcset="/img/blog/{name}-mobile.webp" '
               f'width="{math.ceil(mw / 2)}" height="{math.ceil(mh / 2)}">{img}</picture>')
    return f'<figure class="blog-figure">{img}<figcaption>{esc(caption)}</figcaption></figure>'


def render_body(slug, lang):
    where = f"content/blog/{slug}.{lang}.md"
    text = FIGURE_RE.sub(lambda m: figure_html(m, where), source(slug, lang))
    md = markdown.Markdown(
        extensions=["extra", "toc", "sane_lists"],
        extension_configs={"toc": {"slugify": slugify_unicode, "permalink": False}},
    )
    out = md.convert(text)
    out = re.sub(r'<a href="(https?://(?!miaoyan\.app)[^"]+)">', r'<a href="\1" target="_blank" rel="noopener">', out)
    if DOWNLOAD_RE.search(out):
        raise BuildError(f"{where}: links to a download; the site links only to the App Store and GitHub")
    return glue_cjk_tails(out)


# Keep a paragraph or list item from ending on one Chinese or Japanese
# character. `text-wrap: pretty` handles most lines, but Chromium gives up in
# paragraphs with long unbreakable tokens or `box-decoration-break: clone` code
# chips, and Firefox has no `pretty`; so the last two characters and closing
# punctuation stay on one line, or a lone one is bound to the word before it
# (same helper on every product site, maintainer 2026-10-23).
GLUE_BLOCK_RE = re.compile(r'(<(p|li)\b[^>]*>)((?:(?!<(?:p|li)\b).)*?)(</\2>)', re.S)
CJK_TAIL_RE = re.compile(r'[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff]{2}[。，、；：！？」』）”]*$')
CJK_LONE_RE = re.compile(r' ([\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff][。，、；：！？」』）”]*)$')


def glue_cjk_tails(page):
    def glue(m):
        inner, glued = CJK_TAIL_RE.subn(lambda t: f'<span class="nobr">{t.group(0)}</span>', m.group(3))
        if not glued:
            inner = CJK_LONE_RE.sub(r'&nbsp;\1', inner)
        return m.group(1) + inner + m.group(4)
    return GLUE_BLOCK_RE.sub(glue, page)


def plain(fragment):
    return html.unescape(re.sub(r"<[^>]+>", "", fragment)).strip()


def faq_pairs(body, lang):
    section = re.search(rf"<h2[^>]*>{re.escape(UI[lang]['faq'])}</h2>(.*?)(?=<h2[ >]|\Z)", body, re.S)
    if not section:
        return []
    return [(plain(q), re.sub(r"\s+", " ", plain(a))) for q, a in re.findall(r"<h3[^>]*>(.*?)</h3>(.*?)(?=<h3[ >]|\Z)", section.group(1), re.S)]


# ---------------------------------------------------------------- pages

def related(post, posts, limit=3):
    """The category's pillar, then the nearest posts in the same category by
    list order; other categories fill in only when this one is too small."""
    selected = []

    def add(candidate):
        if candidate and candidate["slug"] != post["slug"] and candidate not in selected and len(selected) < limit:
            selected.append(candidate)

    by_slug = {p["slug"]: p for p in posts}
    add(by_slug.get(CATEGORY_COPY[post["category"]]["pillar"]))
    same = [p for p in posts if p["category"] == post["category"]]
    i = same.index(post)
    for distance in range(1, len(same)):
        add(same[i - distance] if i - distance >= 0 else None)
        add(same[i + distance] if i + distance < len(same) else None)
    for candidate in posts:
        add(candidate)
    return selected


def head(lang, *, title, desc, canonical, en_url, zh_url, og_type, image, jsonld, extra=""):
    lang_attr = site.lang_entry(lang)[2]
    return f"""<!DOCTYPE html>
<html lang="{lang_attr}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#f5f4ed">
<script>document.documentElement.classList.add('js')</script>
<title>{esc(title)}</title>
<meta name="description" content="{esc(desc)}">
<link rel="canonical" href="{canonical}">
<link rel="alternate" hreflang="en" href="{en_url}">
<link rel="alternate" hreflang="zh-CN" href="{zh_url}">
<link rel="alternate" hreflang="x-default" href="{en_url}">
<link rel="alternate" type="application/rss+xml" title="{esc(UI[lang]['index_title'])}" href="{SITE}{route(lang)}feed.xml">
<meta property="og:type" content="{og_type}">
<meta property="og:url" content="{canonical}">
<meta property="og:title" content="{esc(title)}">
<meta property="og:description" content="{esc(desc)}">
<meta property="og:image" content="{image}">{extra}
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:creator" content="@HiTw93">
<meta name="twitter:image" content="{image}">
{site.ICONS}
{site.font_preload(lang)}<link rel="stylesheet" href="/site.css">
<script type="application/ld+json">{json.dumps(jsonld, ensure_ascii=False)}</script>
</head>
"""


def shell(lang, slug, main):
    menu = [(k, route(k, slug)) for k in LANGS]
    header = site.header_html(lang, home=home_path(lang), menu=menu, blog_current=True)
    footer = site.footer_html(lang, faq_href=f"{home_path(lang)}#faq")
    return f"""<body>
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


def breadcrumb(items):
    return {
        "@type": "BreadcrumbList",
        "itemListElement": [{"@type": "ListItem", "position": i + 1, "name": n, "item": u} for i, (n, u) in enumerate(items)],
    }


def index_page(lang, posts):
    ui = UI[lang]
    canonical = SITE + route(lang)
    groups = []
    for category in CATEGORIES:
        items = [p for p in posts if p["category"] == category]
        if not items:
            continue
        label, description = CATEGORY_COPY[category][lang]
        cards = "".join(card_html(p, lang) for p in items)
        groups.append(
            f'  <section id="topic-{category}" class="blog-group" aria-labelledby="topic-{category}-title">\n'
            f'    <h2 class="blog-group-title" id="topic-{category}-title">{esc(label)}</h2>\n'
            f'    <p class="blog-group-description">{esc(description)}</p>\n'
            f'    <ul class="blog-cards">{cards}</ul>\n'
            f"  </section>\n"
        )
    graph = [
        breadcrumb([(ui["home_name"], SITE + home_path(lang)), (ui["blog"], canonical)]),
        {
            "@type": "Blog",
            "@id": canonical + "#blog",
            "name": ui["index_title"],
            "description": ui["index_desc"],
            "url": canonical,
            "inLanguage": site.lang_entry(lang)[2],
            "author": AUTHOR,
            "blogPost": [
                {"@type": "BlogPosting", "headline": p[lang]["title"], "url": SITE + route(lang, p["slug"]), "datePublished": p["date"]}
                for p in posts
            ],
        },
    ]
    out = head(
        lang, title=ui["index_title"], desc=ui["index_desc"], canonical=canonical,
        en_url=SITE + route("en"), zh_url=SITE + route("zh"), og_type="website",
        image=share_image(lang), jsonld={"@context": "https://schema.org", "@graph": graph},
    )
    main = (
        '<main class="blog-index">\n'
        f'  <h1 class="section-title">{esc(ui["index_title"])}</h1>\n'
        f'  <p class="section-lede">{esc(ui["index_lede"])}</p>\n'
        + "".join(groups)
        + "</main>"
    )
    return out + shell(lang, None, main)


def card_html(p, lang):
    slug = p["slug"]
    media = (
        f'<span class="blog-card-media"><img src="/img/blog/cards/{slug}.webp" width="1600" height="900" alt="" loading="lazy"></span>'
        if cover_file(slug).exists()
        else ""
    )
    return (
        f'<li class="blog-card"><a href="{route(lang, slug)}">{media}<span class="blog-card-body">'
        f'<h3 class="blog-card-title">{esc(p[lang]["title"])}</h3>'
        f'<span class="blog-card-desc">{esc(p[lang]["description"])}</span>'
        f'<span class="blog-card-meta"><time datetime="{p["date"]}">{fmt_date(p["date"], lang)}</time> · {read_label(slug, lang)}</span>'
        f"</span></a></li>"
    )


def post_page(p, lang, posts):
    ui = UI[lang]
    slug = p["slug"]
    meta = p[lang]
    body = render_body(slug, lang)
    canonical = SITE + route(lang, slug)
    label = CATEGORY_COPY[p["category"]][lang][0]
    n = minutes(slug, lang)
    image = share_image(lang, slug)
    posting = {
        "@type": "BlogPosting",
        "@id": canonical + "#article",
        "headline": meta["title"],
        "description": meta["description"],
        "url": canonical,
        "mainEntityOfPage": canonical,
        "datePublished": p["date"],
        "dateModified": modified(p),
        "inLanguage": site.lang_entry(lang)[2],
        "image": image,
        "timeRequired": f"PT{n}M",
        "articleSection": label,
        "author": AUTHOR,
        "isPartOf": {"@id": SITE + route(lang) + "#blog"},
        "about": {"@type": "SoftwareApplication", "name": "MiaoYan", "url": SITE + "/"},
    }
    graph = [
        breadcrumb([(ui["home_name"], SITE + home_path(lang)), (ui["blog"], SITE + route(lang)), (meta["title"], canonical)]),
        posting,
    ]
    faqs = faq_pairs(body, lang)
    if faqs:
        graph.append({
            "@type": "FAQPage",
            "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in faqs],
        })
    extra = (
        f'\n<meta property="article:published_time" content="{p["date"]}">'
        f'\n<meta property="article:modified_time" content="{modified(p)}">'
        f'\n<meta property="article:section" content="{esc(label)}">'
    )
    out = head(
        lang, title=f"{meta['title']} · {ui['index_title']}", desc=meta["description"], canonical=canonical,
        en_url=SITE + route("en", slug), zh_url=SITE + route("zh", slug), og_type="article",
        image=image, jsonld={"@context": "https://schema.org", "@graph": graph}, extra=extra,
    )
    cover = (
        f'    <figure class="blog-cover" aria-hidden="true"><img src="/img/blog/cards/{slug}.webp" width="1600" height="900" alt="" fetchpriority="high"></figure>\n'
        if cover_file(slug).exists()
        else ""
    )
    rel = related(p, posts)
    rel_html = ""
    if rel:
        items = "".join(
            f'<li><a href="{route(lang, r["slug"])}"><span class="blog-related-cat">{esc(CATEGORY_COPY[r["category"]][lang][0])}</span>'
            f'<span class="blog-related-name">{esc(r[lang]["title"])}</span>'
            f'<span class="blog-related-meta">{read_label(r["slug"], lang)}</span></a></li>'
            for r in rel
        )
        rel_html = (
            f'  <nav class="blog-related" aria-labelledby="blog-related-title">\n'
            f'    <h2 class="blog-related-title" id="blog-related-title">{esc(ui["related"])}</h2>\n'
            f'    <ul class="blog-related-list">{items}</ul>\n'
            f"  </nav>\n"
        )
    main = (
        '<main class="blog-post">\n'
        '  <article class="blog-article">\n'
        f'    <nav class="blog-crumb" aria-label="Breadcrumb"><a href="{route(lang)}">{esc(ui["blog"])}</a></nav>\n'
        f'    <h1 class="blog-title">{esc(meta["title"])}</h1>\n'
        f'    <p class="blog-meta"><span><a href="{route(lang)}#topic-{p["category"]}">{esc(label)}</a></span>'
        f'<span><time datetime="{p["date"]}">{fmt_date(p["date"], lang)}</time></span><span>{read_label(slug, lang)}</span></p>\n'
        f"{cover}"
        f'    <div class="blog-body">\n{body}\n    </div>\n'
        "  </article>\n"
        f"{rel_html}"
        "</main>"
    )
    return out + shell(lang, slug, main)


def feed_xml(lang, posts):
    ui = UI[lang]
    items = []
    for p in sorted(posts, key=lambda p: p["date"], reverse=True):
        link = SITE + route(lang, p["slug"])
        pub = format_datetime(datetime.fromisoformat(p["date"] + "T01:00:00").replace(tzinfo=timezone.utc))
        items.append(
            f"    <item>\n"
            f"      <title>{esc(p[lang]['title'])}</title>\n"
            f"      <link>{link}</link>\n"
            f'      <guid isPermaLink="true">{link}</guid>\n'
            f"      <pubDate>{pub}</pubDate>\n"
            f"      <description>{esc(p[lang]['description'])}</description>\n"
            f"    </item>\n"
        )
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>{esc(ui['index_title'])}</title>
    <link>{SITE}{route(lang)}</link>
    <atom:link href="{SITE}{route(lang)}feed.xml" rel="self" type="application/rss+xml"/>
    <description>{esc(ui['index_desc'])}</description>
    <language>{site.lang_entry(lang)[2]}</language>
{"".join(items)}  </channel>
</rss>
"""


# ---------------------------------------------------------------- shared files

def replace_block(text, inner, name):
    start, end = "<!-- blog:start -->", "<!-- blog:end -->"
    pattern = re.compile(re.escape(start) + ".*?" + re.escape(end), re.S)
    if not pattern.search(text):
        raise BuildError(f"{name} is missing the {start} {end} markers")
    return pattern.sub(lambda _: start + inner + end, text)


def sitemap_block(posts):
    rows = []
    if posts:
        newest = max(modified(p) for p in posts)
        rows += [(SITE + route(lang), newest) for lang in LANGS]
        rows += [(SITE + route(lang, p["slug"]), modified(p)) for p in posts for lang in LANGS]
    body = "".join(f"\n  <url>\n    <loc>{loc}</loc>\n    <lastmod>{mod}</lastmod>\n  </url>" for loc, mod in rows)
    return body + "\n  "


def llms_block(posts):
    if not posts:
        return "\n"
    lines = [
        "## Blog",
        "",
        f"English posts are at {SITE}{route('en')} and Chinese ones at {SITE}{route('zh')}.",
        "",
    ]
    for lang in LANGS:
        if lang != LANGS[0]:
            lines.append("")
        lines += [f"- [{p[lang]['title']}]({SITE}{route(lang, p['slug'])}): {p[lang]['description']}" for p in posts]
    return "\n" + "\n".join(lines) + "\n"


def outputs(posts):
    files = {}
    for lang in LANGS:
        files[output(lang)] = index_page(lang, posts)
        files[ROOT / route(lang).strip("/") / "feed.xml"] = feed_xml(lang, posts)
        for p in posts:
            files[output(lang, p["slug"])] = post_page(p, lang, posts)
    for name, block in (("sitemap.xml", sitemap_block(posts)), ("llms.txt", llms_block(posts))):
        files[ROOT / name] = replace_block((ROOT / name).read_text(encoding="utf-8"), block, name)
    return files


def stale_files(files):
    """Files under the blog directories that no current post produces."""
    stale = []
    for lang in LANGS:
        d = ROOT / route(lang).strip("/")
        if d.exists():
            stale += [f for f in d.rglob("*") if f.is_file() and f not in files]
    return stale


def broken_links(files):
    """Root-relative links and sources in the blog pages that resolve to nothing."""
    broken = []
    for path, text in files.items():
        if path.suffix != ".html":
            continue
        # Code samples keep their quotes unescaped, so an example tag is not a link.
        text = re.sub(r"<code[^>]*>.*?</code>", "", text, flags=re.S)
        for ref in re.findall(r'(?:href|src)="(/[^"/][^"]*|/)"', text):
            target = ref.split("#")[0].split("?")[0]
            rel = target.strip("/")
            candidates = [ROOT / rel / "index.html"] if target.endswith("/") else [ROOT / rel, ROOT / rel / "index.html"]
            if not any(c in files or c.is_file() for c in candidates):
                broken.append(f"{path.relative_to(ROOT)}: {ref}")
    return sorted(set(broken))


def main():
    check = "--check" in sys.argv
    try:
        posts = load_posts()
        files = outputs(posts)
    except BuildError as error:
        sys.exit(f"blog: {error}")
    broken = broken_links(files)
    for line in broken:
        print(f"broken link: {line}", file=sys.stderr)
    stale = stale_files(files)
    if check:
        changed = [p for p, text in files.items() if not p.exists() or p.read_text(encoding="utf-8") != text]
        for p in changed + stale:
            print(f"stale: {p.relative_to(ROOT)}", file=sys.stderr)
        if changed or stale or broken:
            print("blog is out of date or broken: run python3 scripts/build-blog.py", file=sys.stderr)
            return 1
        print(f"blog-ok ({len(posts)} posts)")
        return 0
    if broken:
        return 1
    for p, text in files.items():
        if not p.exists() or p.read_text(encoding="utf-8") != text:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8")
    for p in stale:
        p.unlink()
    for lang in LANGS:
        for d in sorted((ROOT / route(lang).strip("/")).rglob("*"), reverse=True):
            if d.is_dir() and not any(d.iterdir()):
                d.rmdir()
    print(f"blog: {len(posts)} posts, {len(files)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
