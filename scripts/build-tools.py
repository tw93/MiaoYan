#!/usr/bin/env python3
"""Build the free tool pages: /tools/<slug>/ in English and /zh/tools/<slug>/ in
Simplified Chinese, one per tool in content/tools/index.json, and /tools/ and
/zh/tools/, which list them.

Sources:
  content/tools/index.json            titles, ledes and descriptions per language
  content/tools/<slug>.en.md, .zh.md  the prose under the tool (an FAQ h2 with h3
                                      questions becomes FAQPage data, as on the blog)
  content/tools/mermaid-templates.json  the editor's templates
  content/tools/markdown-table-generator.json  the table the generator opens with

Each tool runs in the browser (assets/tools/<slug>.js). The editor runs with the
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
        "hub": {
            "title": "Markdown Tools",
            "head_title": "Free Markdown Tools: Mermaid, Markmap, tables and preview",
            "lede": "Small tools for writing Markdown, free and in your browser.",
            "description": "Free browser tools from MiaoYan: a Mermaid live editor, a Markmap mind map editor, a Markdown table generator, a Markdown viewer and a Chinese typography cleaner.",
        },
        "faq": "FAQ",
        "app_cta": "View in App Store",
        "typography": {
            "open": "Open file",
            "code": "Original",
            "result": "Cleaned",
            "copy": "Copy result",
            "download": "Download .md",
            "app_title": "Clean a whole note in MiaoYan",
            "app_text": "MiaoYan is a Markdown notebook for Mac, iPhone and iPad. Clean Typography in the Mac app's Edit menu runs these same rules over the open note, and ⌘Z undoes it.",
            "app_alt": "MiaoYan on a Mac, with Markdown on the left and its preview on the right",
            "app_shot": "split",
            "strings": {
                "changed": "{n} changes.",
                "changedOne": "1 change.",
                "clean": "Typography is already clean.",
                "opened": "Opened {name}.",
                "fileType": "Open a Markdown or text file under 5 MB.",
                "copied": "Copied, paste it back where it came from.",
                "copyFailed": "This browser does not allow copying.",
                "exportFailed": "This browser cannot save the file.",
            },
        },
        "markmap": {
            "code": "Markdown outline",
            "preview": "Mind map",
            "png": "Download PNG",
            "copy_image": "Copy image",
            "svg": "Download SVG",
            "markdown": "Copy Markdown",
            "zoom": "Zoom",
            "zoom_out": "Zoom out",
            "zoom_in": "Zoom in",
            "fit": "Fit",
            "app_title": "Mind maps inside your notes",
            "app_text": "MiaoYan, a Markdown notebook for Mac, iPhone and iPad, draws Markmap with these same files. Put the outline in a markmap block and the note's preview shows the map.",
            "app_alt": "MiaoYan on a Mac, with a note on the left and its preview on the right",
            "app_shot": "preview",
            "strings": {
                "loadFailed": "Markmap did not load. Check the connection and reload the page.",
                "copiedMarkdown": "Copied as a Markdown code block.",
                "copiedImage": "Image copied, ready to paste.",
                "copyFailed": "This browser did not allow copying.",
                "exportFailed": "This browser could not save the image.",
                "empty": "Write an outline to draw a mind map.",
                "oldBrowser": "This browser cannot open mind map links. Update it, or open the link in another browser.",
            },
        },
        "nnw": {
            "appearance": "Appearance",
            "light": "Light",
            "dark": "Dark",
            "install": "Install in NetNewsWire",
            "zip": "Download .zip",
            "github": "GitHub",
            "preview": "A MiaoYan blog post in NetNewsWire with this theme, in {scheme} mode",
            "app_title": "Write in MiaoYan",
            "app_text": "MiaoYan, from the same author, is a Markdown notebook for Mac, iPhone and iPad that keeps every note as a plain .md file.",
            "app_alt": "MiaoYan on a Mac, with the note list on the left and a note in its preview on the right",
            "app_shot": "preview",
            "strings": {
                "installing": "If NetNewsWire did not open, install it first and click again.",
            },
        },
        "viewer": {
            "open": "Open file",
            "preview_only": "Preview only",
            "code": "Markdown",
            "preview": "Preview",
            "pdf": "Save as PDF",
            "html": "Download HTML",
            "copy": "Copy formatted",
            "app_title": "Read and write it in MiaoYan",
            "app_text": "MiaoYan, a Markdown notebook for Mac, iPhone and iPad, keeps every note as a plain .md file, and this preview is drawn with its stylesheets.",
            "app_alt": "MiaoYan on a Mac, with the note list on the left and a note in its preview on the right",
            "app_shot": "preview",
            "strings": {
                "opened": "Opened {name}.",
                "fileType": "Open a Markdown or text file under 5 MB.",
                "copied": "Copied with its formatting, ready to paste into a document or an email.",
                "copyFailed": "This browser did not allow copying.",
                "exportFailed": "This browser could not save the file.",
                "loadFailed": "Part of the preview did not load. Check the connection and reload the page.",
            },
        },
        "table": {
            "add_row": "Add row",
            "add_col": "Add column",
            "clear": "Clear",
            "cell": "Row {row}, column {col}",
            "align_group": "Column {col} alignment",
            "align_left": "Align left",
            "align_center": "Align center",
            "align_right": "Align right",
            "del_col": "Delete column {col}",
            "del_row": "Delete row {row}",
            "output": "Markdown",
            "pad": "Line up columns",
            "copy": "Copy Markdown",
            "undo": "Undo",
            "app_title": "Paste the table into a note",
            "app_text": "In MiaoYan, a Markdown notebook for Mac, iPhone and iPad, the note's preview shows this Markdown as a table. On the Mac, a table copied from a web page is written as Markdown when you paste it.",
            "app_alt": "MiaoYan on a Mac, with Markdown on the left and its preview on the right",
            "app_shot": "split",
            "strings": {
                "copied": "Copied. Paste it into a Markdown file or a note.",
                "copyFailed": "This browser did not allow copying.",
                "pasted": "Pasted a table of {rows} by {cols}.",
                "trimmed": "The grid holds {rows} rows and {cols} columns, so the rest was left out.",
                "noTable": "There is no table in this file.",
                "fileType": "Drop a CSV, TSV, Markdown or text file under 4 MB.",
                "cleared": "Cleared the table.",
                "deleted": "Deleted.",
            },
        },
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
            "zoom": "Zoom",
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
        "hub": {
            "title": "Markdown 在线工具",
            "head_title": "Markdown 在线工具：Mermaid、Markmap 思维导图、表格和预览",
            "lede": "写 Markdown 时顺手用的几个小工具，免费，打开浏览器就能用。",
            "description": "妙言的免费在线工具，Mermaid 在线编辑器、Markmap 思维导图、Markdown 表格生成器、Markdown 在线预览和中英文排版整理。",
        },
        "faq": "常见问题",
        "app_cta": "在 App Store 获取",
        "markmap": {
            "code": "Markdown 大纲",
            "preview": "思维导图",
            "png": "下载 PNG",
            "copy_image": "复制图片",
            "svg": "下载 SVG",
            "markdown": "复制 Markdown",
            "zoom": "缩放",
            "zoom_out": "缩小",
            "zoom_in": "放大",
            "fit": "适应画布",
            "app_title": "在笔记里画导图",
            "app_text": "妙言是 Mac、iPhone 和 iPad 上的 Markdown 笔记本，画 Markmap 用的就是这几份文件，把大纲放进 markmap 代码块，笔记的预览里就是这张导图。",
            "app_alt": "Mac 上的妙言，左边是笔记，右边是它的预览",
            "app_shot": "preview",
            "strings": {
                "loadFailed": "Markmap 没加载上，检查网络后刷新页面。",
                "copiedMarkdown": "已复制成 Markdown 代码块。",
                "copiedImage": "图片已复制，可以直接粘贴。",
                "copyFailed": "这个浏览器不允许复制。",
                "exportFailed": "这个浏览器存不了这张图。",
                "empty": "写一份大纲就能画出导图。",
                "oldBrowser": "这个浏览器打不开导图链接，更新一下或者换个浏览器打开。",
            },
        },
        "typography": {
            "open": "打开文件",
            "code": "原文",
            "result": "整理后",
            "copy": "复制结果",
            "download": "下载 .md",
            "app_title": "在妙言里整理整篇笔记",
            "app_text": "妙言是 Mac、iPhone 和 iPad 上的 Markdown 笔记本，Mac 版编辑菜单里的清理排版用的就是这套规则，整篇笔记一次整理好，不满意按 ⌘Z 就能退回。",
            "app_alt": "Mac 上的妙言，左边是 Markdown，右边是它的预览",
            "app_shot": "split",
            "strings": {
                "changed": "改了 {n} 处。",
                "clean": "排版无需清理。",
                "opened": "已打开 {name}。",
                "fileType": "打开的需要是 5 MB 以内的 Markdown 或文本文件。",
                "copied": "已复制，贴回原来的地方就行。",
                "copyFailed": "这个浏览器不允许复制。",
                "exportFailed": "这个浏览器存不了这个文件。",
            },
        },
        "nnw": {
            "appearance": "外观",
            "light": "浅色",
            "dark": "深色",
            "install": "在 NetNewsWire 里安装",
            "zip": "下载 .zip",
            "github": "GitHub",
            "preview": "NetNewsWire 用这套主题显示的一篇妙言博客文章，{scheme}外观",
            "app_title": "写东西用妙言",
            "app_text": "妙言是同一个作者做的 Mac、iPhone 和 iPad 上的 Markdown 笔记本，每篇笔记都是一个普通的 .md 文件。",
            "app_alt": "Mac 上的妙言，左边是笔记列表，右边是一篇笔记的预览",
            "app_shot": "preview",
            "strings": {
                "installing": "NetNewsWire 没有打开的话，先装好它再点一次。",
            },
        },
        "viewer": {
            "open": "打开文件",
            "preview_only": "只看预览",
            "code": "Markdown",
            "preview": "预览",
            "pdf": "存成 PDF",
            "html": "下载 HTML",
            "copy": "复制带格式的内容",
            "app_title": "在妙言里读和写",
            "app_text": "妙言是 Mac、iPhone 和 iPad 上的 Markdown 笔记本，每篇笔记都是一个普通的 .md 文件，这里的预览用的就是它的样式表。",
            "app_alt": "Mac 上的妙言，左边是笔记列表，右边是一篇笔记的预览",
            "app_shot": "preview",
            "strings": {
                "opened": "已打开 {name}。",
                "fileType": "打开的需要是 5 MB 以内的 Markdown 或文本文件。",
                "copied": "已复制，贴进文档或邮件里会带着格式。",
                "copyFailed": "这个浏览器不允许复制。",
                "exportFailed": "这个浏览器存不了这个文件。",
                "loadFailed": "预览有一部分没加载上，检查网络后刷新页面。",
            },
        },
        "table": {
            "add_row": "加一行",
            "add_col": "加一列",
            "clear": "清空",
            "cell": "第 {row} 行第 {col} 列",
            "align_group": "第 {col} 列对齐",
            "align_left": "左对齐",
            "align_center": "居中",
            "align_right": "右对齐",
            "del_col": "删除第 {col} 列",
            "del_row": "删除第 {row} 行",
            "output": "Markdown",
            "pad": "对齐各列",
            "copy": "复制 Markdown",
            "undo": "撤销",
            "app_title": "把表格贴进笔记",
            "app_text": "妙言是 Mac、iPhone 和 iPad 上的 Markdown 笔记本，这段 Markdown 贴进笔记，预览里就是一张表，在 Mac 上从网页复制表格直接粘贴，也会写成 Markdown。",
            "app_alt": "Mac 上的妙言，左边是 Markdown，右边是它的预览",
            "app_shot": "split",
            "strings": {
                "copied": "已复制，贴进 Markdown 文件或者笔记里就行。",
                "copyFailed": "这个浏览器不允许复制。",
                "pasted": "已粘贴 {rows} 行 {cols} 列。",
                "trimmed": "网格最多放 {rows} 行 {cols} 列，多出的部分没有放进来。",
                "noTable": "这个文件里没有表格。",
                "fileType": "拖进来的需要是 4 MB 以内的 CSV、TSV、Markdown 或文本文件。",
                "cleared": "已清空表格。",
                "deleted": "已删除。",
            },
        },
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
            "zoom": "缩放",
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


def route(lang, slug=None):
    """A tool's page, or with no slug the page that lists every tool."""
    base = "/zh/tools/" if lang == "zh" else "/tools/"
    return f"{base}{slug}/" if slug else base


