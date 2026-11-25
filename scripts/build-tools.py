#!/usr/bin/env python3
"""Build the free tool pages: /tools/<slug>/ in English and /zh/tools/<slug>/ in
Simplified Chinese. Today there is one, the Mermaid live editor.

Sources:
  content/tools/index.json            titles, ledes and descriptions per language
  content/tools/<slug>.en.md, .zh.md  the prose under the tool (an FAQ h2 with h3
                                      questions becomes FAQPage data, as on the blog)
  content/tools/mermaid-templates.json  the editor's templates

The editor runs in the browser (assets/tools/mermaid-editor.js) with the
vendored Mermaid and MiaoYan theme. Its first paint needs no script: the default
template's SVG, drawn ahead by scripts/render-mermaid.mjs, is already in the
preview. Header, footer and scripts come from scripts/build-site.py.

    python3 -I scripts/build-tools.py           write
    python3 -I scripts/build-tools.py --check   fail on stale output or a broken link

Order: build-site.py, mermaid_assets.py and render-mermaid.mjs when diagrams
changed, build-tools.py, build-blog.py, then build-fonts.py for new Chinese copy.
"""

import hashlib
import importlib.util
import json
import pathlib
import re
import sys

import markdown
from markdown.extensions.toc import slugify_unicode

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "content" / "tools"

_spec = importlib.util.spec_from_file_location("build_site", ROOT / "scripts" / "build-site.py")
site = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(site)
sys.path.insert(0, str(ROOT / "scripts"))
import mermaid_assets  # noqa: E402

SITE = site.SITE
esc = site.esc
LANGS = ("en", "zh")
AUTHOR = {"@type": "Person", "name": "Tw93", "url": "https://tw93.fun/"}

UI = {
    "en": {
        "home_name": "MiaoYan",
        "faq": "FAQ",
        "app_cta": "View in App Store",
        "mermaid": {
            "templates": "Templates",
            "code": "Mermaid code",
            "preview": "{kind} preview",
            "syntax": "{label} syntax",
            "png": "Download PNG",
            "copy_image": "Copy image",
            "svg": "Download SVG",
            "markdown": "Copy Markdown",
            "link": "Copy link",
            "undo": "Undo",
            "zoom_out": "Zoom out",
            "zoom_in": "Zoom in",
            "fit": "Fit",
            "app_title": "The same diagrams, inside your notes",
            "app_text": "MiaoYan, a Markdown notebook for Mac, iPhone and iPad, draws Mermaid with this same file. Put the code in a mermaid block and the note's preview shows this diagram.",
            "app_alt": "MiaoYan on a Mac, with Mermaid code on the left and the drawn flowchart in the preview on the right",
            "app_shot": "split",
            "strings": {
                "loading": "Loading Mermaid…",
                "loadFailed": "Mermaid did not load. Check the connection and reload the page.",
                "replaced": "Switched to the template.",
                "copiedMarkdown": "Copied as a Markdown code block.",
                "copiedImage": "Image copied, ready to paste.",
                "copiedLink": "Link copied. Whoever opens it sees this diagram.",
                "copyFailed": "This browser did not allow copying.",
                "exportFailed": "This browser could not save the image.",
                "empty": "Write some Mermaid to draw a diagram.",
                "oldBrowser": "This browser cannot open diagram links. Update it, or open the link in another browser.",
            },
        },
    },
    "zh": {
        "home_name": "妙言",
        "faq": "常见问题",
        "app_cta": "在 App Store 获取",
        "mermaid": {
            "templates": "模板",
            "code": "Mermaid 代码",
            "preview": "{kind}预览",
            "syntax": "{label}写法",
            "png": "下载 PNG",
            "copy_image": "复制图片",
            "svg": "下载 SVG",
            "markdown": "复制 Markdown",
            "link": "复制链接",
            "undo": "撤销",
            "zoom_out": "缩小",
            "zoom_in": "放大",
            "fit": "适应窗口",
            "app_title": "在笔记里画同样的图",
            "app_text": "妙言是 Mac、iPhone 和 iPad 上的 Markdown 笔记本，预览里用的就是这份 Mermaid，把代码放进 mermaid 代码块，画出来就是这张图。",
            "app_alt": "Mac 上的妙言，左边是 Mermaid 代码，右边预览里是画好的流程图",
            "app_shot": "split",
            "strings": {
                "loading": "正在加载 Mermaid…",
                "loadFailed": "Mermaid 没加载上，检查网络后刷新页面。",
                "replaced": "已换成这个模板。",
                "copiedMarkdown": "已复制成 Markdown 代码块。",
                "copiedImage": "图片已复制，可以直接粘贴。",
                "copiedLink": "链接已复制，打开就是这张图。",
                "copyFailed": "这个浏览器不允许复制。",
                "exportFailed": "这个浏览器存不了这张图。",
                "empty": "写一段 Mermaid 就能画出图。",
                "oldBrowser": "这个浏览器打不开图表链接，更新一下或者换个浏览器打开。",
            },
        },
    },
}

