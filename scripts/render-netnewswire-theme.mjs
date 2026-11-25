#!/usr/bin/env node
// Draw the NetNewsWire theme's preview: a MiaoYan blog post as NetNewsWire
// shows it with tw93/MiaoYan-NetNewsWire-Theme, light and dark, English and
// Chinese, at NetNewsWire's Mac article width and at a phone's, into
// img/tools/netnewswire-theme-<lang>-<light|dark>[-phone].webp, plus
// img/tools/netnewswire-theme.json with each image's size for build-tools.py.
//
//   NNW_THEME=~/path/to/MiaoYan-NetNewsWire-Theme node scripts/render-netnewswire-theme.mjs
//
// The page is NetNewsWire's own Mac shell (Mac/MainWindow/Detail/page.html)
// holding its core.css, the theme's stylesheet.css and the theme's
// template.html. NetNewsWire loads a theme with the article's link as its base
// URL, so the TsangerJinKai file inside the theme never loads (its
// Technotes/Themes.md: "a theme can't load its own .js, image, or font
// files"); a reader sees it only with the font installed in macOS. The
// preview shows what everyone else sees, the stack's next face, PingFang SC,
// so TsangerJinKai is taken out of the stack here even on a Mac that has it.
// Needs playwright-core and a Chromium (as render-markmap.mjs) and cwebp.
import { createRequire } from "node:module";
import { createServer } from "node:http";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const theme = (process.env.NNW_THEME || "").replace(/^~(?=\/)/, homedir());
for (const f of ["stylesheet.css", "template.html"]) {
  if (!theme || !existsSync(join(theme, f))) {
    console.error(`NNW_THEME must point at a MiaoYan-NetNewsWire-Theme checkout (missing ${f}).`);
    process.exit(1);
  }
}
const outDir = join(root, "img", "tools");
mkdirSync(outDir, { recursive: true });

const pwDir = process.env.PLAYWRIGHT_CORE || join(homedir(), ".cache", "site-shot", "node_modules", "playwright-core");
const { chromium } = createRequire(join(root, "package.json"))(pwDir);
function findChromium() {
  if (process.env.CHROMIUM) return process.env.CHROMIUM;
  const cache = join(homedir(), "Library", "Caches", "ms-playwright");
  if (!existsSync(cache)) return undefined;
  for (const dir of readdirSync(cache).filter((d) => d.startsWith("chromium_headless_shell-")).sort().reverse()) {
    for (const bin of ["chrome-mac/headless_shell", "chrome-mac-arm64/headless_shell", "chrome-linux/headless_shell"]) {
      if (existsSync(join(cache, dir, bin))) return join(cache, dir, bin);
    }
  }
  return undefined;
}

// NetNewsWire's core.css, the part a theme sits on (Shared/Article Rendering).
const CORE_CSS = `html { scrollbar-gutter: stable; }
.articleBody, .article-body { position: relative; }
pre, code { tab-size: 4; }`;
const POST = "chinese-english-spacing";
// How many of the post's blocks to show: the title, its first paragraphs, a
// heading, a list and some code, about two windows tall.
const BLOCKS = 9;
const WIDTHS = { "": 800, "-phone": 390 };

const pages = new Map();
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".svg": "image/svg+xml", ".woff2": "font/woff2", ".webp": "image/webp", ".png": "image/png", ".ttf": "font/ttf" };
const server = createServer((req, res) => {
  const path = normalize(decodeURIComponent(req.url.split("?")[0].split("#")[0]));
  if (pages.has(path)) { res.writeHead(200, { "content-type": "text/html; charset=utf-8" }); res.end(pages.get(path)); return; }
  const file = join(root, path.endsWith("/") ? path + "index.html" : path);
  if (!file.startsWith(root) || !existsSync(file)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": types[extname(file)] || "application/octet-stream" });
  res.end(readFileSync(file));
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const base = `http://127.0.0.1:${server.address().port}`;

const fill = (template, values) => template.replace(/\[\[(\w+)\]\]/g, (_, k) => values[k] ?? "");
const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const original = readFileSync(join(theme, "stylesheet.css"), "utf8");
const stylesheet = original.replace(/"TsangerJinKai02",\s*/g, "");
if (stylesheet === original) throw new Error("stylesheet.css no longer names TsangerJinKai02; check what the preview should show");
const template = readFileSync(join(theme, "template.html"), "utf8");

const browser = await chromium.launch({ executablePath: findChromium() });
const sizes = {};
const scratch = join(tmpdir(), `nnw-${process.pid}`);
mkdirSync(scratch, { recursive: true });
try {
  for (const lang of ["en", "zh"]) {
    const prefix = lang === "zh" ? "/zh" : "";
    const reader = await browser.newPage();
    await reader.goto(`${base}${prefix}/blog/${POST}/`);
    const post = await reader.evaluate((n) => {
      const body = document.querySelector(".blog-body");
      const blocks = [...body.children].slice(0, n).map((el) => el.outerHTML).join("\n");
      const time = document.querySelector("time[datetime]");
      return {
        title: document.querySelector("h1").textContent.trim(),
        body: blocks,
        date: time ? time.getAttribute("datetime").slice(0, 10) : "",
        feed: document.querySelector('link[rel="alternate"][type="application/rss+xml"]').title,
      };
    }, BLOCKS);
    await reader.close();
    const [y, m, d] = post.date.split("-").map(Number);
    const when = new Intl.DateTimeFormat(lang === "zh" ? "zh-CN" : "en-US", { dateStyle: "short", timeStyle: "short" }).format(new Date(y, m - 1, d, 9, 30));
    const article = fill(template, {
      title: esc(post.title),
      preferred_link: `https://miaoyan.app${prefix}/blog/${POST}/`,
      feed_link: `https://miaoyan.app${prefix}/blog/feed.xml`,
      feed_link_title: esc(post.feed),
      avatar_src: `${base}/assets/icon-64.png`,
      datetime_short: esc(when),
      text_size_class: "mediumText",
      body: post.body,
    });
    const route = `/__nnw/${lang}.html`;
    pages.set(route, `<html dir="auto">\n\t<head>\n\t\t<title>${esc(post.title)}</title>\n\t\t<style>\n${CORE_CSS}\n${stylesheet}\n\t\t</style>\n\t\t<base href="${base}/">\n\t</head>\n\t<body>\n${article}\n\t</body>\n</html>`);
    for (const [suffix, width] of Object.entries(WIDTHS)) for (const scheme of ["light", "dark"]) {
      const page = await browser.newPage({ viewport: { width, height: 900 }, deviceScaleFactor: 2, colorScheme: scheme });
      await page.goto(base + route);
      await page.evaluate(() => document.fonts.ready);
      const height = await page.evaluate(() => Math.ceil(document.documentElement.scrollHeight));
      const png = join(scratch, `${lang}-${scheme}${suffix}.png`);
      await page.screenshot({ path: png, fullPage: true });
      await page.close();
      const name = `netnewswire-theme-${lang}-${scheme}${suffix}.webp`;
      execFileSync("cwebp", ["-quiet", "-q", "82", "-m", "6", png, "-o", join(outDir, name)]);
      sizes[name] = { width: width * 2, height: height * 2 };
      console.log(`drew img/tools/${name} (${width * 2}x${height * 2})`);
    }
  }
} finally {
  await browser.close();
  server.close();
  rmSync(scratch, { recursive: true, force: true });
}
writeFileSync(join(outDir, "netnewswire-theme.json"), JSON.stringify(sizes, null, 2) + "\n");