def output(lang, slug=None):
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


ACTIONS_RE = re.compile(r'\n    <div class="tool-actions">.*?\n    </div>', re.S)
BAR_RE = re.compile(r'\n    <div class="(?:tool-templates|table-bar)"[^>]*>.*?</div>(?=\n    <div)', re.S)


def toolbar(tool_html):
    """The tool's own controls on the left and its actions on the right, in one
    row above the panes, so the first screen holds everything the tool does."""
    actions = ACTIONS_RE.search(tool_html)
    if not actions:
        raise BuildError("a tool has no tool-actions block")
    html = tool_html[:actions.start()] + tool_html[actions.end():]
    block = (actions.group(0)
             .replace('class="btn btn-primary"', 'class="tool-chip tool-chip-primary"')
             .replace('class="btn btn-ghost"', 'class="tool-chip"'))
    bar = BAR_RE.search(html)
    if bar:
        return html[:bar.start()] + '\n    <div class="tool-bar">' + bar.group(0).replace("\n    ", "\n      ") + block.replace("\n    ", "\n      ") + "\n    </div>" + html[bar.end():]
    head = html.index(">") + 1
    return html[:head] + '\n    <div class="tool-bar">' + block.replace("\n    ", "\n      ") + "\n    </div>" + html[head:]


