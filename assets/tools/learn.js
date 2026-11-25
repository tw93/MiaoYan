// Learn Markdown, /learn/ and /zh/learn/ (scripts/build-learn.py): a level
// is done when the reader's text draws the same blocks as the level's answer.
// Both are parsed by the same markdown-it rules as the Markdown viewer
// (md-rules.js) and compared by what they build, not by their characters:
// tags, the attributes that change what is drawn, and the words, so
// *a* and _a_, "- " and "* " lists, or a loose and a tight list read as one.
// Formulas compare by their TeX without spaces and Mermaid by its edges.
// Blocks that differ are tinted in the preview, matched by their longest
// common run so one extra block marks only itself. Progress, the level and
// each level's text stay in localStorage.
(function () {
  "use strict";

  var data = JSON.parse(document.getElementById("learn-data").textContent);
  var S = data.strings;
  var LV = data.levels;
  var KEY = "miaoyan.learn";

  function $(id) { return document.getElementById(id); }
  var tool = $("learn-tool");
  var code = $("learn-code");
  var mineFrame = $("learn-mine");
  var goalFrame = $("learn-goal");
  var titleEl = $("learn-title");
  var textEl = $("learn-text");
  var hintEl = $("learn-hint");
  var status = $("learn-status");
  var countEl = $("learn-count");
  var finish = $("learn-finish");
  var dots = Array.prototype.slice.call(tool.querySelectorAll(".learn-dot"));
  var nextButton = tool.querySelector('[data-action="next"]');

  var state = { at: 0, done: {}, text: {} };
  try {
    var saved = JSON.parse(localStorage.getItem(KEY) || "null");
    if (saved && typeof saved === "object") {
      state.at = Math.min(Math.max(parseInt(saved.at, 10) || 0, 0), LV.length - 1);
      if (saved.done && typeof saved.done === "object") state.done = saved.done;
      if (saved.text && typeof saved.text === "object") state.text = saved.text;
    }
  } catch (e) { /* storage blocked or unreadable: start fresh */ }

  function store() {
    try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) { /* storage blocked */ }
  }
  function track(name, params) {
    if (typeof window.gtag === "function") window.gtag("event", name, params || {});
  }
  function say(text) { status.textContent = text || ""; }
  function fill(s, map) { return s.replace(/\{(\w+)\}/g, function (m, k) { return k in map ? map[k] : m; }); }
  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) { return c === "&" ? "&amp;" : c === "<" ? "&lt;" : c === ">" ? "&gt;" : "&quot;"; });
  }

  // ---- Loading -------------------------------------------------------------------

  var scripts = {};
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
    var done = list.reduce(function (chain, src) { return chain.then(function () { return loadOne(src); }); }, Promise.resolve());
    done.catch(function () { say(S.loadFailed); });
    return done;
  }

  // ---- Parsing ---------------------------------------------------------------------

  var view = null;
  var compare = null;
  var svgCache = {};
  var katexReady = null;
  var mermaidReady = null;
  var mermaidLoaded = false;

  function tex(s) { return s.replace(/\s+/g, ""); }

  function renderMath(src, display) {
    if (window.katex) {
      try { return window.katex.renderToString(src, { displayMode: display, throwOnError: false }); } catch (e) { /* the source */ }
    }
    var shown = display ? "$$" + src + "$$" : "$" + src + "$";
    return display ? '<p class="math-src">' + esc(shown) + "</p>" : esc(shown);
  }

  // A flowchart as its direction, its edges by label and its lone nodes, so
  // "B --> C[x]" and "B[y] --> C[x]" after "A --> B[y]" read the same.
  var ARROW = /\s*(-->|---|==>|-\.->)\s*/;
  var NODE = /^([A-Za-z0-9_]+)\s*(?:\[([^\]]*)\]|\(([^)]*)\)|\{([^}]*)\})?\s*$/;
  function graphKey(src) {
    var lines = src.split("\n").map(function (l) { return l.trim(); }).filter(Boolean);
    var flat = src.replace(/\s+/g, "");
    if (!lines.length) return "";
    var head = lines[0].replace(/^graph\b/, "flowchart").replace(/\s+/g, " ");
    var labels = {};
    var nodes = {};
    var edges = [];
    for (var i = 1; i < lines.length; i++) {
      var parts = lines[i].split(ARROW);
      var ids = [];
      for (var p = 0; p < parts.length; p += 2) {
        var m = NODE.exec(parts[p]);
        if (!m) return "raw:" + flat;
        var label = m[2] != null ? m[2] : m[3] != null ? m[3] : m[4];
        if (label != null) labels[m[1]] = label.trim();
        nodes[m[1]] = true;
        ids.push(m[1]);
      }
      for (var k = 1; k < ids.length; k++) edges.push([ids[k - 1], parts[2 * k - 1], ids[k]]);
    }
    function name(id) { return labels[id] != null ? labels[id] : id; }
    var linked = {};
    var list = edges.map(function (e) { linked[e[0]] = linked[e[2]] = true; return name(e[0]) + e[1] + name(e[2]); }).sort();
    var alone = Object.keys(nodes).filter(function (id) { return !linked[id]; }).map(name).sort();
    return head + "|" + list.join(",") + "|" + alone.join(",");
  }

  function make(forCompare) {
    var md = window.markdownit({ html: true, linkify: true });
    window.MiaoYanMarkdownRules.use(md);
    md.renderer.rules.math_inline = function (tokens, idx) {
      var t = tokens[idx];
      var display = !!(t.meta && t.meta.display);
      return forCompare ? '<span data-tex="' + esc(tex(t.content)) + '" data-display="' + display + '"></span>' : renderMath(t.content, display);
    };
    md.renderer.rules.math_block = function (tokens, idx) {
      return forCompare ? '<div data-tex="' + esc(tex(tokens[idx].content)) + '"></div>\n' : renderMath(tokens[idx].content, true) + "\n";
    };
    md.renderer.rules.fence = function (tokens, idx) {
      var t = tokens[idx];
      var lang = (t.info || "").trim().split(/\s+/)[0].toLowerCase();
      if (lang === "mermaid") {
        if (forCompare) return '<div data-mermaid="' + esc(graphKey(t.content)) + '"></div>\n';
        return '<div class="mermaid-image-container" data-mermaid="' + esc(t.content) + '">' +
          (svgCache[t.content] || "<pre><code>" + esc(t.content) + "</code></pre>") + "</div>\n";
      }
      if (forCompare) return "<pre><code" + (lang ? ' class="language-' + esc(lang) + '"' : "") + ">" + esc(t.content) + "</code></pre>\n";
      var hl = window.hljs;
      var body = lang && hl && hl.getLanguage(lang) ? hl.highlight(t.content, { language: lang, ignoreIllegals: true }).value : esc(t.content);
      return '<pre><code class="hljs' + (lang ? " language-" + esc(lang) : "") + '">' + body + "</code></pre>\n";
    };
    return md;
  }

  // ---- Comparing -------------------------------------------------------------------

  var KEEP = {
    A: ["href"], IMG: ["src", "alt"], INPUT: ["checked"], TH: ["style"], TD: ["style"], OL: ["start"],
    CODE: ["class"], SPAN: ["data-tex", "data-display"], DIV: ["data-tex", "data-mermaid"],
  };
  var BLOCK = /\s?(<\/?(?:P|LI|UL|OL|H[1-6]|BLOCKQUOTE|TABLE|THEAD|TBODY|TR|TH|TD|PRE|DIV|HR|BR)\b[^>]*>)\s?/g;

  function key(node, inPre) {
    if (node.nodeType === 3) return inPre ? node.data : node.data.replace(/\s+/g, " ");
    if (node.nodeType !== 1) return "";
    var tag = node.tagName;
    var inner = "";
    for (var c = node.firstChild; c; c = c.nextSibling) inner += key(c, inPre || tag === "PRE");
    if (tag === "PRE") inner = inner.replace(/[ \t]+$/gm, "").replace(/\n+(<\/CODE>)?$/, "$1");
    // A loose list item wraps its text in a paragraph; a tight one does not.
    if (tag === "P" && node.parentNode && node.parentNode.tagName === "LI") return inner;
    var attrs = (KEEP[tag] || []).filter(function (a) { return node.hasAttribute(a); }).map(function (a) {
      var v = node.getAttribute(a);
      if (a === "style") v = v.replace(/\s+/g, "");
      return " " + a + (a === "checked" ? "" : "=" + v);
    }).join("");
    return "<" + tag + attrs + ">" + inner + "</" + tag + ">";
  }

  function blocks(md, text) {
    var t = document.createElement("template");
    t.innerHTML = md.render(text);
    return Array.prototype.map.call(t.content.children, function (el) {
      return key(el, false).replace(BLOCK, "$1").trim();
    });
  }

  // Which of the reader's blocks are not in the longest run shared with the goal.
  function unmatched(a, b) {
    var n = a.length;
    var m = b.length;
    var table = [];
    for (var i = 0; i <= n; i++) { table.push(new Array(m + 1).fill(0)); }
    for (i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        table[i][j] = a[i] === b[j] ? table[i + 1][j + 1] + 1 : Math.max(table[i + 1][j], table[i][j + 1]);
      }
    }
    var off = {};
    i = 0;
    j = 0;
    while (i < n && j < m) {
      if (a[i] === b[j]) { i++; j++; } else if (table[i + 1][j] >= table[i][j + 1]) { off[i] = true; i++; } else { j++; }
    }
    for (; i < n; i++) off[i] = true;
    return off;
  }

  // ---- Frames ------------------------------------------------------------------------

  var OFF_CSS = ".learn-off { background: #F2ECE1; border-radius: 6px; box-shadow: 0 0 0 6px #F2ECE1; }";
  var frameDoc = "<!doctype html><html lang=\"" + (data.lang === "zh" ? "zh-CN" : "en") + "\"><head><meta charset=\"utf-8\">" +
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title></title>" +
    data.css.concat([data.katexCss]).map(function (href) { return '<link rel="stylesheet" href="' + href + '">'; }).join("") +
    "<style>" + data.pageCss + " html { padding: 20px; } #write { padding: 0 8px; } #write > :last-child { margin-bottom: 0; } " + OFF_CSS + "</style></head><body><div class=\"markdown-body heti\" id=\"write\"></div></body></html>";

  function frameReady(frame) {
    return new Promise(function (resolve) {
      frame.addEventListener("load", function () {
        var doc = frame.contentDocument;
        var write = doc && doc.location.href === "about:srcdoc" ? doc.getElementById("write") : null;
        if (!write) { frame.srcdoc = frameDoc; return; }
        // Links in a lesson's note go nowhere; the page is the lesson.
        doc.addEventListener("click", function (e) { if (e.target.closest && e.target.closest("a")) e.preventDefault(); });
        doc.addEventListener("submit", function (e) { e.preventDefault(); });
        resolve(write);
      });
      frame.srcdoc = frameDoc;
    });
  }
  var mineWrite = null;
  var goalWrite = null;

  // What MiaoYan's preview does after parsing (common.js): task lists marked,
  // wide tables in a scroller.
  function finishDom(root) {
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
      var wrapper = table.ownerDocument.createElement("div");
      wrapper.className = "table-scroll";
      table.parentNode.insertBefore(wrapper, table);
      wrapper.appendChild(table);
    });
    Array.prototype.forEach.call(root.querySelectorAll("meta, base"), function (el) { el.remove(); });
  }

  // ---- Extras: KaTeX and Mermaid, loaded when a level or a text needs them ----------------

  function needsMath(text) { return text.indexOf("$") >= 0; }
  function needsMermaid(text) { return /```\s*mermaid/i.test(text); }

  function ensure(text) {
    var waits = [];
    if (needsMath(text) && !window.katex) {
      if (!katexReady) { katexReady = load(data.katex); katexReady.catch(function () { katexReady = null; }); }
      waits.push(katexReady);
    }
    if (needsMermaid(text) && !mermaidLoaded) {
      if (!mermaidReady) {
        mermaidReady = load(data.mermaid).then(function () {
          var base = window.ThemeColors.getMermaidConfig(false);
          window.mermaid.initialize(Object.assign({}, base, data.mermaidConfig, { startOnLoad: false }));
          mermaidLoaded = true;
        });
        mermaidReady.catch(function () { mermaidReady = null; });
      }
      waits.push(mermaidReady);
    }
    return waits.length ? Promise.all(waits) : null;
  }

  var diagramId = 0;
  function drawDiagrams(root, then) {
    var boxes = Array.prototype.slice.call(root.querySelectorAll("[data-mermaid]"));
    if (!boxes.length || !mermaidLoaded) return;
    mermaidReady.then(function () {
      return boxes.reduce(function (chain, box) {
        return chain.then(function () {
          var source = box.getAttribute("data-mermaid");
          if (svgCache[source]) { box.innerHTML = svgCache[source]; return; }
          var id = "learn-mermaid-" + (++diagramId);
          return window.mermaid.render(id, source).then(function (out) {
            svgCache[source] = out.svg;
            if (box.isConnected) box.innerHTML = out.svg;
          }, function () {
            var stray = document.getElementById("d" + id);
            if (stray) stray.remove();
          });
        });
      }, Promise.resolve());
    }).catch(function () { /* said by load */ }).then(function () { if (then) then(); });
  }

  // ---- A level ------------------------------------------------------------------------

  var goalKeys = null;
  var timer = 0;

  function level() { return LV[state.at]; }
  function doneCount() { return LV.filter(function (l) { return state.done[l.id]; }).length; }

  function paintMap() {
    dots.forEach(function (dot, i) {
      dot.classList.toggle("is-done", !!state.done[LV[i].id]);
      if (i === state.at) dot.setAttribute("aria-current", "step"); else dot.removeAttribute("aria-current");
    });
    var n = doneCount();
    countEl.textContent = fill(S.count, { n: n, total: LV.length });
    finish.hidden = n < LV.length;
  }

  function render() {
    timer = 0;
    if (!view || !mineWrite) return;
    var L = level();
    var text = code.value;
    var wait = ensure(text);
    if (wait) wait.then(function () { if (level() === L) { render(); paintGoal(); } }, function () {});
    var mine = blocks(compare, text);
    if (!goalKeys) goalKeys = blocks(compare, L.answer);
    var passed = mine.length === goalKeys.length && mine.every(function (k, i) { return k === goalKeys[i]; });
    mineWrite.innerHTML = view.render(text);
    var kids = mineWrite.children;
    if (!passed && kids.length === mine.length) {
      var off = unmatched(mine, goalKeys);
      for (var i = 0; i < kids.length; i++) if (off[i]) kids[i].classList.add("learn-off");
    }
    finishDom(mineWrite);
    drawDiagrams(mineWrite);
    if (passed && !state.done[L.id]) {
      state.done[L.id] = 1;
      store();
      track("learn_level", { level: L.id });
      if (doneCount() === LV.length) track("learn_complete");
    }
    nextButton.classList.toggle("tool-chip-primary", passed);
    say(passed ? (doneCount() === LV.length ? S.allDone : S.passed) : "");
    paintMap();
  }

  // The goal's frame is as tall as the goal, so a one-line goal on its own
  // row (a narrow window) leaves no empty box; its pane caps the height.
  function fitGoal() {
    if (!goalWrite) return;
    var doc = goalWrite.ownerDocument;
    var pad = parseFloat(doc.defaultView.getComputedStyle(doc.documentElement).paddingBottom) || 0;
    var bottom = goalWrite.getBoundingClientRect().bottom + doc.defaultView.scrollY + pad;
    goalFrame.style.height = Math.ceil(bottom) + "px";
  }

  function paintGoal() {
    if (!view || !goalWrite) return;
    goalWrite.innerHTML = view.render(level().answer);
    finishDom(goalWrite);
    fitGoal();
    drawDiagrams(goalWrite, fitGoal);
  }

  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(render, 120);
  }

  function show(i) {
    state.at = i;
    store();
    var L = level();
    titleEl.innerHTML = '<span class="learn-no">' + esc(fill(S.level, { n: i + 1 })) + "</span> " + esc(L.title);
    textEl.innerHTML = L.text;
    hintEl.innerHTML = L.hint;
    hintEl.hidden = true;
    code.value = state.text[L.id] != null ? state.text[L.id] : L.start;
    code.scrollTop = 0;
    code.setSelectionRange(code.value.length, code.value.length);
    nextButton.hidden = i === LV.length - 1;
    goalKeys = null;
    var wait = ensure(L.answer);
    if (wait) wait.then(function () { if (level() === L) { goalKeys = null; paintGoal(); render(); } }, function () {});
    paintGoal();
    render();
  }

  function go(i, focus) {
    show(i);
    var top = tool.getBoundingClientRect().top;
    if (top < 0 || top > window.innerHeight * 0.5) tool.scrollIntoView({ block: "start" });
    if (focus && window.matchMedia("(pointer: fine)").matches) code.focus();
  }

  // ---- Input ------------------------------------------------------------------------

  code.addEventListener("input", function () {
    state.text[level().id] = code.value;
    store();
    schedule();
  });

  window.MiaoYanEditor.attach(code, { save: function () {} });

  // Command-Return (Control-Return elsewhere) moves on once a level is done.
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Enter" || !(e.metaKey || e.ctrlKey) || e.altKey) return;
    if (state.at >= LV.length - 1 || !state.done[level().id]) return;
    e.preventDefault();
    e.stopPropagation();
    go(state.at + 1, true);
  }, true);

  tool.addEventListener("click", function (e) {
    var dot = e.target.closest(".learn-dot");
    if (dot) { go(parseInt(dot.getAttribute("data-level"), 10), true); return; }
    var button = e.target.closest("[data-action]");
    if (!button) return;
    var action = button.getAttribute("data-action");
    var L = level();
    if (action === "hint") {
      hintEl.hidden = false;
      track("learn_hint", { level: L.id });
    } else if (action === "answer") {
      code.value = L.answer;
      state.text[L.id] = L.answer;
      store();
      render();
      track("learn_answer", { level: L.id });
    } else if (action === "reset") {
      code.value = L.start;
      delete state.text[L.id];
      store();
      render();
      code.focus();
    } else if (action === "next") {
      if (state.at < LV.length - 1) go(state.at + 1, true);
    } else if (action === "again") {
      state = { at: 0, done: {}, text: {} };
      store();
      go(0, true);
    }
  });

  // ---- Start ------------------------------------------------------------------------

  var parsed = load(data.parser).then(function () {
    view = make(false);
    compare = make(true);
  });
  Promise.all([parsed, frameReady(mineFrame), frameReady(goalFrame)]).then(function (r) {
    mineWrite = r[1];
    goalWrite = r[2];
    goalWrite.ownerDocument.addEventListener("load", fitGoal, true);
    window.addEventListener("resize", fitGoal);
    show(state.at);
  }, function () { /* said by load */ });
  paintMap();
})();