DEFAULT_TEMPLATE = "flowchart"


class BuildError(Exception):
    pass


def route(lang, slug):
    return f"/zh/tools/{slug}/" if lang == "zh" else f"/tools/{slug}/"


def output(lang, slug):
    return ROOT / route(lang, slug).strip("/") / "index.html"


def load_tools():
    return json.loads((SRC / "index.json").read_text(encoding="utf-8"))["tools"]


def render_prose(slug, lang):
    md = markdown.Markdown(
        extensions=["extra", "toc", "sane_lists"],
        extension_configs={"toc": {"slugify": slugify_unicode, "permalink": False}},
    )
    out = md.convert((SRC / f"{slug}.{lang}.md").read_text(encoding="utf-8"))
    return re.sub(r'<a href="(https?://(?!miaoyan\.app)[^"]+)">', r'<a href="\1" target="_blank" rel="noopener">', out)


def plain(fragment):
    import html
    return html.unescape(re.sub(r"<[^>]+>", "", fragment)).strip()


def faq_pairs(body, lang):
    section = re.search(rf"<h2[^>]*>{re.escape(UI[lang]['faq'])}</h2>(.*?)(?=<h2[ >]|\Z)", body, re.S)
    if not section:
        return []
    return [(plain(q), re.sub(r"\s+", " ", plain(a))) for q, a in re.findall(r"<h3[^>]*>(.*?)</h3>(.*?)(?=<h3[ >]|\Z)", section.group(1), re.S)]


def head(lang, *, title, desc, canonical, en_url, zh_url, jsonld):
    lang_attr = site.lang_entry(lang)[2]
    image = f"{SITE}/assets/shots/og-{lang}.jpg"
    return f"""<!DOCTYPE html>
<html lang="{lang_attr}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#fbfaf6">
<meta name="apple-itunes-app" content="app-id=6759252269">
<script>document.documentElement.classList.add('js')</script>
<title>{esc(title)}</title>
<meta name="description" content="{esc(desc)}">
<link rel="canonical" href="{canonical}">
<link rel="alternate" hreflang="en" href="{en_url}">
<link rel="alternate" hreflang="zh-CN" href="{zh_url}">
<link rel="alternate" hreflang="zh-Hans" href="{zh_url}">
<link rel="alternate" hreflang="x-default" href="{en_url}">
<meta property="og:type" content="website">
<meta property="og:url" content="{canonical}">
<meta property="og:title" content="{esc(title)}">
<meta property="og:description" content="{esc(desc)}">
<meta property="og:image" content="{image}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:creator" content="@HiTw93">
<meta name="twitter:image" content="{image}">
{site.ICONS}
{site.font_preload(lang)}{site.HEAD_ASSETS}
<script type="application/ld+json">{json.dumps(jsonld, ensure_ascii=False)}</script>
</head>
"""