def tool_page(tool, lang, *, category, tool_html, data_id, data, script, before=(), system="Any"):
    """One tool page: title and lede, the tool, the prose with its FAQ, then the
    one quiet way into MiaoYan at the end, above the footer."""
    tool_html = toolbar(tool_html)
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
                {"@type": "ListItem", "position": 2, "name": ui["hub"]["title"], "item": SITE + route(lang)},
                {"@type": "ListItem", "position": 3, "name": meta["title"], "item": canonical},
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
            "operatingSystem": system,
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
        + "".join(f'<script src="{versioned(s)}" defer></script>\n' for s in before)
        + f'<script src="{versioned(script)}" defer></script>'
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
        <div class="tool-zoom" role="group" aria-label="{esc(ui["zoom"])}">{zoom}</div>
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


# The table generator's Markdown, the same as assets/tools/markdown-table-generator.js
# writes it, so the page arrives with the right output before any script runs.
WIDE = (
    (0x1100, 0x115F), (0x231A, 0x231B), (0x23E9, 0x23EC), (0x23F0, 0x23F0), (0x23F3, 0x23F3),
    (0x25FD, 0x25FE), (0x2614, 0x2615), (0x2648, 0x2653), (0x267F, 0x267F), (0x2693, 0x2693),
    (0x26A1, 0x26A1), (0x26AA, 0x26AB), (0x26BD, 0x26BE), (0x26C4, 0x26C5), (0x26CE, 0x26CE),
    (0x26D4, 0x26D4), (0x26EA, 0x26EA), (0x26F2, 0x26F3), (0x26F5, 0x26F5), (0x26FA, 0x26FA),
    (0x26FD, 0x26FD), (0x2705, 0x2705), (0x270A, 0x270B), (0x2728, 0x2728), (0x274C, 0x274C),
    (0x274E, 0x274E), (0x2753, 0x2755), (0x2757, 0x2757), (0x2795, 0x2797), (0x27B0, 0x27B0),
    (0x27BF, 0x27BF), (0x2B1B, 0x2B1C), (0x2B50, 0x2B50), (0x2B55, 0x2B55),
    (0x2E80, 0x303E), (0x3041, 0x33FF), (0x3400, 0x4DBF), (0x4E00, 0x9FFF),
    (0xA000, 0xA4CF), (0xA960, 0xA97F), (0xAC00, 0xD7A3), (0xF900, 0xFAFF), (0xFE30, 0xFE4F),
    (0xFF00, 0xFF60), (0xFFE0, 0xFFE6), (0x1F004, 0x1F004), (0x1F0CF, 0x1F0CF), (0x1F18E, 0x1F18E),
    (0x1F191, 0x1F19A), (0x1F200, 0x1F202), (0x1F210, 0x1F23B), (0x1F240, 0x1F248), (0x1F250, 0x1F251),
    (0x1F300, 0x1F64F), (0x1F680, 0x1F6FF), (0x1F7E0, 0x1F7EB), (0x1F90C, 0x1F9FF), (0x1FA70, 0x1FAFF),
    (0x20000, 0x3FFFD),
)
ZERO = ((0x0300, 0x036F), (0x200B, 0x200F), (0x20D0, 0x20FF), (0xFE00, 0xFE0F), (0x1F3FB, 0x1F3FF), (0xE0020, 0xE007F))
# String.prototype.trim()'s set, so a cell trims the same in both places.
JS_SPACE = "\t\n\v\f\r \u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff"


