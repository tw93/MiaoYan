// The Markdown viewer on /tools/markdown-viewer/ (scripts/build-tools.py).
// Markdown is parsed here with markdown-it and drawn into an iframe that holds
// MiaoYan's preview stylesheets, so the page's own styles and the note's never
// meet. The iframe runs no script (its sandbox has no allow-scripts); this page
// writes into it, which allow-same-origin permits, and prints from it.
// highlight.js, KaTeX and Mermaid are the app's own files; KaTeX and Mermaid
// load only once the text has math or a diagram. Nothing leaves the browser.
(function () {
  "use strict";
  var data = JSON.parse(document.getElementById("viewer-data").textContent);
  var S = data.strings;
  var tool = document.getElementById("viewer-tool");
  var grid = document.getElementById("viewer-grid");
  var code = document.getElementById("viewer-code");
  var frame = document.getElementById("viewer-preview");
  var status = document.getElementById("viewer-status");
  var fileInput = document.getElementById("viewer-file");
  var onlyButton = document.getElementById("viewer-only");
  var phoneButton = document.getElementById("viewer-phone");
  var countEl = document.getElementById("viewer-count");
  var frameBox = frame.parentNode;

  // The Markdown viewer, Markdown to Word and Markdown to image pages run
  // this same tool, each with its own draft.
  var TOOL = data.tool || "viewer";
  var DRAFT_KEY = data.draftKey || "miaoyan.markdown-viewer.draft";
  var MAX_BYTES = 5e6;
  var md = null;
  var write = null;
  var timer = 0;
  var seq = 0;
  var edited = false;
  var fileName = "";
  var scripts = {};
  var svgCache = {};
  var mermaidReady = null;
  var katexWait = null;
  // A failed KaTeX counts as drawn for saving: the formulas stay source.
  var katexFailed = false;
  var diagramsPending = false;
  function mathPending() { return needs.math && !window.katex && !katexFailed; }

  function track(name, params) {
    if (typeof window.gtag === "function") window.gtag("event", name, params || {});
  }

  function say(text) { status.textContent = text || ""; }

  function fill(template, values) {
    return template.replace(/\{(\w+)\}/g, function (_, k) { return values[k]; });
  }

  function esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  // Scripts in order, each added once; a failed one is forgotten so the next
  // try adds only that one again.
  function loadOne(src) {
    if (!scripts[src]) {
      scripts[src] = new Promise(function (resolve, reject) {
        var s = document.createElement("script");
        s.src = src;
        s.onload = resolve;
        s.onerror = function () { s.remove(); delete scripts[src]; reject(new Error(src)); };
        document.head.appendChild(s);
      });
    }
    return scripts[src];
  }

  function load(list) {
    var done = list.reduce(function (chain, src) {
      return chain.then(function () { return loadOne(src); });
    }, Promise.resolve());
    done.catch(function () { say(S.loadFailed); });
    return done;
  }

  // ---- Markdown ----------------------------------------------------------

  // $...$ inline and $$...$$ blocks, kept away from emphasis and escapes so a
  // formula reaches KaTeX as written. An opening $ is followed by a non-space,
  // a closing one preceded by a non-space and not followed by a digit, as in
  // Pandoc, so "$5 and $6" stays text.
  // A $ is escaped when an odd number of backslashes sits before it, so the
  // TeX line break in $a\\$ still closes.
  function escaped(src, at) {
    var n = 0;
    while (at - 1 - n >= 0 && src.charCodeAt(at - 1 - n) === 0x5C) n++;
    return n % 2 === 1;
  }

  function mathInline(state, silent) {
    var src = state.src;
    var pos = state.pos;
    if (src.charCodeAt(pos) !== 0x24) return false;
    // $$...$$ inside a sentence is display math, as in Pandoc.
    var display = src.charCodeAt(pos + 1) === 0x24;
    var open = display ? 2 : 1;
    var first = src.charAt(pos + open);
    if (!first || /\s/.test(first)) return false;
    var end = pos + open;
    for (;;) {
      end = src.indexOf(display ? "$$" : "$", end);
      if (end < 0) return false;
      if (escaped(src, end)) { end++; continue; }
      break;
    }
    var content = src.slice(pos + open, end);
    if (/\s/.test(src.charAt(end - 1))) return false;
    if (!display && /[0-9]/.test(src.charAt(end + 1))) return false;
    // A backtick inside means the closing $ belongs to a code span.
    if (content.indexOf("`") >= 0) return false;
    if (!silent) {
      var token = state.push("math_inline", "math", 0);
      token.content = content;
      token.meta = { display: display };
    }
    state.pos = end + open;
    return true;
  }

  // A display block ends at the first line ending in $$ and never crosses a
  // blank line (Pandoc's rule). A start that found no end marks the lines up
  // to that blank line, so later starts in them give up at once: an unclosed
  // $$ on every line stays linear.
  function mathBlock(state, startLine, endLine, silent) {
    var pos = state.bMarks[startLine] + state.tShift[startLine];
    var max = state.eMarks[startLine];
    if (state.sCount[startLine] - state.blkIndent >= 4) return false;
    if (state.src.slice(pos, pos + 2) !== "$$") return false;
    var miss = state.env.mathMiss;
    if (miss && startLine > miss[0] && startLine < miss[1]) return false;
    var rest = state.src.slice(pos + 2, max).trim();
    var content = null;
    var last = startLine;
    if (rest.length >= 2 && rest.slice(-2) === "$$") {
      content = rest.slice(0, -2);
      // $$a$$ and $$b$$ on one line is two formulas in a paragraph.
      for (var at = content.indexOf("$$"); at >= 0; at = content.indexOf("$$", at + 1)) {
        if (!escaped(content, at)) return false;
      }
    } else {
      // $$a$$ and $$b$$. followed by more text opens no block either.
      for (var open = rest.indexOf("$$"); open >= 0; open = rest.indexOf("$$", open + 1)) {
        if (!escaped(rest, open)) return false;
      }
      var lines = rest ? [rest] : [];
      for (var line = startLine + 1; line < endLine; line++) {
        if (state.isEmpty(line)) break;
        var text = state.src.slice(state.bMarks[line] + state.tShift[line], state.eMarks[line]);
        if (text.trim().slice(-2) === "$$") {
          lines.push(text.trim().slice(0, -2));
          content = lines.join("\n");
          last = line;
          break;
        }
        lines.push(text);
      }
    }
    if (content === null) {
      state.env.mathMiss = [startLine, line];
      return false;
    }
    if (silent) return true;
    var token = state.push("math_block", "math", 0);
    token.block = true;
    token.content = content;
    token.map = [startLine, last + 1];
    state.line = last + 1;
    return true;
  }

  var needs = { math: false, mermaid: false };

  function lineAttr(token) {
    return token.map && token.level === 0 ? ' data-line="' + token.map[0] + '"' : "";
  }

  function renderMath(tex, display) {
    needs.math = true;
    if (window.katex) {
      try {
        return window.katex.renderToString(tex, { displayMode: display, throwOnError: false });
      } catch (e) { /* fall through to the source */ }
    }
    var src = display ? "$$" + tex + "$$" : "$" + tex + "$";
    return display ? '<p class="math-src">' + esc(src) + "</p>" : esc(src);
  }

  function setup() {
    md = window.markdownit({ html: true, linkify: true });
    md.inline.ruler.before("escape", "math_inline", mathInline);
    md.block.ruler.before("fence", "math_block", mathBlock, { alt: ["paragraph", "reference", "blockquote", "list"] });
    md.renderer.rules.math_inline = function (tokens, idx) { return renderMath(tokens[idx].content, !!(tokens[idx].meta && tokens[idx].meta.display)); };
    md.renderer.rules.math_block = function (tokens, idx) { return renderMath(tokens[idx].content, true) + "\n"; };
    md.renderer.rules.fence = function (tokens, idx) {
      var token = tokens[idx];
      var lang = (token.info || "").trim().split(/\s+/)[0].toLowerCase();
      if (lang === "mermaid") {
        needs.mermaid = true;
        var svg = svgCache[token.content];
        return '<div class="mermaid-image-container"' + lineAttr(token) + ' data-mermaid="' + esc(token.content) + '">' +
          (svg || "<pre><code>" + esc(token.content) + "</code></pre>") + "</div>\n";
      }
      var hl = window.hljs;
      var body = lang && hl && hl.getLanguage(lang)
        ? hl.highlight(token.content, { language: lang, ignoreIllegals: true }).value
        : esc(token.content);
      return "<pre" + lineAttr(token) + '><code class="hljs' + (lang ? " language-" + esc(lang) : "") + '">' + body + "</code></pre>\n";
    };
    // Every top-level block carries the source line it starts on, which is
    // how the two panes scroll together (sync below).
    md.core.ruler.push("source_lines", function (state) {
      state.tokens.forEach(function (token) {
        if (token.map && token.level === 0 && token.nesting >= 0 && token.type !== "inline") token.attrSet("data-line", String(token.map[0]));
      });
    });
    // GitHub task list items: "[ ] " or "[x] " at the start of an item.
    md.core.ruler.after("inline", "task_lists", function (state) {
      var tokens = state.tokens;
      for (var i = 2; i < tokens.length; i++) {
        if (tokens[i].type !== "inline" || tokens[i - 1].type !== "paragraph_open" || tokens[i - 2].type !== "list_item_open") continue;
        var first = tokens[i].children[0];
        var m = first && first.type === "text" && /^\[([ xX])\](?=\s|$)/.exec(first.content);
        if (!m) continue;
        first.content = first.content.slice(3).replace(/^\s/, "");
        var box = new state.Token("html_inline", "", 0);
        box.content = '<input type="checkbox" disabled' + (m[1] === " " ? "" : " checked") + "> ";
        tokens[i].children.unshift(box);
      }
    });
  }

  // What MiaoYan's preview does to the HTML after parsing (common.js):
  // heading ids from their text, task lists marked, wide tables in a scroller.
  function finish(root) {
    var used = {};
    Array.prototype.forEach.call(root.querySelectorAll("h1, h2, h3, h4, h5, h6"), function (h) {
      var base = h.textContent.trim() || "section";
      var id = base;
      for (var n = 1; used[id]; n++) id = base + "-" + n;
      used[id] = true;
      h.id = id;
    });
    Array.prototype.forEach.call(root.querySelectorAll("input[type=checkbox]"), function (input) {
      var li = input.closest("li");
      if (li && li.parentElement) li.parentElement.classList.add("cb");
    });
    Array.prototype.forEach.call(root.querySelectorAll("ul.cb > li"), function (item) {
      var first = item.firstElementChild;
      var box = first && first.tagName === "P" ? first.firstElementChild : first;
      if (!box || box.tagName !== "INPUT") item.classList.add("cb-plain");
    });
    Array.prototype.forEach.call(root.querySelectorAll("table"), function (table) {
      if (table.parentElement && table.parentElement.classList.contains("table-scroll")) return;
      var wrapper = table.ownerDocument.createElement("div");
      wrapper.className = "table-scroll";
      table.parentNode.insertBefore(wrapper, table);
      wrapper.appendChild(table);
    });
    // Raw HTML may carry a refresh or a base that would move the preview away.
    Array.prototype.forEach.call(root.querySelectorAll("meta, base"), function (el) { el.remove(); });
    Array.prototype.forEach.call(root.querySelectorAll("a[href]"), function (a) {
      if (/^https?:/i.test(a.getAttribute("href"))) {
        a.target = "_blank";
        a.rel = "noopener";
      }
    });
    var h1 = root.querySelector("h1");
    root.ownerDocument.title = (h1 && h1.textContent.trim()) || fileName.replace(/\.[^.]+$/, "") || "Markdown";
  }

  // ---- Drawing -------------------------------------------------------------

  function shell(css, extra) {
    return "<!doctype html><html lang=\"" + (data.lang === "zh" ? "zh-CN" : "en") + "\"><head><meta charset=\"utf-8\">" +
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title></title>" + css +
      "<style>" + data.pageCss + "</style>" + (extra || "") + "</head><body><div class=\"markdown-body heti\" id=\"write\">";
  }

  // Inside the preview a heading link scrolls to its heading and a web link
  // opens a tab; a relative link (another note) has nowhere to go and does
  // nothing, rather than loading the site into the frame.
  var XLINK = "http://www.w3.org/1999/xlink";

  function onPreviewClick(e) {
    var a = e.target.closest && e.target.closest("a, area");
    if (!a) return;
    var href = a.getAttribute("href") || a.getAttributeNS(XLINK, "href");
    if (!href) return;
    if (/^(https?:|mailto:)/i.test(href) && a.tagName.toLowerCase() === "a" && a.namespaceURI !== "http://www.w3.org/2000/svg") return;
    e.preventDefault();
    if (href.charAt(0) !== "#") return;
    var id = href.slice(1);
    try { id = decodeURIComponent(id); } catch (err) { /* keep it as written */ }
    var target = a.ownerDocument.getElementById(id);
    if (target) target.scrollIntoView({ block: "start" });
  }

  var frameDoc = shell(data.css.concat([data.katexCss]).map(function (href) {
    return '<link rel="stylesheet" href="' + href + '">';
  }).join("")) + "</div></body></html>";

  // Anything that still moves the frame (a form, a link kind the click
  // handler does not know) brings the preview straight back.
  var frameReady = new Promise(function (resolve) {
    frame.addEventListener("load", function () {
      var doc = frame.contentDocument;
      write = doc && doc.location.href === "about:srcdoc" ? doc.getElementById("write") : null;
      if (!write) {
        frame.srcdoc = frameDoc;
        return;
      }
      doc.addEventListener("click", onPreviewClick);
      frame.contentWindow.addEventListener("scroll", onPreviewScroll);
      doc.addEventListener("load", stale, true);
      doc.addEventListener("submit", function (e) { e.preventDefault(); });
      doc.addEventListener("dragover", onDragOver);
      doc.addEventListener("drop", onDrop);
      doc.addEventListener("dragleave", function (e) { if (!e.relatedTarget) tool.classList.remove("is-drop"); });
      doc.addEventListener("dragend", function () { tool.classList.remove("is-drop"); });
      resolve();
      if (md) render();
    });
    frame.srcdoc = frameDoc;
  });

  function render() {
    if (!md || !write) return;
    var mine = ++seq;
    needs.math = false;
    needs.mermaid = false;
    write.innerHTML = md.render(code.value);
    finish(write);
    anchors = null;
    countWords();
    // Saved once everything has drawn, math and diagrams included (the render
    // after KaTeX arrives, or the diagrams' end, saves), so text that hangs
    // the page never comes back on the next visit.
    if (needs.math && !window.katex && !katexWait) {
      katexFailed = false;
      katexWait = load(data.katex).then(render, function () {
        katexWait = null;
        katexFailed = true;
        if (edited && !diagramsPending) store();
      });
    }
    diagramsPending = needs.mermaid;
    if (edited && !mathPending() && !diagramsPending) store();
    if (needs.mermaid) drawDiagrams(mine);
  }

  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(render, code.value.length > 1e5 ? 500 : 150);
  }

  // Diagrams are drawn on this page, where Mermaid can measure text, and the
  // SVG goes into the preview; each one is kept so typing elsewhere does not
  // redraw it.
  function loadMermaid() {
    if (!mermaidReady) {
      mermaidReady = load(data.mermaid).then(function () {
        var base = window.ThemeColors.getMermaidConfig(false);
        window.mermaid.initialize(Object.assign({}, base, data.mermaidConfig, { startOnLoad: false }));
      });
      mermaidReady.catch(function () { mermaidReady = null; });
    }
    return mermaidReady;
  }

  var diagramId = 0;

  function drawDiagrams(mine) {
    loadMermaid().then(function () {
      var boxes = Array.prototype.slice.call(write.querySelectorAll("[data-mermaid]"));
      return boxes.reduce(function (chain, box) {
        return chain.then(function () {
          if (mine !== seq) return;
          var source = box.getAttribute("data-mermaid");
          if (svgCache[source]) { box.innerHTML = svgCache[source]; return; }
          var id = "viewer-mermaid-" + (++diagramId);
          return window.mermaid.render(id, source).then(function (out) {
            svgCache[source] = out.svg;
            if (mine === seq && box.isConnected) box.innerHTML = out.svg;
          }, function () {
            var stray = document.getElementById("d" + id);
            if (stray) stray.remove();
          });
        });
      }, Promise.resolve());
    }).catch(function () { /* said by load */ }).then(function () {
      if (mine !== seq) return;
      anchors = null;
      diagramsPending = false;
      if (edited && !mathPending()) store();
    });
  }

  // ---- Editing ---------------------------------------------------------------

  function store() {
    // A text too big to store must not leave an older draft to come back.
    try { localStorage.setItem(DRAFT_KEY, code.value); } catch (e) {
      try { localStorage.removeItem(DRAFT_KEY); } catch (e2) { /* storage blocked */ }
    }
  }

  code.addEventListener("input", function () {
    if (!edited) { edited = true; track("tool_render", { tool: TOOL }); }
    say("");
    schedule();
  });

  window.MiaoYanEditor.attach(code, { save: function () { saveMarkdown(); } });

  // ---- Scrolling together --------------------------------------------------------
  // Each top-level block in the preview carries its source line; that line's
  // top in the editor (wrapping included, from the highlighter) and the
  // block's top in the preview make a pair, and a scroll in either pane moves
  // the other along straight lines between neighbouring pairs, so a long
  // table or a tall diagram never pulls the panes apart, as doocs/md's
  // block-mapped sync does. A scroll this code made is not sent back.
  var anchors = null;
  var echo = { code: -1, preview: -1 };

  function scroller() {
    var doc = frame.contentDocument;
    return doc && doc.scrollingElement;
  }

  function buildAnchors() {
    var el = scroller();
    var tops = window.MiaoYanHighlight && window.MiaoYanHighlight.lineTops(code);
    if (!el || !write || !tops || !code.offsetParent) return null;
    var codeMax = code.scrollHeight - code.clientHeight;
    var viewMax = el.scrollHeight - el.clientHeight;
    var base = write.getBoundingClientRect().top;
    var out = [[0, 0]];
    Array.prototype.forEach.call(write.querySelectorAll("[data-line]"), function (block) {
      var a = tops[+block.getAttribute("data-line")];
      var b = block.getBoundingClientRect().top - base;
      var last = out[out.length - 1];
      // Blocks past either pane's last scroll position fall to the end pair,
      // so the bottom of one pane always meets the bottom of the other.
      if (a === undefined || a >= codeMax || b >= viewMax) return;
      if (a > last[0] && b > last[1]) out.push([a, b]);
    });
    var end = out[out.length - 1];
    if (codeMax > end[0] && viewMax > end[1]) out.push([codeMax, viewMax]);
    return out;
  }

  function along(y, from, to) {
    var a = anchors;
    if (a.length < 2) return 0;
    for (var i = 1; i < a.length; i++) {
      if (y <= a[i][from] || i === a.length - 1) {
        var p = a[i - 1];
        var q = a[i];
        var span = q[from] - p[from];
        var t = span > 0 ? Math.min(1, Math.max(0, (y - p[from]) / span)) : 0;
        return p[to] + t * (q[to] - p[to]);
      }
    }
    return 0;
  }

  code.addEventListener("scroll", function () {
    if (echo.code >= 0 && Math.abs(code.scrollTop - echo.code) < 2) { echo.code = -1; return; }
    echo.code = -1;
    var el = scroller();
    if (!el || !(anchors = anchors || buildAnchors())) return;
    var y = Math.round(along(code.scrollTop, 0, 1));
    if (Math.abs(el.scrollTop - y) < 1) return;
    echo.preview = y;
    el.scrollTop = y;
    seenTop = el.scrollTop;
  });

  function onPreviewScroll() {
    var el = scroller();
    if (!el) return;
    seenTop = el.scrollTop;
    if (echo.preview >= 0 && Math.abs(el.scrollTop - echo.preview) < 2) { echo.preview = -1; return; }
    echo.preview = -1;
    if (!(anchors = anchors || buildAnchors())) return;
    var y = Math.round(along(el.scrollTop, 1, 0));
    if (Math.abs(code.scrollTop - y) < 1) return;
    echo.code = y;
    code.scrollTop = y;
  }

  // Safari runs no listener inside a frame whose sandbox has no allow-scripts,
  // the frame's scroll listener included, so while the pointer is over the
  // preview, the preview has focus, or for a second after the pointer leaves
  // (a trackpad's glide), this page reads the preview's scroll position each
  // frame and hands a change to onPreviewScroll. In Chrome the listener has
  // already seen it and the two agree.
  var seenTop = 0;
  var watching = 0;
  var hovering = false;
  var glideUntil = 0;

  function watch() {
    var el = scroller();
    if (el && el.scrollTop !== seenTop) onPreviewScroll();
    watching = hovering || document.activeElement === frame || Date.now() < glideUntil ? requestAnimationFrame(watch) : 0;
  }
  function startWatch() { if (!watching) watching = requestAnimationFrame(watch); }
  frame.addEventListener("pointerenter", function () { hovering = true; startWatch(); });
  frame.addEventListener("pointerleave", function () { hovering = false; glideUntil = Date.now() + 1000; });
  window.addEventListener("blur", function () { setTimeout(function () { if (document.activeElement === frame) startWatch(); }); });

  function stale() { anchors = null; }
  window.addEventListener("resize", stale);

  onlyButton.addEventListener("click", function () {
    var on = onlyButton.getAttribute("aria-pressed") !== "true";
    onlyButton.setAttribute("aria-pressed", String(on));
    grid.classList.toggle("is-preview-only", on);
    stale();
  });

  // The preview at a phone's width, where a WeChat article is read.
  phoneButton.addEventListener("click", function () {
    var on = phoneButton.getAttribute("aria-pressed") !== "true";
    phoneButton.setAttribute("aria-pressed", String(on));
    frameBox.classList.toggle("is-phone", on);
    stale();
  });

  // Words counted as MiaoYan counts them (String+.swift noteWordCount): each
  // CJK character is one, each run of letters and digits is one, front matter
  // left out.
  var CJK = "\\u3040-\\u30FF\\u3400-\\u4DBF\\u4E00-\\u9FFF\\uAC00-\\uD7AF\\uF900-\\uFAFF\\u{20000}-\\u{2FA1F}";
  var WORDS = new RegExp("[" + CJK + "]|(?:(?![" + CJK + "])[\\p{L}\\p{M}\\p{N}])(?:(?![" + CJK + "])[\\p{L}\\p{M}\\p{N}'\\u2019])*", "gu");
  var number = new Intl.NumberFormat(data.lang === "zh" ? "zh-CN" : "en-US");

  function countWords() {
    var text = code.value.replace(/^---\n[\s\S]*?\n---(?:\n|$)/, "");
    var n = (text.match(WORDS) || []).length;
    countEl.textContent = fill(n === 1 ? S.word : S.words, { n: number.format(n) });
  }

  // ---- Files -------------------------------------------------------------------

  var TEXT_FILES = { md: 1, markdown: 1, mdown: 1, mkd: 1, txt: 1 };

  function decode(buffer) {
    var bytes = new Uint8Array(buffer);
    try { return new TextDecoder("utf-8", { fatal: true }).decode(bytes); } catch (err) { /* not UTF-8 */ }
    try { return new TextDecoder("gb18030").decode(bytes); } catch (err) { return new TextDecoder("utf-8").decode(bytes); }
  }

  var opening = 0;

  function openFile(file) {
    var ext = (file.name.split(".").pop() || "").toLowerCase();
    var mine = ++opening;
    if (!(ext in TEXT_FILES) || file.size > MAX_BYTES || !file.arrayBuffer) { say(S.fileType); return; }
    file.arrayBuffer().then(function (buffer) {
      if (mine !== opening) return;
      code.value = decode(buffer).replace(/^﻿/, "").replace(/\r\n?/g, "\n");
      fileName = file.name;
      edited = true;
      code.scrollTop = 0;
      render();
      var doc = frame.contentDocument;
      if (doc && doc.scrollingElement) doc.scrollingElement.scrollTop = 0;
      say(fill(S.opened, { name: file.name }));
      track("tool_import", { tool: TOOL, source: "file" });
    }, function () { if (mine === opening) say(S.fileType); });
  }

  fileInput.addEventListener("change", function () {
    if (fileInput.files[0]) openFile(fileInput.files[0]);
    fileInput.value = "";
  });

  function onDragOver(e) {
    if (e.dataTransfer && Array.prototype.indexOf.call(e.dataTransfer.types, "Files") >= 0) {
      e.preventDefault();
      tool.classList.add("is-drop");
    }
  }

  function onDrop(e) {
    var file = e.dataTransfer && e.dataTransfer.files[0];
    tool.classList.remove("is-drop");
    if (!file) return;
    e.preventDefault();
    openFile(file);
  }

  tool.addEventListener("dragover", onDragOver);
  tool.addEventListener("dragleave", function (e) {
    if (!tool.contains(e.relatedTarget)) tool.classList.remove("is-drop");
  });
  tool.addEventListener("drop", onDrop);

  // ---- Export ------------------------------------------------------------------

  function download(blob, name) {
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  function baseName() {
    var title = frame.contentDocument ? frame.contentDocument.title : "";
    return (title || "note").replace(/[\\/:*?"<>|]+/g, " ").trim().slice(0, 80) || "note";
  }

  // A page that stands on its own: the stylesheets inline, KaTeX's from the
  // site only when there is math, since its fonts live there.
  var cssText = null;

  function exportHtml() {
    return sheets().then(function (sheets) {
      var math = write.querySelector(".katex") ? '<link rel="stylesheet" href="' + data.site + data.katexCss + '">' : "";
      var title = "<title>" + esc(frame.contentDocument.title) + "</title>";
      // The preview runs none of the note's script, and the file does not either.
      var csp = '<meta http-equiv="Content-Security-Policy" content="script-src \'none\'">';
      var html = shell(csp + "<style>" + sheets.join("\n") + "</style>" + math).replace("<title></title>", title) +
        write.innerHTML.replace(/ data-line="\d+"/g, "") + "</div></body></html>\n";
      download(new Blob([html], { type: "text/html" }), baseName() + ".html");
      track("tool_export", { tool: TOOL, format: "html" });
    });
  }

  function exportPdf() {
    var win = frame.contentWindow;
    win.focus();
    win.print();
    track("tool_export", { tool: TOOL, format: "pdf" });
    return Promise.resolve();
  }

  function saveMarkdown() {
    var name = /\.(md|markdown|mdown|mkd|txt)$/i.test(fileName) ? fileName : baseName() + ".md";
    download(new Blob([code.value], { type: "text/markdown;charset=utf-8" }), name);
    track("tool_export", { tool: TOOL, format: "md" });
    return Promise.resolve();
  }

  // ---- Copy with its styles -----------------------------------------------------
  // Editors that take pasted HTML (WeChat's article editor, a mail, a CMS)
  // drop <style> and class, so the copy carries each element's computed style
  // inline, read from a copy of the preview laid out offscreen in the same
  // frame. What those editors cannot hold becomes what they can, after
  // doocs/md's WeChat copy (services/export/clipboard-dom.ts): MiaoYan's quote
  // bar, an absolutely placed ::before, becomes a left border on a <section>
  // (WeChat paints its own bar on <blockquote>); task boxes become ☐ and ☑;
  // code keeps its spaces and line breaks as &nbsp; and <br>; a nested list
  // follows its item; diagrams become PNG images; formulas stay as their TeX.
  // On the Chinese page, written for WeChat articles, where a link to another
  // site does not open, links become numbered references at the end.
  // For Word (mode "word") the same styled copy goes to docx's HTML reader,
  // which holds what a paste cannot: lists stay nested, task boxes stay
  // checkboxes, code keeps its own spaces, links stay links, and formulas
  // become Word equations from KaTeX's MathML.
  var SVG_NS = "http://www.w3.org/2000/svg";
  var INHERITED = ["color", "font-family", "font-size", "font-style", "font-weight", "line-height", "letter-spacing", "text-align", "text-indent", "word-break", "overflow-wrap", "white-space"];
  var SIDES = ["top", "right", "bottom", "left"];
  var BLOCK = { P: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1, UL: 1, OL: 1, LI: 1, BLOCKQUOTE: 1, PRE: 1, TABLE: 1, HR: 1, DIV: 1, SECTION: 1, FIGURE: 1, IMG: 1 };
  var NONE = { "0px": 1, "none": 1, "normal": 1, "auto": 1, "rgba(0, 0, 0, 0)": 1, "transparent": 1, "baseline": 1, "visible": 1, "separate": 1 };

  function styleOf(win, el, parent) {
    var cs = win.getComputedStyle(el);
    var ps = parent ? win.getComputedStyle(parent) : null;
    var out = [];
    function put(k, v) { out.push(k + ": " + v); }
    INHERITED.forEach(function (k) {
      var v = cs.getPropertyValue(k);
      if (!ps || ps.getPropertyValue(k) !== v) put(k, v);
    });
    var block = BLOCK[el.tagName];
    if (block || cs.display !== "inline") put("display", cs.display);
    ["margin", "padding"].forEach(function (box) {
      SIDES.forEach(function (s) {
        var v = cs.getPropertyValue(box + "-" + s);
        if (block || !NONE[v]) put(box + "-" + s, v);
      });
    });
    SIDES.forEach(function (s) {
      var style = cs.getPropertyValue("border-" + s + "-style");
      if (style !== "none" && style !== "hidden") {
        put("border-" + s, cs.getPropertyValue("border-" + s + "-width") + " " + style + " " + cs.getPropertyValue("border-" + s + "-color"));
      }
    });
    ["border-radius", "background-color", "vertical-align", "border-collapse", "overflow-x", "max-width"].forEach(function (k) {
      var v = cs.getPropertyValue(k);
      if (!NONE[v]) put(k, v);
    });
    if (cs.textDecorationLine !== "none") put("text-decoration", cs.textDecorationLine + " " + cs.textDecorationColor);
    if (el.tagName === "UL" || el.tagName === "OL" || el.tagName === "LI") put("list-style-type", cs.listStyleType);
    if (el.tagName === "IMG") { put("max-width", "100%"); put("height", "auto"); }
    return out.join("; ");
  }

  // A diagram as a PNG at twice its size, for editors that drop SVG.
  function diagramImage(svg) {
    var r = svg.getBoundingClientRect();
    var w = Math.round(r.width);
    var h = Math.round(r.height);
    if (!w || !h) return Promise.resolve(null);
    var copy = svg.cloneNode(true);
    copy.setAttribute("width", w);
    copy.setAttribute("height", h);
    copy.style.maxWidth = "none";
    var xml = new XMLSerializer().serializeToString(copy);
    return new Promise(function (resolve) {
      var img = new Image();
      img.onload = function () {
        try {
          var canvas = document.createElement("canvas");
          canvas.width = w * 2;
          canvas.height = h * 2;
          var g = canvas.getContext("2d");
          g.scale(2, 2);
          g.drawImage(img, 0, 0, w, h);
          resolve({ src: canvas.toDataURL("image/png"), width: w });
        } catch (e) { resolve(null); }
      };
      img.onerror = function () { resolve(null); };
      img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(xml);
    });
  }

  function each(root, selector, fn) {
    Array.prototype.slice.call(root.querySelectorAll(selector)).forEach(fn);
  }

  function retag(el, tag) {
    var next = el.ownerDocument.createElement(tag);
    Array.prototype.forEach.call(el.attributes, function (a) { next.setAttribute(a.name, a.value); });
    while (el.firstChild) next.appendChild(el.firstChild);
    el.parentNode.replaceChild(next, el);
    return next;
  }

  function styledCopy(mode) {
    var word = mode === "word";
    var doc = frame.contentDocument;
    var win = frame.contentWindow;
    var box = write.cloneNode(true);
    var notes = { links: 0, math: false };
    write.removeAttribute("id");
    // For Word the copy is laid out at the page's text width, so tables and
    // diagrams are measured to fit between its margins.
    box.style.cssText = "position: absolute; left: -100000px; top: 0; width: " + (word ? WORD_PAGE.text + "px; padding: 0; margin: 0; max-width: none" : write.clientWidth + "px");
    doc.body.appendChild(box);
    var mounted = box;

    var diagrams = Array.prototype.slice.call(box.querySelectorAll(".mermaid-image-container svg"));
    return Promise.all(diagrams.map(diagramImage)).then(function (images) {
      images.forEach(function (image, i) {
        if (!image) return;
        var img = doc.createElement("img");
        img.src = image.src;
        img.alt = "";
        img.setAttribute("data-width", image.width);
        diagrams[i].parentNode.replaceChild(img, diagrams[i]);
      });
      each(box, ".katex-display, .katex", function (k) {
        if (!k.isConnected) return;
        if (word) {
          var math = k.querySelector(".katex-mathml math");
          if (!math) return;
          var eq = math.cloneNode(true);
          each(eq, "annotation", function (a) { a.remove(); });
          if (k.classList.contains("katex-display")) {
            eq.setAttribute("display", "block");
            var line = doc.createElement("p");
            line.style.textAlign = "center";
            line.appendChild(eq);
            var host = k.parentNode;
            // A formula alone in its block takes the block's place.
            if (host !== box && host.textContent.trim() === k.textContent.trim() && !host.querySelector("img")) host.parentNode.replaceChild(line, host);
            else host.replaceChild(line, k);
          } else {
            k.parentNode.replaceChild(eq, k);
          }
          return;
        }
        var tex = k.querySelector('annotation[encoding="application/x-tex"]');
        if (!tex) return;
        var display = k.classList.contains("katex-display");
        var c = doc.createElement("code");
        c.textContent = display ? "$$" + tex.textContent + "$$" : "$" + tex.textContent + "$";
        notes.math = true;
        if (display) {
          var p = doc.createElement("p");
          p.appendChild(c);
          k.parentNode.replaceChild(p, k);
        } else {
          k.parentNode.replaceChild(c, k);
        }
      });
      if (!word) each(box, "input[type=checkbox]", function (input) {
        var mark = doc.createElement("span");
        mark.textContent = input.checked ? "☑ " : "☐ ";
        input.parentNode.replaceChild(mark, input);
      });
      var refs = [];
      if (data.wechat && !word) {
        each(box, "a[href]", function (a) {
          var href = a.getAttribute("href");
          if (!/^https?:/i.test(href) || /^https?:\/\/mp\.weixin\.qq\.com\//i.test(href)) return;
          var text = a.textContent.trim();
          var span = doc.createElement("span");
          while (a.firstChild) span.appendChild(a.firstChild);
          a.parentNode.replaceChild(span, a);
          if (text === href) return;
          refs.push([text, href]);
          var sup = doc.createElement("sup");
          sup.textContent = "[" + refs.length + "]";
          span.parentNode.insertBefore(sup, span.nextSibling);
        });
        if (refs.length) {
          var title = doc.createElement("h4");
          title.textContent = S.references;
          box.appendChild(title);
          refs.forEach(function (ref, i) {
            var p = doc.createElement("p");
            p.className = "copy-ref";
            p.textContent = "[" + (i + 1) + "] " + ref[0] + ": " + ref[1];
            box.appendChild(p);
          });
        }
        notes.links = refs.length;
      }

      // Read every style before any element changes.
      var all = [box].concat(Array.prototype.slice.call(box.querySelectorAll("*"))).filter(function (el) {
        return el.namespaceURI !== SVG_NS && el.namespaceURI !== "http://www.w3.org/1998/Math/MathML";
      });
      var styles = all.map(function (el) { return styleOf(win, el, el === box ? null : el.parentElement); });
      var bars = Array.prototype.slice.call(box.querySelectorAll("blockquote")).map(function (q) {
        var bar = win.getComputedStyle(q, "::before");
        return [q, bar.width, bar.backgroundColor, parseFloat(win.getComputedStyle(q).paddingLeft) || 0];
      });
      var secondary = win.getComputedStyle(box).getPropertyValue("--text-secondary").trim();
      all.forEach(function (el, i) { el.setAttribute("style", styles[i]); });
      // Word takes one font name per run, the first it knows of a list, and
      // the system's own fonts have names Word does not: the text's fonts go
      // in the document's styles instead (WORD_FONT), code keeps one name.
      if (word) all.forEach(function (el) {
        if (el.closest("pre") || /^(CODE|KBD|SAMP)$/.test(el.tagName)) el.style.fontFamily = WORD_CODE_FONT;
        else el.style.removeProperty("font-family");
      });

      bars.forEach(function (b) {
        var width = parseFloat(b[1]) || 0;
        if (width && b[2] !== "rgba(0, 0, 0, 0)") {
          b[0].style.borderLeft = width + "px solid " + b[2];
          b[0].style.paddingLeft = Math.max(0, b[3] - width) + "px";
        }
        retag(b[0], "section");
      });
      // The PNG is drawn at twice the diagram's size; it shows at its size.
      each(box, "img[data-width]", function (img) {
        img.style.width = img.getAttribute("data-width") + "px";
        img.style.margin = "0 auto";
        img.removeAttribute("data-width");
      });
      each(box, ".copy-ref", function (p) {
        p.style.fontSize = "14px";
        p.style.wordBreak = "break-all";
        if (secondary) p.style.color = secondary;
      });
      if (!word) each(box, "pre", function (pre) {
        var walker = doc.createTreeWalker(pre, NodeFilter.SHOW_TEXT);
        var texts = [];
        while (walker.nextNode()) texts.push(walker.currentNode);
        texts.forEach(function (node) {
          var parts = node.data.replace(/\t/g, "    ").split("\n");
          var frag = doc.createDocumentFragment();
          parts.forEach(function (part, i) {
            if (i) frag.appendChild(doc.createElement("br"));
            if (part) frag.appendChild(doc.createTextNode(part.replace(/ /g, "\u00a0")));
          });
          node.parentNode.replaceChild(frag, node);
        });
        // A trailing newline would leave an empty last line.
        var last = pre.querySelector("code") || pre;
        while (last.lastChild && last.lastChild.nodeName === "BR") last.removeChild(last.lastChild);
        pre.style.overflowX = "auto";
        pre.style.whiteSpace = "nowrap";
        pre.setAttribute("data-ignore-width", "");
      });
      each(box, "table, .table-scroll", function (el) { el.setAttribute("data-ignore-width", ""); });
      if (!word) each(box, "li > ul, li > ol", function (list) { list.parentNode.parentNode.insertBefore(list, list.parentNode.nextSibling); });
      each(box, 'a[href^="#"]', function (a) { a.removeAttribute("href"); });
      [box].concat(Array.prototype.slice.call(box.querySelectorAll("[class], [id], [data-line], [data-mermaid], [target], [rel]"))).forEach(function (el) {
        ["class", "id", "data-line", "data-mermaid", "target", "rel"].forEach(function (k) { el.removeAttribute(k); });
      });
      box.style.position = "";
      box.style.left = "";
      box.style.top = "";
      box.style.width = "";
      var root = mounted = retag(box, "section");
      return { html: root.outerHTML, text: root.innerText, notes: notes };
    }).then(function (copy) {
      mounted.remove();
      write.id = "write";
      return copy;
    }, function (err) {
      mounted.remove();
      write.id = "write";
      throw err;
    });
  }

  function copyFormatted() {
    return styledCopy().then(function (copy) {
      var html = copy.html;
      var text = copy.text;
      if (window.ClipboardItem && navigator.clipboard && navigator.clipboard.write && window.isSecureContext) {
        return navigator.clipboard.write([new ClipboardItem({
          "text/html": new Blob([html], { type: "text/html" }),
          "text/plain": new Blob([text], { type: "text/plain" })
        })]).then(function () { return copy.notes; });
      }
      var onCopy = function (e) {
        e.clipboardData.setData("text/html", html);
        e.clipboardData.setData("text/plain", text);
        e.preventDefault();
      };
      document.addEventListener("copy", onCopy);
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (err) { ok = false; }
      document.removeEventListener("copy", onCopy);
      if (!ok) throw new Error("copy");
      return copy.notes;
    }).then(function (notes) {
      var said = notes.links ? fill(S.copiedLinks, { n: notes.links }) : S.copied;
      say(notes.math ? said + S.copiedMath : said);
      track("tool_copy", { tool: TOOL, kind: data.wechat ? "wechat" : "formatted" });
    });
  }

  // ---- Word ------------------------------------------------------------------------
  // The styled copy as a .docx through docx's HTML reader, loaded on the first
  // save. Pictures from other sites are fetched for their bytes; one a site
  // will not hand over (no CORS) or a relative path stays out, and the status
  // line says how many.
  function imageBytes(html) {
    var doc = new DOMParser().parseFromString(html, "text/html");
    var srcs = [];
    each(doc, "img[src]", function (img) {
      var src = img.getAttribute("src");
      if (!/^data:/i.test(src) && srcs.indexOf(src) < 0) srcs.push(src);
    });
    var map = {};
    var missed = 0;
    return Promise.all(srcs.map(function (src) {
      if (!/^https?:/i.test(src)) { missed++; return null; }
      return fetch(src, { mode: "cors", credentials: "omit", referrerPolicy: "no-referrer" }).then(function (r) {
        if (!r.ok) throw new Error("image");
        return r.arrayBuffer();
      }).then(function (buffer) { map[src] = new Uint8Array(buffer); }, function () { missed++; });
    })).then(function () { return { map: map, missed: missed }; });
  }

  // MiaoYan's preview faces; Word on a machine without them substitutes its own.
  var WORD_FONT = { ascii: "Helvetica Neue", hAnsi: "Helvetica Neue", cs: "Helvetica Neue", eastAsia: "PingFang SC" };
  var WORD_CODE_FONT = "Menlo";
  // A4 for the Chinese page and US Letter for the English one, one-inch
  // margins; text is the width between them in CSS pixels (1in = 96px), sizes
  // in twentieths of a point.
  var WORD_PAGE = data.lang === "zh" ? { width: 11906, height: 16838, text: 601 } : { width: 12240, height: 15840, text: 624 };

  function exportDocx() {
    var title = frame.contentDocument ? frame.contentDocument.title : "";
    return Promise.all([load(data.docx), styledCopy("word")]).then(function (r) {
      var copy = r[1];
      return imageBytes(copy.html).then(function (images) {
        var d = window.docx;
        var children = window.docxHtml.htmlToContent(copy.html, { images: images.map, onWarning: function () {} });
        var styles = { document: { run: { font: WORD_FONT } } };
        for (var level = 1; level <= 6; level++) styles["heading" + level] = { run: { font: WORD_FONT } };
        styles.title = { run: { font: WORD_FONT } };
        var doc = new d.Document({
          title: title || undefined,
          creator: "MiaoYan",
          styles: { default: styles },
          sections: [{
            properties: { page: { size: { width: WORD_PAGE.width, height: WORD_PAGE.height }, margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } } },
            children: children,
          }],
        });
        return d.Packer.toBlob(doc).then(function (blob) {
          download(blob, baseName() + ".docx");
          say(images.missed ? fill(images.missed === 1 ? S.wordImage : S.wordImages, { n: images.missed }) : "");
          track("tool_export", { tool: TOOL, format: "docx" });
        });
      });
    });
  }

  // ---- Long image ----------------------------------------------------------------
  // The preview as one PNG, as MiaoYan's Export > Image snapshots its preview
  // at twice its size with the note's title on top when the text has no
  // heading of its own. A page cannot photograph itself, so the preview is
  // laid out again in a hidden frame with every stylesheet inline, written
  // into an SVG foreignObject and drawn onto a canvas: as a data URL, since a
  // blob URL taints the canvas in both Chrome and Safari. Nothing inside such
  // an image may load from outside, so KaTeX's fonts go in as data URLs and
  // so do the note's web pictures, fetched as Word does; one a site will not
  // hand over stays out and the status line says so. It is drawn at the width
  // shown, a phone's 375px at three times (1125px) or the export's 760px
  // column at twice, smaller only when a canvas that size would not fit the
  // browser's limits.
  var IMAGE = { phone: { width: 375, pad: "24px 20px 28px", scale: 3 }, desk: { width: 840, pad: "40px 40px 44px", scale: 2 } };
  var IOS = /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.maxTouchPoints > 1 && /Macintosh/.test(navigator.userAgent));
  var MAX_SIDE = 32767;
  var MAX_AREA = IOS ? 16777216 : 268435456;
  var katexInline = null;
  var imaging = false;

  function sheets() {
    if (!cssText) {
      cssText = Promise.all(data.css.map(function (href) {
        return fetch(href).then(function (r) { if (!r.ok) throw new Error("css"); return r.text(); });
      }));
      cssText.catch(function () { cssText = null; });
    }
    return cssText;
  }

  function asDataUrl(blob) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onload = function () { resolve(reader.result); };
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  }

  function fetchData(url) {
    return fetch(url, { mode: "cors", credentials: "omit", referrerPolicy: "no-referrer" }).then(function (r) {
      if (!r.ok) throw new Error("fetch");
      return r.blob();
    }).then(asDataUrl);
  }

  // KaTeX's stylesheet with its woff2 fonts written in and the older formats left out.
  function katexCss() {
    if (!katexInline) {
      var base = new URL(data.katexCss, location.href);
      katexInline = fetch(base).then(function (r) { if (!r.ok) throw new Error("css"); return r.text(); }).then(function (css) {
        css = css.replace(/,\s*url\([^)]*\.(woff|ttf)\)\s*format\("[^"]*"\)/g, "");
        var files = [];
        css.replace(/url\(([^)]+\.woff2)\)/g, function (m, f) { if (files.indexOf(f) < 0) files.push(f); return m; });
        return Promise.all(files.map(function (f) { return fetchData(new URL(f, base).href); })).then(function (urls) {
          files.forEach(function (f, i) { css = css.split("url(" + f + ")").join("url(" + urls[i] + ")"); });
          return css;
        });
      });
      katexInline.catch(function () { katexInline = null; });
    }
    return katexInline;
  }

  function longImage() {
    if (imaging) return Promise.reject(new Error("busy"));
    imaging = true;
    var size = frameBox.classList.contains("is-phone") ? IMAGE.phone : IMAGE.desk;
    var win = frame.contentWindow;
    var dark = !!(win && win.matchMedia && win.matchMedia("(prefers-color-scheme: dark)").matches);
    var box = write.cloneNode(true);
    var doc = box.ownerDocument;
    // The title on top, as the app adds it: the opened file's name, when the
    // text does not start with a heading of its own.
    var first = box.firstElementChild;
    var named = fileName.replace(/\.[^.]+$/, "").trim();
    if (named && (!first || first.tagName !== "H1")) {
      var h1 = doc.createElement("h1");
      h1.textContent = named;
      h1.style.cssText = "font-size: 2em; font-weight: bold; margin-bottom: 24px; padding-bottom: 12px; border-bottom: 1px solid #eee; display: block;";
      box.insertBefore(h1, first);
    }
    each(box, "[data-line]", function (el) { el.removeAttribute("data-line"); });
    var missed = 0;
    var pictures = Promise.all(Array.prototype.map.call(box.querySelectorAll("img"), function (img) {
      // Resolved as the preview resolves it, so a path on this site comes along.
      var src = img.getAttribute("src") ? img.src : "";
      img.removeAttribute("srcset");
      img.removeAttribute("loading");
      if (/^data:image\//i.test(src)) return null;
      if (!/^https?:/i.test(src)) { missed++; img.remove(); return null; }
      return fetchData(src).then(function (url) { img.setAttribute("src", url); }, function () { missed++; img.remove(); });
    }));
    var math = !!box.querySelector(".katex");
    var measure = null;
    var done = function () { imaging = false; if (measure) measure.remove(); };
    return Promise.all([sheets(), math ? katexCss() : "", pictures]).then(function (r) {
      var css = (r[0].join("\n") + "\n" + r[1] + "\n" + data.pageCss +
        " html { padding: " + size.pad + "; overflow: visible; } body { overflow: visible; }" +
        // The page ends where the text does, the bottom margin matching the top.
        " #write { margin-bottom: 0; padding-bottom: 0; } #write > :last-child { margin-bottom: 0 !important; }")
        // In an SVG image :root is the <svg>, so the preview's variables go on <html>.
        .replace(/:root/g, "html")
        // The image keeps the scheme the preview shows.
        .replace(/\(prefers-color-scheme:\s*dark\)/g, dark ? "(min-width: 0px)" : "(max-width: 0px)")
        .replace(/<\/style/gi, "<\\/style");
      measure = document.createElement("iframe");
      measure.setAttribute("sandbox", "allow-same-origin");
      measure.setAttribute("aria-hidden", "true");
      measure.tabIndex = -1;
      measure.style.cssText = "position: fixed; left: 0; top: 0; width: " + size.width + "px; height: 100px; border: 0; opacity: 0; pointer-events: none; z-index: -1;";
      return new Promise(function (resolve) {
        measure.addEventListener("load", resolve, { once: true });
        measure.srcdoc = "<!doctype html><html lang=\"" + (data.lang === "zh" ? "zh-CN" : "en") + "\"><head><meta charset=\"utf-8\"><style>" + css +
          "</style></head><body><div class=\"markdown-body heti\" id=\"write\"></div></body></html>";
        document.body.appendChild(measure);
      }).then(function () {
        var mdoc = measure.contentDocument;
        var target = mdoc.getElementById("write");
        target.innerHTML = box.innerHTML;
        var waits = Array.prototype.map.call(mdoc.images, function (img) { return img.decode ? img.decode().catch(function () {}) : null; });
        if (mdoc.fonts && mdoc.fonts.ready) waits.push(mdoc.fonts.ready);
        return Promise.all(waits).then(function () { return mdoc; });
      });
    }).then(function (mdoc) {
      var root = mdoc.documentElement;
      var width = size.width;
      var height = Math.ceil(root.scrollHeight);
      var scale = size.scale;
      while (scale > 1 && (height * scale > MAX_SIDE || width * scale * height * scale > MAX_AREA)) scale -= 0.5;
      if (height * scale > MAX_SIDE || width * scale * height * scale > MAX_AREA) throw new Error("long");
      var background = mdoc.defaultView.getComputedStyle(mdoc.body).backgroundColor;
      var xhtml = new XMLSerializer().serializeToString(root);
      var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + width + '" height="' + height + '"><foreignObject x="0" y="0" width="' + width + '" height="' + height + '">' + xhtml + "</foreignObject></svg>";
      return new Promise(function (resolve, reject) {
        var img = new Image();
        img.onload = function () { resolve(img); };
        img.onerror = function () { reject(new Error("image")); };
        img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
      }).then(function (img) {
        return (img.decode ? img.decode().catch(function () {}) : Promise.resolve()).then(function () { return img; });
      }).then(function (img) {
        var canvas = document.createElement("canvas");
        canvas.width = Math.round(width * scale);
        canvas.height = Math.round(height * scale);
        var g = canvas.getContext("2d");
        if (!g) throw new Error("long");
        function paint() {
          g.fillStyle = background && background !== "rgba(0, 0, 0, 0)" ? background : "#FDFCF9";
          g.fillRect(0, 0, canvas.width, canvas.height);
          g.drawImage(img, 0, 0, canvas.width, canvas.height);
        }
        // Safari leaves the pictures inside an SVG image blank on its first
        // draw and paints them on a draw that comes a moment later.
        paint();
        return new Promise(function (resolve) { setTimeout(resolve, 150); }).then(function () {
          paint();
          return new Promise(function (resolve, reject) {
            canvas.toBlob(function (blob) { blob ? resolve({ blob: blob, missed: missed }) : reject(new Error("long")); }, "image/png");
          });
        });
      });
    }).then(function (out) { done(); return out; }, function (err) { done(); throw err; });
  }

  // "Saved." stands alone only to say a picture stayed out; a plain save says nothing.
  function imageSaid(missed, lead) {
    if (!missed) return lead;
    var more = fill(missed === 1 ? S.imageMissed : S.imagesMissed, { n: missed });
    return lead + (data.lang === "zh" ? "" : " ") + more;
  }

  function imageFailed(err) {
    say(err && err.message === "long" ? S.imageTooLong : err && err.message === "busy" ? S.imageMaking : S.imageFailed);
  }

  function exportImage() {
    say(S.imageMaking);
    return longImage().then(function (out) {
      download(out.blob, baseName() + ".png");
      say(out.missed ? imageSaid(out.missed, S.imageSaved) : "");
      track("tool_export", { tool: TOOL, format: "png" });
    }, imageFailed);
  }

  // Safari copies an image only when the clipboard is asked inside the click,
  // so the picture goes in as a promise the click already holds.
  var canCopyImage = !!(window.ClipboardItem && navigator.clipboard && navigator.clipboard.write && window.isSecureContext &&
    (typeof ClipboardItem.supports !== "function" || ClipboardItem.supports("image/png")));
  function copyImage() {
    say(S.imageMaking);
    var missed = 0;
    var made = longImage().then(function (out) { missed = out.missed; return out.blob; });
    return navigator.clipboard.write([new ClipboardItem({ "image/png": made })]).then(function () {
      say(imageSaid(missed, S.imageCopied));
      track("tool_copy", { tool: TOOL, kind: "image" });
    }, function () {
      return made.then(function () { say(S.copyFailed); }, imageFailed);
    });
  }
  each(tool, '[data-action="copyimage"]', function (button) { button.hidden = !canCopyImage; });

  var actions = { pdf: exportPdf, html: exportHtml, md: saveMarkdown, copy: copyFormatted, docx: exportDocx, png: exportImage, copyimage: copyImage };
  var failures = { pdf: S.exportFailed, html: S.exportFailed, md: S.exportFailed, copy: S.copyFailed, docx: S.exportFailed, png: S.imageFailed, copyimage: S.copyFailed };
  tool.querySelector(".tool-actions").addEventListener("click", function (e) {
    var button = e.target.closest("[data-action]");
    if (!button || !write) return;
    var kind = button.dataset.action;
    try {
      actions[kind]().catch(function () { say(failures[kind]); });
    } catch (err) {
      say(failures[kind]);
    }
  });

  // ---- Start ---------------------------------------------------------------------

  try {
    var saved = localStorage.getItem(DRAFT_KEY);
    if (saved !== null && saved !== code.value) code.value = saved;
  } catch (e) { /* storage blocked */ }

  Promise.all([load(data.parser), frameReady]).then(function () {
    setup();
    render();
  }, function () { /* said by load */ });
})();