def shell(lang, slug, main, tail):
    menu = [(k, route(k, slug)) for k in LANGS]
    header = site.header_html(lang, home=site.lang_entry(lang)[1], menu=menu)
    footer = site.footer_html(lang, faq_href=f"{site.lang_entry(lang)[1]}#faq")
    return f"""<body>
<div class="wrap">
{header}
{main}
</div>
{footer}
{tail}
{site.page_script(site.STORE_JS, site.LANG_JS)}
{site.ANALYTICS}
</body>
</html>
"""


def template_data(lang):
    out = []
    for t in mermaid_assets.templates():
        code = t[lang]["code"]
        h = mermaid_assets.digest(code)
        if not mermaid_assets.svg_path(h).exists():
            raise BuildError(f"template {t['id']} ({lang}): img/mermaid/{h}.svg is missing; run node scripts/render-mermaid.mjs")
        w, hh = mermaid_assets.svg_size(h)
        out.append({
            "id": t["id"],
            "label": t[lang]["label"],
            "kind": mermaid_assets.kind(code, lang),
            "code": code,
            "svg": f"/img/mermaid/{h}.svg",
            "width": w,
            "height": hh,
            "syntax": (site.blog_path(lang) + t["post"] + "/") if t.get("post") else None,
            "syntaxLabel": UI[lang]["mermaid"]["syntax"].format(label=t[lang]["label"]),
        })
    return out


def versioned(path):
    """A site path with ?v= its content hash; vercel.json caches these for a year."""
    return f"/{path}?v={hashlib.sha256((ROOT / path).read_bytes()).hexdigest()[:12]}"


def script_json(data):
    return json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")


ICON = {
    "minus": '<svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M3.5 8h9"/></svg>',
    "plus": '<svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M3.5 8h9M8 3.5v9"/></svg>',
    "fit": '<svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M2.5 6V2.5H6M10 2.5h3.5V6M13.5 10v3.5H10M6 13.5H2.5V10"/></svg>',
}


def tool_page(tool, lang, *, category, tool_html, data_id, data, script):
    """One tool page: title and lede, the tool, the prose with its FAQ, then the
    one quiet way into MiaoYan at the end, above the footer."""
    ui = UI[lang]
    meta = tool[lang]
    slug = tool["slug"]
    key = PAGE_KEY[slug]
    copy = ui[key]
    canonical = SITE + route(lang, slug)
    prose = render_prose(slug, lang)
    faqs = faq_pairs(prose, lang)
    home = SITE + site.lang_entry(lang)[1]
    graph = [
        {
            "@type": "BreadcrumbList",
            "itemListElement": [
                {"@type": "ListItem", "position": 1, "name": ui["home_name"], "item": home},
                {"@type": "ListItem", "position": 2, "name": meta["title"], "item": canonical},
            ],
        },
        {
            "@type": "WebApplication",
            "@id": canonical + "#app",
            "name": meta["title"],
            "description": meta["description"],
            "url": canonical,
            "inLanguage": site.lang_entry(lang)[2],
            "applicationCategory": category,
            "operatingSystem": "Any",
            "browserRequirements": "Requires JavaScript",
            "isAccessibleForFree": True,
            "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
            "author": AUTHOR,
            "publisher": {"@type": "SoftwareApplication", "name": "MiaoYan", "url": SITE + "/"},
        },
    ]
    if faqs:
        graph.append({
            "@type": "FAQPage",
            "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in faqs],
        })
    out = head(
        lang, title=meta["head_title"], desc=meta["description"], canonical=canonical,
        en_url=SITE + route("en", slug), zh_url=SITE + route("zh", slug),
        jsonld={"@context": "https://schema.org", "@graph": graph},
    )
    store = site.store_url(lang)
    shot = f"/assets/shots/{lang}-{copy['app_shot']}-1400.webp"
    main = f"""<main class="tool-page">
  <h1 class="section-title">{esc(meta["title"])}</h1>
  <p class="section-lede">{esc(meta["lede"])}</p>
{tool_html}
  <div class="blog-body tool-body">
{prose}
  </div>
  <section class="tool-app" aria-labelledby="tool-app-title">
    <div class="tool-app-text">
      <h2 class="tool-app-title" id="tool-app-title">{esc(copy["app_title"])}</h2>
      <p>{esc(copy["app_text"])}</p>
      <a class="btn btn-ghost" href="{store}" target="_blank" rel="noopener" data-store>{site.APPLE}{esc(ui["app_cta"])}</a>
    </div>
    <figure class="tool-app-shot"><img src="{shot}" width="1400" height="910" alt="{esc(copy["app_alt"])}" loading="lazy" decoding="async"></figure>
  </section>
</main>"""
    tail = (
        f'<script type="application/json" id="{data_id}">{script_json(data)}</script>\n'
        f'<script src="{versioned(script)}" defer></script>'
    )
    return out + shell(lang, slug, main, tail)


