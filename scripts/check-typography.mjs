#!/usr/bin/env node
// assets/tools/typography-cleaner.js is a port of MiaoYan's TypographyCleaner
// (Helpers/TypographyCleaner.swift on the app's main branch). This keeps the
// two giving the same answer.
//
//   node scripts/check-typography.mjs              run the port over
//                                                  data/typography-fixtures.json
//                                                  and fail on any difference
//   node scripts/check-typography.mjs --regenerate compile the Swift file from
//                                                  origin/main with swiftc, run it
//                                                  over the app's own test strings
//                                                  and a seeded random corpus, and
//                                                  write the fixtures; also rewrite
//                                                  the port's NUMERIC table
//
// --regenerate needs macOS with swiftc and the app's origin/main fetched.
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const fixturesPath = join(root, "data", "typography-fixtures.json");
const portPath = join(root, "assets", "tools", "typography-cleaner.js");
const SWIFT_PATH = "Helpers/TypographyCleaner.swift";
const TESTS_PATH = "MiaoYanTests/TypographyCleanerTests.swift";

function port() {
  const require = createRequire(import.meta.url);
  delete require.cache[portPath];
  return require(portPath);
}

// Swift string literals in the app's tests, "..." and """...""".
function swiftLiterals(source) {
  const out = [];
  const unescape = (s) => s.replace(/\\u\{([0-9a-fA-F]+)\}|\\(.)/g, (_, hex, ch) => {
    if (hex) return String.fromCodePoint(parseInt(hex, 16));
    return { n: "\n", t: "\t", r: "\r", "0": "\0", "\\": "\\", "\"": "\"", "'": "'" }[ch] ?? ch;
  });
  for (const m of source.matchAll(/"""\n([\s\S]*?)\n(\s*)"""/g)) {
    const indent = m[2];
    out.push(unescape(m[1].split("\n").map((l) => (l.startsWith(indent) ? l.slice(indent.length) : l)).join("\n")));
  }
  const single = source.replace(/"""[\s\S]*?"""/g, "");
  for (const m of single.matchAll(/"((?:[^"\\\n]|\\.)*)"/g)) out.push(unescape(m[1]));
  return [...new Set(out)];
}

// A seeded corpus of mixed Chinese, Latin, digits, punctuation and Markdown.
function corpus(count) {
  let seed = 20261125;
  const rand = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
  const pick = (a) => a[Math.floor(rand() * a.length)];
  const atoms = [
    "中文", "妙言", "笔记", "あいう", "カタカナ", "한국", "三", "万", "English", "Swift", "iOS", "v2", "3.5", "10:00", "42", "Ａｂｃ１２",
    ",", ".", ":", ";", "!", "?", "，", "。", "：", "！", "、", "（", "）", "「", "」", "《", "》", "“", "”", "\"", "'",
    " ", " ", "  ", "\t", "...", "……", "—", "——", " — ", "`", "``", "`code`", "$", "$x$", "$5", "$$", "[", "]", "[[", "]]", "(", ")", "](",
    "[链接](https://a.b/c)", "[[页面]]", "https://example.com/路径,中文", "http://a.b", "<", ">", "> ", "*", "**", "_", "#", "- ", "1. ",
    "é", "́", "👍🏽", "👨‍👩‍👧", "😀", "​", "　", " ", "\r", "Ａ", "ｚ", "０", "Ⅻ", "½", "٣",
  ];
  const lineStarts = ["", "", "", "", "> ", "> > ", "    ", "\t", "- ", "## ", "```", "~~~", "````js", "$$", "---", "[ref]: ", "[^1]: "];
  const out = [];
  for (let n = 0; n < count; n++) {
    const lines = [];
    const lineCount = 1 + Math.floor(rand() * 6);
    for (let l = 0; l < lineCount; l++) {
      let line = pick(lineStarts);
      const len = Math.floor(rand() * 14);
      for (let k = 0; k < len; k++) line += pick(atoms);
      if (rand() < 0.15) line = "";
      lines.push(line);
    }
    let text = lines.join("\n");
    if (rand() < 0.3) text += "\n";
    out.push(text);
  }
  return out;
}

function regenerate() {
  const work = mkdtempSync(join(tmpdir(), "typography-"));
  try {
    const app = join(process.env.HOME, "www", "MiaoYan");
    const show = (p) => execFileSync("git", ["-C", app, "show", `origin/main:${p}`], { encoding: "utf8", maxBuffer: 1 << 26 });
    const commit = execFileSync("git", ["-C", app, "rev-parse", "--short", "origin/main"], { encoding: "utf8" }).trim();
    writeFileSync(join(work, "TypographyCleaner.swift"), show(SWIFT_PATH));
    writeFileSync(join(work, "main.swift"), `import Foundation
if CommandLine.arguments.count > 1 {
    var out: [String] = []
    for v in 0...0x10FFFF { if let s = Unicode.Scalar(UInt32(v)), s.properties.numericType != nil { out.append(String(v)) } }
    print(out.joined(separator: ","))
    exit(0)
}
let inputs = try! JSONDecoder().decode([String].self, from: FileHandle.standardInput.readDataToEndOfFile())
FileHandle.standardOutput.write(try! JSONEncoder().encode(inputs.map { TypographyCleaner.clean($0) }))
`);
    const bin = join(work, "tc");
    execFileSync("swiftc", ["-O", "-o", bin, join(work, "TypographyCleaner.swift"), join(work, "main.swift")], { stdio: "inherit" });

    const inputs = [...swiftLiterals(show(TESTS_PATH)), ...corpus(3000)];
    const outputs = JSON.parse(execFileSync(bin, [], { input: JSON.stringify(inputs), maxBuffer: 1 << 28 }).toString("utf8"));
    const cases = inputs.map((input, i) => [input, outputs[i]]);
    writeFileSync(fixturesPath, JSON.stringify({ source: `MiaoYan ${commit} ${SWIFT_PATH}`, cases }) + "\n");

    const values = execFileSync(bin, ["numeric"], { encoding: "utf8", maxBuffer: 1 << 26 }).trim().split(",").map(Number);
    const ranges = [];
    for (const v of values) {
      if (ranges.length && v === ranges[ranges.length - 1][1] + 1) ranges[ranges.length - 1][1] = v;
      else ranges.push([v, v]);
    }
    const flat = ranges.map(([a, b]) => `${a.toString(16)},${b.toString(16)}`).join(",");
    const src = readFileSync(portPath, "utf8");
    const next = src.replace(/var NUMERIC = "[^"]*"/, `var NUMERIC = "${flat}"`);
    if (next === src && !src.includes(flat)) throw new Error("NUMERIC table not found in the port");
    writeFileSync(portPath, next);
    console.log(`wrote ${cases.length} cases from MiaoYan ${commit}, ${ranges.length} numeric ranges`);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

function check() {
  const { source, cases } = JSON.parse(readFileSync(fixturesPath, "utf8"));
  const { clean } = port();
  const bad = [];
  for (const [input, expected] of cases) {
    const got = clean(input);
    if (got !== expected) bad.push({ input, expected, got });
  }
  for (const b of bad.slice(0, 5)) console.error(JSON.stringify(b));
  if (bad.length) {
    console.error(`typography: ${bad.length} of ${cases.length} differ from ${source}`);
    process.exit(1);
  }
  console.log(`typography-ok (${cases.length} cases, ${source})`);
}

if (process.argv.includes("--regenerate")) regenerate();
check();
