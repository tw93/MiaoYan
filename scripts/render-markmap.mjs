#!/usr/bin/env node
// Draw every ```markmap example in content/blog/*.md (written inside a
// ````markdown fence, so readers see the source) into img/markmap/<hash>.svg
// with the site's own Markmap editor, and delete SVGs no post uses. The file
// is the editor's Download SVG, so the blog shows what the editor draws. The
// hash is the first 12 hex digits of the outline's SHA-256 (build-blog.py
// markmap_digest); an editor change does not redraw existing files.
//
//   node scripts/render-markmap.mjs
//
// It needs playwright-core and a Chromium, found as render-mermaid.mjs finds them.
import { createRequire } from "node:module";
import { createHash } from "node:crypto";
import { createServer } from "node:http";
import { existsSync, mkdirSync, readdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const outDir = join(root, "img", "markmap");
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

const WRAPPED = /^````markdown\n```markmap\n([\s\S]*?)\n```\n````$/gm;
const blogDir = join(root, "content", "blog");
const wanted = new Map();
for (const name of readdirSync(blogDir).filter((n) => n.endsWith(".md"))) {
  for (const m of readFileSync(join(blogDir, name), "utf8").matchAll(WRAPPED)) {
    wanted.set(createHash("sha256").update(m[1]).digest("hex").slice(0, 12), m[1]);
  }
}

for (const name of readdirSync(outDir)) {
  if (name.endsWith(".svg") && !wanted.has(name.slice(0, -4))) {
    unlinkSync(join(outDir, name));
    console.log(`removed img/markmap/${name}`);
  }
}

const todo = [...wanted].filter(([h]) => !existsSync(join(outDir, `${h}.svg`)));
if (todo.length) {
  const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".svg": "image/svg+xml", ".woff2": "font/woff2", ".webp": "image/webp" };
  const server = createServer((req, res) => {
    let path = normalize(decodeURIComponent(req.url.split("?")[0].split("#")[0]));
    if (path.endsWith("/")) path += "index.html";
    const file = join(root, path);
    if (!file.startsWith(root) || !existsSync(file)) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { "content-type": types[extname(file)] || "application/octet-stream" });
    res.end(readFileSync(file));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ executablePath: findChromium() });
  let failed = 0;
  try {
    for (const [h, outline] of todo) {
      const context = await browser.newContext({ acceptDownloads: true, viewport: { width: 1280, height: 900 } });
      const page = await context.newPage();
      const link = Buffer.from(outline).toString("base64url");
      await page.goto(`${base}/tools/markmap-editor/#b=${link}`);
      try {
        await page.waitForFunction((text) => document.getElementById("markmap-code").value === text
          && document.querySelectorAll("#markmap-svg g.markmap-node").length > 0, outline, { timeout: 15000 });
        const [download] = await Promise.all([page.waitForEvent("download"), page.click('[data-action="svg"]')]);
        writeFileSync(join(outDir, `${h}.svg`), readFileSync(await download.path()));
        console.log(`drew img/markmap/${h}.svg`);
      } catch (error) {
        failed++;
        console.error(`img/markmap/${h}.svg: ${error.message}`);
      }
      await context.close();
    }
  } finally {
    await browser.close();
    server.close();
  }
  if (failed) process.exit(1);
}