def mermaid_page(tool, lang):
    ui = UI[lang]["mermaid"]
    templates = template_data(lang)
    first = next(t for t in templates if t["id"] == DEFAULT_TEMPLATE)
    chips = "".join(
        f'<button type="button" class="tool-chip" data-template="{t["id"]}" aria-pressed="{"true" if t is first else "false"}">{esc(t["label"])}</button>'
        for t in templates
    )
    syntax = (
        f'<a class="tool-syntax" id="mermaid-syntax" href="{first["syntax"]}">{esc(first["syntaxLabel"])}</a>'
        if first["syntax"] else '<a class="tool-syntax" id="mermaid-syntax" hidden></a>'
    )
    lines = "".join(f"<span>{i}</span>" for i in range(1, first["code"].count("\n") + 2))
    zoom = "".join(
        f'<button type="button" class="tool-zoom-btn" data-zoom="{k}" aria-label="{esc(ui[label])}" title="{esc(ui[label])}">{ICON[icon]}</button>'
        for k, label, icon in (("out", "zoom_out", "minus"), ("in", "zoom_in", "plus"), ("fit", "fit", "fit"))
    )
    data = {
        "lang": lang,
        "default": DEFAULT_TEMPLATE,
        "templates": templates,
        "config": mermaid_assets.CONFIG,
        "vendor": [versioned(p) for p in sorted(mermaid_assets.VENDOR, key=lambda p: "mermaid-" in p)],
        "preview": ui["preview"],
        "strings": ui["strings"],
    }
    tool_html = f"""  <div class="tool" id="mermaid-tool">
    <div class="tool-templates" role="group" aria-label="{esc(ui["templates"])}">{chips}</div>
    <div class="tool-grid">
      <div class="tool-editor">
        <div class="tool-gutter" aria-hidden="true"><div class="tool-lines" id="mermaid-lines">{lines}</div></div>
        <label class="visually-hidden" for="mermaid-code">{esc(ui["code"])}</label>
        <textarea id="mermaid-code" class="tool-code" spellcheck="false" autocapitalize="off" autocomplete="off" autocorrect="off" wrap="off">{esc(first["code"])}</textarea>
      </div>
      <div class="tool-preview" id="mermaid-frame">
        <div class="tool-canvas" id="mermaid-preview" role="img" aria-label="{esc(ui["preview"].format(kind=first["kind"]))}"><img src="{first["svg"]}" width="{first["width"]}" height="{first["height"]}" alt="" fetchpriority="high"></div>
        <div class="tool-zoom" role="group">{zoom}</div>
      </div>
    </div>
    <div class="tool-foot">
      <p class="tool-status" id="mermaid-status" role="status" aria-live="polite"></p>
      <button type="button" class="tool-undo" id="mermaid-undo" hidden>{esc(ui["undo"])}</button>
      {syntax}
    </div>
    <div class="tool-actions">
      <button type="button" class="btn btn-primary" data-action="png">{esc(ui["png"])}</button>
      <button type="button" class="btn btn-ghost" data-action="image" hidden>{esc(ui["copy_image"])}</button>
      <button type="button" class="btn btn-ghost" data-action="svg">{esc(ui["svg"])}</button>
      <button type="button" class="btn btn-ghost" data-action="markdown">{esc(ui["markdown"])}</button>
      <button type="button" class="btn btn-ghost" data-action="link">{esc(ui["link"])}</button>
    </div>
  </div>"""
    return tool_page(tool, lang, category="DesignApplication", tool_html=tool_html,
                     data_id="mermaid-data", data=data, script="assets/tools/mermaid-editor.js")


