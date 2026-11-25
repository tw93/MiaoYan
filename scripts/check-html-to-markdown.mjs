#!/usr/bin/env node
// assets/tools/html-to-markdown-core.js is a port of MiaoYan's HtmlToMarkdown
// (Helpers/HtmlToMarkdown.swift on the app's main branch), what the app does
// with rich text pasted into a note. This keeps the two giving the same answer.
//
//   node scripts/check-html-to-markdown.mjs              run the port in Chromium
//                                                        over data/html-to-markdown-
//                                                        fixtures.json and fail on
//                                                        any difference
//   node scripts/check-html-to-markdown.mjs --regenerate compile the Swift file from
//                                                        origin/main with swiftc, run
//                                                        it over the app's own test
//                                                        HTML and the bodies of 24
//                                                        built blog posts (half of
//                                                        them behind Chrome's
//                                                        clipboard <meta charset>),
//                                                        and write the fixtures
//
// Both need playwright-core and a Chromium (as the render scripts);
// --regenerate also needs macOS with swiftc, the app's origin/main fetched and
// the site built.
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const fixturesPath = join(root, "data", "html-to-markdown-fixtures.json");
const portPath = join(root, "assets", "tools", "html-to-markdown-core.js");
const SWIFT_PATH = "Helpers/HtmlToMarkdown.swift";
const TESTS_PATH = "MiaoYanTests/HtmlToMarkdownTests.swift";
const POSTS = 12;
// Shapes a clipboard carries that the app's tests and the blog do not: HTML5
// containers, addresses with spaces and CJK, comments.
const PROBES = [
  "<p>a</p><figure><picture><source srcset=\"m.png\"><img src=\"x.png\" alt=\"pic\"></picture><figcaption>cap</figcaption></figure><p>b</p>",
  "<p><a href=\"a b/图.png?q=中&x=1#片\">t</a> <img src=\"图 1.png\" alt=\"i\"></p>",
  "<section><h2>s</h2><p>x</p></section><article><p>y</p></article><main><p>z</p></main>",
  "<details><summary>sum</summary><p>body</p></details><header><p>h</p></header><footer><p>f</p></footer><p>tail <mark>m</mark></p>",
  "<!--StartFragment--><h2>T</h2><p>x</p><!--EndFragment-->",
  "<p>a<span>  </span>b</p><h3>x</h3><ol><li><p>one</p><p>two</p></li><li>three</li></ol>",
];
// What the page gives where it leaves tidy's two bugs out.
const OWN = [
  ["<p>a</p><figure><img src=\"x.png\" alt=\"pic\"><figcaption>cap</figcaption></figure><p>b</p>", "a\n\n![pic](x.png)\n\ncap\n\nb"],
  ["<!--StartFragment--><h2>T</h2><p>x</p><!--EndFragment-->", "## T\n\nx"],
  // Google Docs: one <b> around the copy, bold and italic as span styles.
  ["<meta charset=\"utf-8\"><b style=\"font-weight:normal;\" id=\"docs-internal-guid-1\"><h1 dir=\"ltr\"><span style=\"font-size:20pt;font-weight:700\">Title</span></h1><p dir=\"ltr\"><span style=\"font-weight:700\">bold</span><span style=\"font-weight:400\"> and </span><span style=\"font-style:italic\">it</span> <span style=\"text-decoration:line-through\">gone</span></p><ul><li><p>one</p></li></ul></b>", "# Title\n\n**bold** and *it* ~~gone~~\n\n- one"],
  // Word: list paragraphs with their marker in an mso-list:Ignore span, one level deeper in the middle.
  ["<p class=MsoListParagraphCxSpFirst style='mso-list:l0 level1 lfo1'><span style='mso-list:Ignore'>1.<span>&nbsp;&nbsp;</span></span>first</p><p class=MsoListParagraphCxSpMiddle style='mso-list:l0 level2 lfo1'><![if !supportLists]><span style='mso-list:Ignore'>o<span>&nbsp;</span></span><![endif]>inner</p><p class=MsoListParagraphCxSpLast style='mso-list:l0 level1 lfo1'><span style='mso-list:Ignore'>2.<span>&nbsp;&nbsp;</span></span>second</p><p class=MsoNormal>after</p>", "1. first\n   - inner\n2. second\n\nafter"],
];

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

async function browser() {
  const pwDir = process.env.PLAYWRIGHT_CORE || join(homedir(), ".cache", "site-shot", "node_modules", "playwright-core");
  const { chromium } = createRequire(join(root, "package.json"))(pwDir);
  const b = await chromium.launch({ executablePath: findChromium() });
  const page = await b.newPage();
  await page.setContent("<!doctype html><title>port</title>");
  await page.addScriptTag({ content: readFileSync(portPath, "utf8") });
  return { b, page };
}