def char_width(ch):
    cp = ord(ch)
    if cp < 0x300:
        return 1
    if any(a <= cp <= b for a, b in ZERO):
        return 0
    return 2 if any(a <= cp <= b for a, b in WIDE) else 1


def text_width(s):
    return sum(char_width(c) for c in s)


def table_cell(s):
    return re.sub(r"\\?\|", r"\\|", s.strip(JS_SPACE))


def table_markdown(rows, align, pad=True):
    cells = [[table_cell(c) for c in r] for r in rows]
    marks = {"left": (":", ""), "center": (":", ":"), "right": ("", ":")}
    if not pad:
        rule = [{"left": ":---", "center": ":---:", "right": "---:"}.get(a, "---") for a in align]
        lines = [cells[0], rule] + cells[1:]
        return "\n".join("| " + " | ".join(r) + " |" for r in lines)
    widths = [max([3] + [text_width(r[c]) for r in cells]) for c in range(len(align))]

    def fit(s, c):
        gap = widths[c] - text_width(s)
        if align[c] == "right":
            return " " * gap + s
        if align[c] == "center":
            return " " * (gap // 2) + s + " " * (gap - gap // 2)
        return s + " " * gap

    rule = []
    for c, a in enumerate(align):
        head, tail = marks.get(a, ("", ""))
        rule.append(head + "-" * (widths[c] - len(head) - len(tail)) + tail)
    out = ["| " + " | ".join(fit(s, c) for c, s in enumerate(cells[0])) + " |", "| " + " | ".join(rule) + " |"]
    out += ["| " + " | ".join(fit(s, c) for c, s in enumerate(r)) + " |" for r in cells[1:]]
    return "\n".join(out)


def table_markdown_html(text):
    """The output as shown on the page: wide characters sit in a two-column box,
    so the columns line up in a monospace font whose CJK fallback is narrower."""
    return "".join(f'<span class="w">{esc(c)}</span>' if char_width(c) == 2 else esc(c) for c in text)


ICON_ALIGN = {
    "left": '<svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M2.5 4h11M2.5 8h7M2.5 12h9"/></svg>',
    "center": '<svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M2.5 4h11M4.5 8h7M3.5 12h9"/></svg>',
    "right": '<svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M2.5 4h11M6.5 8h7M4.5 12h9"/></svg>',
}
ICON_X = '<svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M4.5 4.5l7 7M11.5 4.5l-7 7"/></svg>'


def table_grid_html(rows, align, ui):
    """The grid, built the way the script builds it, so its first render changes nothing."""
    def fmt(key, **kw):
        return esc(ui[key].format(**kw))

    ctrl = ""
    for c, a in enumerate(align):
        buttons = "".join(
            f'<button type="button" class="table-btn" data-align="{k}" aria-pressed="{"true" if a == k else "false"}" aria-label="{esc(ui["align_" + k])}" title="{esc(ui["align_" + k])}">{ICON_ALIGN[k]}</button>'
            for k in ("left", "center", "right")
        )
        ctrl += (
            f'<td><div class="table-col-ctrl"><div class="table-align" role="group" aria-label="{fmt("align_group", col=c + 1)}">{buttons}</div>'
            f'<button type="button" class="table-btn table-x" data-del-col="{c}" aria-label="{fmt("del_col", col=c + 1)}" title="{fmt("del_col", col=c + 1)}">{ICON_X}</button></div></td>'
        )
    body = ""
    for r, row in enumerate(rows):
        cells = "".join(
            f'<td data-align="{align[c] or "none"}"><input class="table-cell" type="text" value="{esc(v)}" aria-label="{fmt("cell", row=r + 1, col=c + 1)}" spellcheck="false" autocomplete="off" autocapitalize="off"></td>'
            for c, v in enumerate(row)
        )
        body += (
            f'<tr{" class=\"is-head\"" if r == 0 else ""}>{cells}<td class="table-end">'
            f'<button type="button" class="table-btn table-x" data-del-row="{r}" aria-label="{fmt("del_row", row=r + 1)}" title="{fmt("del_row", row=r + 1)}">{ICON_X}</button></td></tr>'
        )
    return f'<table class="table-grid" id="table-grid"><thead><tr class="table-ctrl">{ctrl}<td class="table-end"></td></tr></thead><tbody>{body}</tbody></table>'


def table_page(tool, lang):
    ui = UI[lang]["table"]
    start = json.loads((SRC / "markdown-table-generator.json").read_text(encoding="utf-8"))[lang]
    rows, align = start["rows"], start["align"]
    md = table_markdown(rows, align)
    data = {
        "lang": lang,
        "start": start,
        "ui": {k: ui[k] for k in ("cell", "align_group", "align_left", "align_center", "align_right", "del_col", "del_row")},
        "icons": {"x": ICON_X, **ICON_ALIGN},
        "strings": ui["strings"],
    }
    tool_html = f"""  <div class="tool table-tool" id="table-tool">
    <div class="table-bar">
      <button type="button" class="tool-chip" data-op="row">{esc(ui["add_row"])}</button>
      <button type="button" class="tool-chip" data-op="col">{esc(ui["add_col"])}</button>
      <label class="table-pad"><input type="checkbox" id="table-pad" checked>{esc(ui["pad"])}</label>
      <button type="button" class="tool-chip table-clear" data-op="clear">{esc(ui["clear"])}</button>
    </div>
    <div class="table-wrap" id="table-wrap">{table_grid_html(rows, align, ui)}</div>
    <div class="table-out">
      <pre class="table-md" id="table-md" tabindex="0" aria-label="{esc(ui["output"])}">{table_markdown_html(md)}</pre>
    </div>
    <div class="tool-foot">
      <p class="tool-status" id="table-status" role="status" aria-live="polite"></p>
      <button type="button" class="tool-undo" id="table-undo" hidden>{esc(ui["undo"])}</button>
    </div>
    <div class="tool-actions">
      <button type="button" class="btn btn-primary" data-action="copy">{esc(ui["copy"])}</button>
    </div>
  </div>"""
    return tool_page(tool, lang, category="DeveloperApplication", tool_html=tool_html,
                     data_id="table-data", data=data, script="assets/tools/markdown-table-generator.js")


PREVIEW_CSS = ("typography", "theme-light", "base", "diagrams")
# What MiaoYan's HTML export sets on top of the stylesheets (HtmlManager.previewStyle
# with the default 16px size and the export width), and its code font stack.
PREVIEW_PAGE_CSS = (
    ':root { --code-text-font: SFMono-Regular, Menlo, Consolas, "Liberation Mono", "Courier New", monospace; } '
    "html { font-size: 16px; padding-top: 24px; } #write { max-width: 760px; margin: 0 auto; }"
)


def viewer_page(tool, lang):
    ui = UI[lang]["viewer"]
    sample = (SRC / f"markdown-viewer-sample.{lang}.md").read_text(encoding="utf-8").rstrip("\n")
    data = {
        "lang": lang,
        "parser": [versioned("assets/vendor/markdown-it-14.1.0.min.js"), versioned("assets/vendor/highlight-11.5.1.min.js")],
        "katex": [versioned("assets/vendor/katex-0.16.47.min.js")],
        "katexCss": versioned("assets/vendor/katex/katex.min.css"),
        "mermaid": [versioned(p) for p in sorted(mermaid_assets.VENDOR, key=lambda p: "mermaid-" in p)],
        "mermaidConfig": mermaid_assets.CONFIG,
        "css": [versioned(f"assets/vendor/preview/{c}.css") for c in PREVIEW_CSS],
        "pageCss": PREVIEW_PAGE_CSS,
        "site": SITE,
        "strings": ui["strings"],
    }
    tool_html = f"""  <div class="tool viewer-tool" id="viewer-tool">
    <div class="table-bar">
      <label class="tool-chip viewer-open">{esc(ui["open"])}<input type="file" id="viewer-file" accept=".md,.markdown,.mdown,.mkd,.txt,text/markdown,text/plain" class="visually-hidden"></label>
      <button type="button" class="tool-chip viewer-only" id="viewer-only" aria-pressed="false">{esc(ui["preview_only"])}</button>
    </div>
    <div class="tool-grid viewer-grid" id="viewer-grid">
      <div class="tool-editor">
        <label class="visually-hidden" for="viewer-code">{esc(ui["code"])}</label>
        <textarea id="viewer-code" class="tool-code viewer-code" data-highlight spellcheck="false" autocapitalize="off" autocomplete="off" autocorrect="off" wrap="soft">{esc(sample)}</textarea>
      </div>
      <div class="viewer-frame"><iframe id="viewer-preview" title="{esc(ui["preview"])}" sandbox="allow-same-origin allow-popups allow-popups-to-escape-sandbox allow-modals" srcdoc="&lt;!doctype html&gt;&lt;title&gt;&lt;/title&gt;"></iframe></div>
    </div>
    <div class="tool-foot">
      <p class="tool-status" id="viewer-status" role="status" aria-live="polite"></p>
    </div>
    <div class="tool-actions">
      <button type="button" class="btn btn-primary" data-action="pdf">{esc(ui["pdf"])}</button>
      <button type="button" class="btn btn-ghost" data-action="html">{esc(ui["html"])}</button>
      <button type="button" class="btn btn-ghost" data-action="copy">{esc(ui["copy"])}</button>
    </div>
  </div>"""
    return tool_page(tool, lang, category="UtilitiesApplication", tool_html=tool_html,
                     data_id="viewer-data", data=data, script="assets/tools/markdown-viewer.js",
                     before=("assets/tools/md-highlight.js",))


APP_TEXT_FONT = "-apple-system, BlinkMacSystemFont, Helvetica Neue, PingFang SC, Hiragino Sans GB, Microsoft YaHei UI, Microsoft YaHei, Arial, sans-serif"
APP_CODE_FONT = 'SFMono-Regular, Menlo, Consolas, "Liberation Mono", "Courier New", monospace'


def markmap_page(tool, lang):
    ui = UI[lang]["markmap"]
    sample = (SRC / f"markmap-editor-sample.{lang}.md").read_text(encoding="utf-8").rstrip("\n")
    data = {
        "vendor": [versioned(p) for p in ("assets/vendor/d3-6.7.0.min.js", "assets/vendor/markmap-0.14.min.js", "assets/vendor/miaoyan-theme-config.js")],
        "katex": [versioned("assets/vendor/katex-0.16.47.min.js")],
        "katexCss": versioned("assets/vendor/katex/katex.min.css"),
        # MiaoYan's preview text, code and link colours and font stacks (theme-light.css).
        "font": APP_TEXT_FONT,
        "codeFont": APP_CODE_FONT,
        "ink": "#262626",
        "link": "#1C5D33",
        "strings": ui["strings"],
    }
    zoom = "".join(
        f'<button type="button" class="tool-zoom-btn" data-zoom="{k}" aria-label="{esc(ui[label])}" title="{esc(ui[label])}">{ICON[icon]}</button>'
        for k, label, icon in (("out", "zoom_out", "minus"), ("in", "zoom_in", "plus"), ("fit", "fit", "fit"))
    )
    tool_html = f"""  <div class="tool markmap-tool" id="markmap-tool">
    <div class="tool-grid">
      <div class="tool-editor">
        <label class="visually-hidden" for="markmap-code">{esc(ui["code"])}</label>
        <textarea id="markmap-code" class="tool-code viewer-code" data-highlight spellcheck="false" autocapitalize="off" autocomplete="off" autocorrect="off" wrap="soft">{esc(sample)}</textarea>
      </div>
      <div class="tool-preview markmap-frame" id="markmap-frame">
        <svg id="markmap-svg" class="markmap-svg" role="img" aria-label="{esc(ui["preview"])}"></svg>
        <div class="tool-zoom" role="group" aria-label="{esc(ui["zoom"])}">{zoom}</div>
      </div>
    </div>
    <div class="tool-foot">
      <p class="tool-status" id="markmap-status" role="status" aria-live="polite"></p>
    </div>
    <div class="tool-actions">
      <button type="button" class="btn btn-primary" data-action="png">{esc(ui["png"])}</button>
      <button type="button" class="btn btn-ghost" data-action="image" hidden>{esc(ui["copy_image"])}</button>
      <button type="button" class="btn btn-ghost" data-action="svg">{esc(ui["svg"])}</button>
      <button type="button" class="btn btn-ghost" data-action="markdown">{esc(ui["markdown"])}</button>
    </div>
  </div>"""
    return tool_page(tool, lang, category="DesignApplication", tool_html=tool_html,
                     data_id="markmap-data", data=data, script="assets/tools/markmap-editor.js",
                     before=("assets/tools/md-highlight.js",))


def typography_page(tool, lang):
    ui = UI[lang]["typography"]
    sample = (SRC / f"chinese-typography-cleaner-sample.{lang}.md").read_text(encoding="utf-8").rstrip("\n")
    data = {"strings": ui["strings"]}
    tool_html = f"""  <div class="tool typography-tool" id="typography-tool">
    <div class="table-bar">
      <label class="tool-chip viewer-open">{esc(ui["open"])}<input type="file" id="typography-file" accept=".md,.markdown,.mdown,.mkd,.txt,text/markdown,text/plain" class="visually-hidden"></label>
    </div>
    <div class="tool-grid">
      <div class="tool-editor">
        <label class="visually-hidden" for="typography-code">{esc(ui["code"])}</label>
        <textarea id="typography-code" class="tool-code viewer-code" data-highlight spellcheck="false" autocapitalize="off" autocomplete="off" autocorrect="off" wrap="soft">{esc(sample)}</textarea>
      </div>
      <div class="tool-editor tc-pane">
        <div class="tool-code viewer-code tc-result" id="typography-result" role="region" tabindex="0" aria-label="{esc(ui["result"])}"></div>
      </div>
    </div>
    <div class="tool-foot">
      <p class="tool-status" id="typography-status" role="status" aria-live="polite"></p>
    </div>
    <div class="tool-actions">
      <button type="button" class="btn btn-primary" data-action="copy">{esc(ui["copy"])}</button>
      <button type="button" class="btn btn-ghost" data-action="download">{esc(ui["download"])}</button>
    </div>
  </div>"""
    return tool_page(tool, lang, category="UtilitiesApplication", tool_html=tool_html,
                     data_id="typography-data", data=data, script="assets/tools/chinese-typography-cleaner.js",
                     before=("assets/tools/md-highlight.js", "assets/tools/typography-cleaner.js"))


NNW_REPO = "https://github.com/tw93/MiaoYan-NetNewsWire-Theme"
NNW_ZIP = NNW_REPO + "/releases/latest/download/MiaoYan.nnwtheme.zip"


def nnw_page(tool, lang):
    """The NetNewsWire theme: a MiaoYan post as NetNewsWire shows it with the
    theme (scripts/render-netnewswire-theme.mjs), light or dark, and the ways
    to install it."""
    ui = UI[lang]["nnw"]
    sizes = json.loads((ROOT / "img" / "tools" / "netnewswire-theme.json").read_text(encoding="utf-8"))
    chips = "".join(
        f'<button type="button" class="tool-chip" data-scheme="{s}" aria-pressed="{"true" if s == "light" else "false"}">{esc(ui[s])}</button>'
        for s in ("light", "dark")
    )
    shots = []
    for s in ("light", "dark"):
        name = f"netnewswire-theme-{lang}-{s}.webp"
        phone = f"netnewswire-theme-{lang}-{s}-phone.webp"
        size, small = sizes[name], sizes[phone]
        lazy = ' fetchpriority="high"' if s == "light" else ' loading="lazy"'
        # The phone shot is the article at a phone's width, not the Mac one shrunk.
        shots.append(
            f'<picture class="nnw-shot" data-scheme="{s}"{"" if s == "light" else " hidden"}>'
            f'<source media="(max-width: 560px)" srcset="{versioned("img/tools/" + phone)}" width="{small["width"] // 2}" height="{small["height"] // 2}">'
            f'<img src="{versioned("img/tools/" + name)}" width="{size["width"] // 2}" height="{size["height"] // 2}"'
            f' alt="{esc(ui["preview"].format(scheme=ui[s]))}" decoding="async"{lazy}></picture>'
        )
    install = "netnewswire://theme/add?url=" + NNW_ZIP
    tool_html = f"""  <div class="tool nnw-tool" id="nnw-tool">
    <div class="tool-templates" role="group" aria-label="{esc(ui["appearance"])}">{chips}</div>
    <div class="nnw-frame is-light" id="nnw-frame">
      {shots[0]}
      {shots[1]}
    </div>
    <div class="tool-foot">
      <p class="tool-status" id="nnw-status" role="status" aria-live="polite"></p>
    </div>
    <div class="tool-actions">
      <a class="btn btn-primary" href="{esc(install)}" data-action="install">{esc(ui["install"])}</a>
      <a class="btn btn-ghost" href="{NNW_ZIP}">{esc(ui["zip"])}</a>
      <a class="btn btn-ghost" href="{NNW_REPO}" target="_blank" rel="noopener">{esc(ui["github"])}</a>
    </div>
  </div>"""
    return tool_page(tool, lang, category="UtilitiesApplication", tool_html=tool_html,
                     data_id="nnw-data", data={"strings": ui["strings"]}, script="assets/tools/netnewswire-theme.js",
                     system="macOS, iOS, iPadOS")


def hub_page(tools, lang):
    """/tools/: every tool with its lede, on the blog index's cards."""
    hub = UI[lang]["hub"]
    canonical = SITE + route(lang)
    graph = [
        {
            "@type": "BreadcrumbList",
            "itemListElement": [
                {"@type": "ListItem", "position": 1, "name": UI[lang]["home_name"], "item": SITE + site.lang_entry(lang)[1]},
                {"@type": "ListItem", "position": 2, "name": hub["title"], "item": canonical},
            ],
        },
        {
            "@type": "CollectionPage",
            "name": hub["title"],
            "description": hub["description"],
            "url": canonical,
            "inLanguage": site.lang_entry(lang)[2],
            "hasPart": [{"@type": "WebApplication", "@id": SITE + route(lang, t["slug"]) + "#app", "name": t[lang]["title"]} for t in tools],
        },
    ]
    out = head(
        lang, title=hub["head_title"], desc=hub["description"], canonical=canonical,
        en_url=SITE + route("en"), zh_url=SITE + route("zh"),
        jsonld={"@context": "https://schema.org", "@graph": graph},
    )
    cards = "".join(
        f'<li class="blog-card"><a href="{route(lang, t["slug"])}"><span class="blog-card-body">'
        f'<h2 class="blog-card-title">{esc(t[lang]["title"])}</h2>'
        f'<span class="blog-card-desc">{esc(t[lang]["lede"])}</span>'
        f"</span></a></li>"
        for t in tools
    )
    main = f"""<main class="blog-index">
  <h1 class="section-title">{esc(hub["title"])}</h1>
  <p class="section-lede">{esc(hub["lede"])}</p>
  <ul class="blog-cards">{cards}</ul>
</main>"""
    return out + shell(lang, None, main, "")


def replace_block(text, inner, name):
    start, end = "<!-- tools:start -->", "<!-- tools:end -->"
    pattern = re.compile(re.escape(start) + ".*?" + re.escape(end), re.S)
    if not pattern.search(text):
        raise BuildError(f"{name} is missing the {start} {end} markers")
    return pattern.sub(lambda _: start + inner + end, text)


def sitemap_block(tools):
    latest = max(t.get("modified") or t["date"] for t in tools)
    rows = [(SITE + route(lang), latest) for lang in LANGS]
    rows += [(SITE + route(lang, t["slug"]), t.get("modified") or t["date"]) for t in tools for lang in LANGS]
    return "".join(f"\n  <url>\n    <loc>{loc}</loc>\n    <lastmod>{mod}</lastmod>\n  </url>" for loc, mod in rows) + "\n  "


def llms_block(tools):
    lines = ["## Tools", ""]
    for lang in LANGS:
        hub = UI[lang]["hub"]
        lines.append(f"- [{hub['title']}]({SITE}{route(lang)}): {hub['description']}")
    for t in tools:
        for lang in LANGS:
            lines.append(f"- [{t[lang]['title']}]({SITE}{route(lang, t['slug'])}): {t[lang]['description']}")
    return "\n" + "\n".join(lines) + "\n"


PAGES = {"mermaid-editor": mermaid_page, "markdown-table-generator": table_page, "markdown-viewer": viewer_page, "markmap-editor": markmap_page, "chinese-typography-cleaner": typography_page, "netnewswire-theme": nnw_page}
PAGE_KEY = {"mermaid-editor": "mermaid", "markdown-table-generator": "table", "markdown-viewer": "viewer", "markmap-editor": "markmap", "chinese-typography-cleaner": "typography", "netnewswire-theme": "nnw"}


def outputs(tools):
    files = {}
    for lang in LANGS:
        files[output(lang)] = hub_page(tools, lang)
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
