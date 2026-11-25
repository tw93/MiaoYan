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

  var DRAFT_KEY = "miaoyan.markdown-viewer.draft";
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
        return '<div class="mermaid-image-container" data-mermaid="' + esc(token.content) + '">' +
          (svg || "<pre><code>" + esc(token.content) + "</code></pre>") + "</div>\n";
      }
      var hl = window.hljs;
      var body = lang && hl && hl.getLanguage(lang)
        ? hl.highlight(token.content, { language: lang, ignoreIllegals: true }).value
        : esc(token.content);
      return '<pre><code class="hljs' + (lang ? " language-" + esc(lang) : "") + '">' + body + "</code></pre>\n";
    };
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
    if (!edited) { edited = true; track("tool_render", { tool: "viewer" }); }
    say("");
    schedule();
  });

  // Tab indents by four spaces, Shift+Tab outdents; after Escape the next Tab
  // leaves the editor.
  var tabLeaves = false;
  code.addEventListener("keydown", function (e) {
    if (e.key === "Escape") { tabLeaves = true; return; }
    if (e.key === "Shift" || e.key === "Control" || e.key === "Alt" || e.key === "Meta") return;
    if (e.key !== "Tab" || e.altKey || e.ctrlKey || e.metaKey) { tabLeaves = false; return; }
    if (tabLeaves) { tabLeaves = false; return; }
    e.preventDefault();
    var value = code.value;
    var start = code.selectionStart;
    var end = code.selectionEnd;
    if (!e.shiftKey && start === end) { insert(start, end, "    "); return; }
    var lineStart = value.lastIndexOf("\n", start - 1) + 1;
    var last = end > start && value.charAt(end - 1) === "\n" ? end - 1 : end;
    var lineEnd = value.indexOf("\n", last);
    if (lineEnd < 0) lineEnd = value.length;
    var block = value.slice(lineStart, lineEnd);
    var changed = e.shiftKey ? block.replace(/^( {1,4}|\t)/gm, "") : block.replace(/^(?=.)/gm, "    ");
    if (changed === block) return;
    insert(lineStart, lineEnd, changed);
    if (start === end) {
      var caret = Math.max(lineStart, start - (block.length - changed.length));
      code.setSelectionRange(caret, caret);
    } else {
      code.setSelectionRange(lineStart, lineStart + changed.length);
    }
  });

  function insert(start, end, text) {
    code.setSelectionRange(start, end);
    var ok = false;
    try { ok = document.execCommand("insertText", false, text); } catch (err) { ok = false; }
    if (!ok) {
      code.setRangeText(text, start, end, "end");
      code.dispatchEvent(new Event("input", { bubbles: true }));
    }
  }

  // The preview follows the editor's scroll by proportion.
  code.addEventListener("scroll", function () {
    var doc = frame.contentDocument;
    var el = doc && doc.scrollingElement;
    if (!el) return;
    var room = code.scrollHeight - code.clientHeight;
    el.scrollTop = room > 0 ? (code.scrollTop / room) * (el.scrollHeight - el.clientHeight) : 0;
  });

  onlyButton.addEventListener("click", function () {
    var on = onlyButton.getAttribute("aria-pressed") !== "true";
    onlyButton.setAttribute("aria-pressed", String(on));
    grid.classList.toggle("is-preview-only", on);
  });

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
      track("tool_import", { tool: "viewer", source: "file" });
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
    if (!cssText) {
      cssText = Promise.all(data.css.map(function (href) {
        return fetch(href).then(function (r) { if (!r.ok) throw new Error("css"); return r.text(); });
      }));
      cssText.catch(function () { cssText = null; });
    }
    return cssText.then(function (sheets) {
      var math = write.querySelector(".katex") ? '<link rel="stylesheet" href="' + data.site + data.katexCss + '">' : "";
      var title = "<title>" + esc(frame.contentDocument.title) + "</title>";
      // The preview runs none of the note's script, and the file does not either.
      var csp = '<meta http-equiv="Content-Security-Policy" content="script-src \'none\'">';
      var html = shell(csp + "<style>" + sheets.join("\n") + "</style>" + math).replace("<title></title>", title) +
        write.innerHTML + "</div></body></html>\n";
      download(new Blob([html], { type: "text/html" }), baseName() + ".html");
      track("tool_export", { tool: "viewer", format: "html" });
    });
  }

  function exportPdf() {
    var win = frame.contentWindow;
    win.focus();
    win.print();
    track("tool_export", { tool: "viewer", format: "pdf" });
    return Promise.resolve();
  }

  // The rendered note as rich text, for a document, an email or a CMS.
  function copyFormatted() {
    var html = write.innerHTML;
    var text = write.innerText;
    if (window.ClipboardItem && navigator.clipboard && navigator.clipboard.write && window.isSecureContext) {
      return navigator.clipboard.write([new ClipboardItem({
        "text/html": new Blob([html], { type: "text/html" }),
        "text/plain": new Blob([text], { type: "text/plain" })
      })]).then(done);
    }
    return new Promise(function (resolve, reject) {
      var onCopy = function (e) {
        e.clipboardData.setData("text/html", html);
        e.clipboardData.setData("text/plain", text);
        e.preventDefault();
      };
      document.addEventListener("copy", onCopy);
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (err) { ok = false; }
      document.removeEventListener("copy", onCopy);
      ok ? resolve() : reject(new Error("copy"));
    }).then(done);
    function done() {
      say(S.copied);
      track("tool_copy", { tool: "viewer", kind: "formatted" });
    }
  }

  var actions = { pdf: exportPdf, html: exportHtml, copy: copyFormatted };
  var failures = { pdf: S.exportFailed, html: S.exportFailed, copy: S.copyFailed };
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