// The HTML strings the app's tests hand to convert() and convertIfStructured().
function testHtml(source) {
  const out = [];
  const lit = /"((?:[^"\\]|\\.)*)"/g;
  const unescape = (s) => s.replace(/\\u\{([0-9a-fA-F]+)\}|\\(.)/g, (_, hex, ch) => {
    if (hex) return String.fromCodePoint(parseInt(hex, 16));
    return { n: "\n", t: "\t", r: "\r", "0": "\0" }[ch] ?? ch;
  });
  for (const line of source.split("\n")) {
    if (!/convert(IfStructured)?\(|let html = /.test(line)) continue;
    let m;
    while ((m = lit.exec(line))) {
      const s = unescape(m[1]);
      if (/</.test(s)) out.push(s);
    }
  }
  return [...new Set(out)];
}

async function regenerate() {
  const work = mkdtempSync(join(tmpdir(), "html2md-"));
  const { b, page } = await browser();
  try {
    const app = join(homedir(), "www", "MiaoYan");
    const show = (p) => execFileSync("git", ["-C", app, "show", `origin/main:${p}`], { encoding: "utf8", maxBuffer: 1 << 26 });
    const commit = execFileSync("git", ["-C", app, "rev-parse", "--short", "origin/main"], { encoding: "utf8" }).trim();
    const inputs = testHtml(show(TESTS_PATH)).concat(PROBES);
    for (const dir of ["blog", "zh/blog"]) {
      const posts = readdirSync(join(root, dir), { withFileTypes: true })
        .filter((d) => d.isDirectory() && existsSync(join(root, dir, d.name, "index.html")))
        .map((d) => d.name).sort().slice(0, POSTS);
      for (const [i, slug] of posts.entries()) {
        const html = readFileSync(join(root, dir, slug, "index.html"), "utf8");
        const body = await page.evaluate((h) => {
          const el = new DOMParser().parseFromString(h, "text/html").querySelector(".blog-body");
          return el ? el.innerHTML : "";
        }, html);
        if (body) inputs.push(i % 2 ? "<meta charset='utf-8'>" + body : body);
      }
    }
    writeFileSync(join(work, "HtmlToMarkdown.swift"), show(SWIFT_PATH));
    writeFileSync(join(work, "main.swift"), `import Foundation
let inputs = try! JSONDecoder().decode([String].self, from: FileHandle.standardInput.readDataToEndOfFile())
FileHandle.standardOutput.write(try! JSONEncoder().encode(inputs.map { HtmlToMarkdown.convert($0) }))
`);
    const bin = join(work, "h2m");
    execFileSync("swiftc", ["-O", "-o", bin, join(work, "HtmlToMarkdown.swift"), join(work, "main.swift")], { stdio: "inherit" });
    const outputs = JSON.parse(execFileSync(bin, [], { input: JSON.stringify(inputs), maxBuffer: 1 << 28 }).toString("utf8"));
    const cases = inputs.map((html, i) => ({ html, markdown: outputs[i] }));
    writeFileSync(fixturesPath, JSON.stringify({ source: `MiaoYan ${commit} ${SWIFT_PATH}`, cases }, null, 1) + "\n");
    console.log(`wrote ${cases.length} cases from MiaoYan ${commit}`);
  } finally {
    await b.close();
    rmSync(work, { recursive: true, force: true });
  }
}

async function check() {
  const { source, cases } = JSON.parse(readFileSync(fixturesPath, "utf8"));
  const { b, page } = await browser();
  try {
    const got = await page.evaluate((cs) => cs.map((c) => window.MiaoYanHtmlToMarkdown.convert(c.html, { tidy: true })), cases);
    const own = await page.evaluate((cs) => cs.map((c) => window.MiaoYanHtmlToMarkdown.convert(c[0])), OWN);
    own.forEach((g, i) => {
      if (g !== OWN[i][1]) {
        console.error(`the page's own output for ${JSON.stringify(OWN[i][0])}\n  want: ${JSON.stringify(OWN[i][1])}\n  got:  ${JSON.stringify(g)}`);
        process.exitCode = 1;
      }
    });
    const bad = cases.map((c, i) => [c, got[i]]).filter(([c, g]) => c.markdown !== g);
    for (const [c, g] of bad.slice(0, 5)) {
      const a = c.markdown, at = [...a].findIndex((ch, i) => ch !== [...g][i]);
      console.error(`differs at ${at} for ${JSON.stringify(c.html.slice(0, 80))}\n  app:  ${JSON.stringify(a.slice(Math.max(0, at - 40), at + 60))}\n  port: ${JSON.stringify(g.slice(Math.max(0, at - 40), at + 60))}`);
    }
    if (bad.length) {
      console.error(`html-to-markdown: ${bad.length} of ${cases.length} cases differ from ${source}`);
      process.exitCode = 1;
    } else {
      console.log(`html-to-markdown-ok (${cases.length} cases, ${source})`);
    }
  } finally {
    await b.close();
  }
}

await (process.argv.includes("--regenerate") ? regenerate() : check());