def replace_block(text, inner, name):
    start, end = "<!-- tools:start -->", "<!-- tools:end -->"
    pattern = re.compile(re.escape(start) + ".*?" + re.escape(end), re.S)
    if not pattern.search(text):
        raise BuildError(f"{name} is missing the {start} {end} markers")
    return pattern.sub(lambda _: start + inner + end, text)


def sitemap_block(tools):
    rows = [(SITE + route(lang, t["slug"]), t.get("modified") or t["date"]) for t in tools for lang in LANGS]
    return "".join(f"\n  <url>\n    <loc>{loc}</loc>\n    <lastmod>{mod}</lastmod>\n  </url>" for loc, mod in rows) + "\n  "


def llms_block(tools):
    lines = ["## Tools", ""]
    for t in tools:
        for lang in LANGS:
            lines.append(f"- [{t[lang]['title']}]({SITE}{route(lang, t['slug'])}): {t[lang]['description']}")
    return "\n" + "\n".join(lines) + "\n"


PAGES = {"mermaid-editor": mermaid_page}
PAGE_KEY = {"mermaid-editor": "mermaid"}


def outputs(tools):
    files = {}
    for t in tools:
        for lang in LANGS:
            files[output(lang, t["slug"])] = PAGES[t["slug"]](t, lang)
    for name, block in (("sitemap.xml", sitemap_block(tools)), ("llms.txt", llms_block(tools))):
        files[ROOT / name] = replace_block((ROOT / name).read_text(encoding="utf-8"), block, name)
    return files


def broken_links(files):
    broken = []
    for path, text in files.items():
        if path.suffix != ".html":
            continue
        text = re.sub(r"<code[^>]*>.*?</code>", "", text, flags=re.S)
        # Template syntax links live in the page's JSON, not in an href.
        for ref in re.findall(r'(?:href|src)="(/[^"/][^"]*|/)"', text) + re.findall(r'"syntax":"(/[^"]+)"', text):
            target = ref.split("#")[0].split("?")[0]
            rel = target.strip("/")
            candidates = [ROOT / rel / "index.html"] if target.endswith("/") else [ROOT / rel, ROOT / rel / "index.html"]
            if not any(c in files or c.is_file() for c in candidates):
                broken.append(f"{path.relative_to(ROOT)}: {ref}")
    return sorted(set(broken))


def main():
    check = "--check" in sys.argv
    try:
        tools = load_tools()
        files = outputs(tools)
    except (BuildError, mermaid_assets.AssetError) as error:
        sys.exit(f"tools: {error}")
    broken = broken_links(files)
    for line in broken:
        print(f"broken link: {line}", file=sys.stderr)
    if check:
        changed = [p for p, text in files.items() if not p.exists() or p.read_text(encoding="utf-8") != text]
        for p in changed:
            print(f"stale: {p.relative_to(ROOT)}", file=sys.stderr)
        if changed or broken:
            print("tools are out of date or broken: run python3 scripts/build-tools.py", file=sys.stderr)
            return 1
        print(f"tools-ok ({len(tools)} tools)")
        return 0
    if broken:
        return 1
    for p, text in files.items():
        if not p.exists() or p.read_text(encoding="utf-8") != text:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8")
    print(f"tools: {len(tools)} tools, {len(files)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
