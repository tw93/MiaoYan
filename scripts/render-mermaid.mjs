#!/usr/bin/env node
// Draw every diagram in data/mermaid-manifest.json into img/mermaid/<hash>.svg
// with the vendored Mermaid and MiaoYan theme, in headless Chromium, and delete
// SVGs the manifest no longer lists. Run python3 -I scripts/mermaid_assets.py
// first; it writes the manifest and its --check says when this is needed.
//
//   node scripts/render-mermaid.mjs           draw the missing SVGs
//
// It needs playwright-core and a Chromium. Set PLAYWRIGHT_CORE to the
// playwright-core package directory and CHROMIUM to the browser binary, or it
// looks in ~/.cache/site-shot and Playwright's own browser cache.
import { createRequire } from "node:module";
import { existsSync, readdirSync, readFileSync, unlinkSync, writeFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(join(root, "data", "mermaid-manifest.json"), "utf8"));
const outDir = join(root, "img", "mermaid");
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

const wanted = manifest.diagrams;
// Names cover the renderer too (scripts/mermaid_assets.py), so an existing file
// is never redrawn: the site serves these as immutable.
const todo = Object.keys(wanted).filter((h) => !existsSync(join(outDir, `${h}.svg`)));

let failed = 0;
if (todo.length) {
  const browser = await chromium.launch({ executablePath: findChromium() });
  const page = await browser.newPage();
  await page.setContent("<!doctype html><html><body></body></html>");
  for (const path of manifest.vendor) await page.addScriptTag({ path: join(root, path) });
  await page.evaluate((config) => {
    window.mermaid.initialize(Object.assign({}, window.ThemeColors.getMermaidConfig(false), config));
  }, manifest.config);
  for (const h of todo) {
    const result = await page.evaluate(async ({ id, code }) => {
      try {
        const { svg } = await window.mermaid.render(id, code);
        // Fixed width and height from the viewBox, so an <img> of this file has
        // an intrinsic size and the page reserves its box before it loads.
        const doc = new DOMParser().parseFromString(svg, "image/svg+xml");
        const el = doc.documentElement;
        const box = (el.getAttribute("viewBox") || "").split(/[\s,]+/).map(Number);
        if (box.length !== 4 || !(box[2] > 0) || !(box[3] > 0)) return { error: "no viewBox" };
        el.setAttribute("width", String(Math.ceil(box[2])));
        el.setAttribute("height", String(Math.ceil(box[3])));
        el.style.removeProperty("max-width");
        if (!el.getAttribute("style")) el.removeAttribute("style");
        el.setAttribute("xmlns", "http://www.w3.org/2000/svg");
        return { svg: new XMLSerializer().serializeToString(el) };
      } catch (e) {
        return { error: String((e && e.message) || e).split("\n").slice(0, 3).join(" ") };
      }
    }, { id: `m${h}`, code: wanted[h] });
    if (result.error) {
      failed += 1;
      console.error(`render failed ${h}: ${result.error}\n${wanted[h]}\n`);
      continue;
    }
    writeFileSync(join(outDir, `${h}.svg`), result.svg + "\n");
  }
  await browser.close();
}

let removed = 0;
for (const file of readdirSync(outDir)) {
  if (file.endsWith(".svg") && !(file.slice(0, -4) in wanted)) {
    unlinkSync(join(outDir, file));
    removed += 1;
  }
}
console.log(`mermaid: drew ${todo.length - failed}, failed ${failed}, removed ${removed}`);
process.exit(failed ? 1 : 0);
