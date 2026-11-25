// The Markmap editor on /tools/markmap-editor/ (scripts/build-tools.py).
// The outline on the left becomes a mind map on the right, drawn with the
// d3 and markmap files MiaoYan's preview ships, in the app's colours. Exports
// turn each node's HTML label into SVG text first: an image holding
// foreignObject taints the canvas in Safari and opens badly in design tools.
// Nothing leaves the browser.
(function () {
  "use strict";
  var data = JSON.parse(document.getElementById("markmap-data").textContent);
  var S = data.strings;
  var tool = document.getElementById("markmap-tool");
  var code = document.getElementById("markmap-code");
  var frame = document.getElementById("markmap-frame");
  var svg = document.getElementById("markmap-svg");
  var status = document.getElementById("markmap-status");

  var DRAFT_KEY = "miaoyan.markmap-editor.draft";
  var mm = null;
  var transformer = null;
  var timer = 0;
  var edited = false;
  var katexLoading = null;
  var SVG_NS = "http://www.w3.org/2000/svg";

  function track(name, params) {
    if (typeof window.gtag === "function") window.gtag("event", name, params || {});
  }

  function say(text) { status.textContent = text || ""; }

  // Scripts in order, each added once; a failed one is forgotten so the next
  // try adds only that one again.
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
    return list.reduce(function (chain, src) {
      return chain.then(function () { return loadOne(src); });
    }, Promise.resolve());
  }

  function colors() {
    return window.ThemeColors.getMarkmapColors(false);
  }

  // ---- Drawing -------------------------------------------------------------

  function render() {
    if (!mm) return;
    var text = code.value;
    if (!text.trim()) {
      mm.setData({ type: "root", depth: 0, content: "", children: [] });
      if (edited) store();
      svg.style.visibility = "hidden";
      say(S.empty);
      return;
    }
    svg.style.visibility = "";
    var result = transformer.transform(text);
    // Math draws with the local KaTeX; markmap would fetch its own from a CDN.
    if (result.features.katex && !window.katex && !katexLoading) {
      katexLoading = load(data.katex).then(function () {
        var link = document.createElement("link");
        link.rel = "stylesheet";
        link.href = data.katexCss;
        document.head.appendChild(link);
        render();
      }, function () {
        katexLoading = null;
        if (edited) store();
      });
    }
    mm.setData(result.root);
    mm.fit();
    // Saved once it has drawn, math included (the render after KaTeX arrives
    // saves), so an outline that hangs the page is not brought back on the
    // next visit.
    if (edited && !(result.features.katex && !window.katex)) store();
    if (status.textContent === S.empty) say("");
  }

  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(render, 200);
  }

  // Plain wheel scrolls the page; a pinch or Ctrl+wheel zooms, as in the
  // Mermaid editor. Dragging pans.
  function setup() {
    var lib = window.markmap;
    // Prism would come from a CDN for code fences, and KaTeX too; math draws
    // with the local KaTeX instead (render), code stays plain.
    var plugins = lib.builtInPlugins.filter(function (p) { return p.name !== "prism"; });
    plugins.forEach(function (p) {
      if (!p.config) return;
      ["preloadScripts", "scripts", "styles"].forEach(function (k) { if (p.config[k]) p.config[k].length = 0; });
    });
    transformer = new lib.Transformer(plugins);
    // Labels go into this page, not a sandbox: raw HTML in an outline would run
    // here, so it stays text. Before KaTeX arrives markmap returns the TeX as it
    // is, which is escaped too.
    var md = transformer.md;
    md.set({ html: false });
    var katexRule = md.renderer.rules.katex;
    if (katexRule) {
      md.renderer.rules.katex = function () {
        var out = katexRule.apply(this, arguments);
        return window.katex ? out : String(out).replace(/[&<>"]/g, function (c) {
          return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;" }[c];
        });
      };
    }
    mm = lib.Markmap.create(svg, {
      autoFit: false,
      duration: 300,
      // MiaoYan's preview spacing (its markmap loader).
      paddingX: 16,
      spacingVertical: 20,
      spacingHorizontal: 20,
      fitRatio: 0.92,
      // The app's box grows with the outline, so its labels stay near 16px;
      // this pane is the window's height, and markmap's default 2x would fit
      // a short outline at twice the size. Zoom still goes past it.
      maxScale: 1,
      color: function (node) {
        var list = colors();
        return list[node.depth % list.length];
      }
    });
    // markmap binds wheel-to-pan on Macs when it is created; d3's own zoom
    // listener (wheel.zoom) stays.
    mm.svg.on("wheel", null);
    mm.zoom.filter(function (e) {
      if (e.type === "wheel") return e.ctrlKey || e.metaKey;
      if (e.type === "touchstart") return e.touches.length > 1;
      return !e.button;
    });
    svg.style.touchAction = "pan-x pan-y";
    svg.addEventListener("wheel", function (e) {
      if (e.ctrlKey || e.metaKey) e.preventDefault();
    }, { passive: false });
    render();
    new ResizeObserver(function () { if (mm) mm.fit(); }).observe(frame);
  }

  svg.addEventListener("click", function (e) {
    var a = e.target.closest && e.target.closest("a[href]");
    if (!a) return;
    e.preventDefault();
    var href = a.getAttribute("href");
    if (/^(https?:|mailto:|\/|\.|#)/i.test(href) || !/^[a-z][a-z0-9+.-]*:/i.test(href)) {
      window.open(new URL(href, location.href).href, "_blank", "noopener");
    }
  });

  frame.querySelector(".tool-zoom").addEventListener("click", function (e) {
    var button = e.target.closest("[data-zoom]");
    if (!button || !mm) return;
    var kind = button.dataset.zoom;
    if (kind === "fit") mm.fit();
    else mm.rescale(kind === "in" ? 1.25 : 0.8);
  });

  // ---- Editing ---------------------------------------------------------------

  function store() {
    // A text too big to store must not leave an older draft to come back.
    try { localStorage.setItem(DRAFT_KEY, code.value); } catch (e) {
      try { localStorage.removeItem(DRAFT_KEY); } catch (e2) { /* storage blocked */ }
    }
  }

  code.addEventListener("input", function () {
    if (!edited) { edited = true; track("tool_render", { tool: "markmap" }); }
    if (location.hash) history.replaceState(null, "", location.pathname + location.search);
    schedule();
  });

  // Tab indents an outline level (two spaces), Shift+Tab outdents; after
  // Escape the next Tab leaves the editor.
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
    var lineStart = value.lastIndexOf("\n", start - 1) + 1;
    var last = end > start && value.charAt(end - 1) === "\n" ? end - 1 : end;
    var lineEnd = value.indexOf("\n", last);
    if (lineEnd < 0) lineEnd = value.length;
    var block = value.slice(lineStart, lineEnd);
    var changed = e.shiftKey ? block.replace(/^( {1,2}|\t)/gm, "") : block.replace(/^(?=.)/gm, "  ");
    if (changed === block) return;
    insert(lineStart, lineEnd, changed);
    if (start === end) {
      var caret = Math.max(lineStart, start + (changed.length - block.length));
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

  // ---- Export ------------------------------------------------------------------

  // The map as a standalone SVG: every node shown at its full size, labels as
  // SVG text, the colours and font written in rather than left to the page.
  function standalone() {
    var root = svg.querySelector("g");
    var box = root.getBBox();
    var pad = 24;
    var copy = svg.cloneNode(true);
    copy.removeAttribute("id");
    copy.removeAttribute("class");
    copy.removeAttribute("style");
    copy.setAttribute("xmlns", SVG_NS);
    var width = Math.ceil(box.width + pad * 2);
    var height = Math.ceil(box.height + pad * 2);
    copy.setAttribute("width", String(width));
    copy.setAttribute("height", String(height));
    copy.setAttribute("viewBox", [box.x - pad, box.y - pad, width, height].join(" "));
    var style = copy.querySelector("style");
    if (style) style.remove();
    var g = copy.querySelector("g");
    g.removeAttribute("transform");
    g.setAttribute("font-family", data.font);
    g.setAttribute("font-size", "16");
    var live = svg.querySelectorAll("foreignObject");
    Array.prototype.forEach.call(copy.querySelectorAll("foreignObject"), function (fo, i) {
      fo.parentNode.replaceChild(labelText(live[i]), fo);
    });
    Array.prototype.forEach.call(copy.querySelectorAll("circle"), function (c) { c.removeAttribute("style"); });
    // What the dropped stylesheet gave the links.
    Array.prototype.forEach.call(copy.querySelectorAll("path"), function (p) { p.setAttribute("fill", "none"); });
    // SVG text can run wider than the HTML it replaced: measure the copy itself.
    copy.style.cssText = "position:absolute;left:-100000px;top:0;visibility:hidden";
    document.body.appendChild(copy);
    var drawn = g.getBBox();
    copy.remove();
    copy.removeAttribute("style");
    var x0 = Math.min(box.x, drawn.x);
    var y0 = Math.min(box.y, drawn.y);
    width = Math.ceil(Math.max(box.x + box.width, drawn.x + drawn.width) - x0 + pad * 2);
    height = Math.ceil(Math.max(box.y + box.height, drawn.y + drawn.height) - y0 + pad * 2);
    copy.setAttribute("width", String(width));
    copy.setAttribute("height", String(height));
    copy.setAttribute("viewBox", [x0 - pad, y0 - pad, width, height].join(" "));
    return { text: new XMLSerializer().serializeToString(copy), width: width, height: height };
  }

  var BLOCK = /^(P|DIV|PRE|LI|UL|OL|BLOCKQUOTE|H[1-6]|TABLE|TR)$/;

  // One label's runs, each with the weight, slant and family it shows in,
  // a line per <br>, block or line of a code block, math as its TeX.
  function labelText(fo) {
    var x = +fo.getAttribute("x");
    var y = +fo.getAttribute("y");
    var h = +fo.getAttribute("height");
    var lines = [[]];
    function brk() { if (lines[lines.length - 1].length) lines.push([]); }
    function run(textValue, el, pre) {
      var parts = pre ? textValue.split("\n") : [textValue.replace(/\s+/g, " ")];
      parts.forEach(function (part, k) {
        if (k > 0) lines.push([]);
        var line = lines[lines.length - 1];
        // A code line keeps its indentation; other runs lose the space a
        // wrapped line starts with.
        if (!line.length && !pre) part = part.replace(/^\s+/, "");
        if (part) line.push({ text: part, el: el });
      });
    }
    (function walk(node, pre) {
      Array.prototype.forEach.call(node.childNodes, function (child) {
        if (child.nodeType === 3) { run(child.nodeValue, node, pre); return; }
        if (child.nodeType !== 1) return;
        if (child.classList.contains("katex")) {
          var tex = child.querySelector('annotation[encoding="application/x-tex"]');
          run(tex ? tex.textContent : child.textContent, child, false);
          return;
        }
        if (child.tagName === "BR") { lines.push([]); return; }
        var block = BLOCK.test(child.tagName);
        if (block) brk();
        walk(child, pre || child.tagName === "PRE");
        if (block) brk();
      });
    })(fo.firstElementChild, false);
    lines = lines.filter(function (l) { return l.length; });
    if (!lines.length) lines = [[]];
    var text = document.createElementNS(SVG_NS, "text");
    text.setAttribute("dominant-baseline", "central");
    text.setAttribute("fill", data.ink);
    text.setAttribute("xml:space", "preserve");
    var step = h / lines.length;
    lines.forEach(function (line, n) {
      var row = document.createElementNS(SVG_NS, "tspan");
      row.setAttribute("x", String(x));
      row.setAttribute("y", String(y + step * (n + 0.5)));
      line.forEach(function (r) {
        var span = document.createElementNS(SVG_NS, "tspan");
        var cs = getComputedStyle(r.el);
        if (parseInt(cs.fontWeight, 10) >= 600) span.setAttribute("font-weight", "bold");
        if (cs.fontStyle === "italic") span.setAttribute("font-style", "italic");
        if (r.el.closest("code")) {
          span.setAttribute("font-family", data.codeFont);
          span.setAttribute("font-size", "14");
        }
        if (r.el.closest("a")) span.setAttribute("fill", data.link);
        if (r.el.closest("del, s")) span.setAttribute("text-decoration", "line-through");
        span.textContent = r.text;
        row.appendChild(span);
      });
      text.appendChild(row);
    });
    return text;
  }

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

  function fileName(ext) {
    var first = mm && mm.state && mm.state.data && mm.state.data.content;
    var name = first ? (new DOMParser().parseFromString(first, "text/html").body.textContent || "") : "";
    return (name.replace(/[\\/:*?"<>|]+/g, " ").trim().slice(0, 60) || "markmap") + "." + ext;
  }

  // Wait for the folding or refit animation to finish, so the export is the
  // map as it settles rather than halfway.
  function settled() {
    return new Promise(function (resolve) {
      var waited = 0;
      (function check() {
        var moving = svg.__transition || Array.prototype.some.call(svg.querySelectorAll("*"), function (n) { return n.__transition; });
        if (!moving || waited >= 2000) resolve();
        else { waited += 50; setTimeout(check, 50); }
      })();
    });
  }

  function exportSvg() {
    return settled().then(function () {
      download(new Blob([standalone().text], { type: "image/svg+xml" }), fileName("svg"));
      track("tool_export", { tool: "markmap", format: "svg" });
    });
  }

  function pngBlob() {
    return settled().then(function () {
      var out = standalone();
      // Under every browser's canvas area and side limits.
      var scale = Math.min(2, Math.sqrt(16e6 / Math.max(1, out.width * out.height)), 16384 / out.width, 16384 / out.height);
      var url = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(out.text);
      return new Promise(function (resolve, reject) {
        var img = new Image();
        img.onload = function () {
          var canvas = document.createElement("canvas");
          canvas.width = Math.ceil(out.width * scale);
          canvas.height = Math.ceil(out.height * scale);
          var ctx = canvas.getContext("2d");
          ctx.fillStyle = window.ThemeColors.getThemeColors(false).diagramBg;
          ctx.fillRect(0, 0, canvas.width, canvas.height);
          ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
          canvas.toBlob(function (blob) { blob ? resolve(blob) : reject(new Error("png")); }, "image/png");
        };
        img.onerror = function () { reject(new Error("png")); };
        img.src = url;
      });
    });
  }

  function exportPng() {
    return pngBlob().then(function (blob) {
      download(blob, fileName("png"));
      track("tool_export", { tool: "markmap", format: "png" });
    });
  }

  // Safari wants the ClipboardItem made inside the click, holding a promise.
  function copyImage() {
    return navigator.clipboard.write([new ClipboardItem({ "image/png": pngBlob() })]).then(function () {
      say(S.copiedImage);
      track("tool_copy", { tool: "markmap", kind: "image" });
    });
  }

  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
    return new Promise(function (resolve, reject) {
      var area = document.createElement("textarea");
      area.value = text;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.opacity = "0";
      document.body.appendChild(area);
      area.select();
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (err) { ok = false; }
      area.remove();
      ok ? resolve() : reject(new Error("copy"));
    });
  }

  // A markmap block for a note: MiaoYan and other Markmap-aware previews draw it.
  function copyMarkdown() {
    var body = code.value.replace(/\s+$/, "");
    var fence = "```";
    while (body.indexOf(fence) >= 0) fence += "`";
    return copyText(fence + "markmap\n" + body + "\n" + fence + "\n").then(function () {
      say(S.copiedMarkdown);
      track("tool_copy", { tool: "markmap", kind: "markdown" });
    });
  }

  var actions = { png: exportPng, image: copyImage, svg: exportSvg, markdown: copyMarkdown };
  var failures = { png: S.exportFailed, image: S.copyFailed, svg: S.exportFailed, markdown: S.copyFailed };
  tool.querySelector(".tool-actions").addEventListener("click", function (e) {
    var button = e.target.closest("[data-action]");
    if (!button) return;
    var kind = button.dataset.action;
    if (!mm || !code.value.trim()) { say(S.empty); return; }
    try {
      actions[kind]().catch(function () { say(failures[kind]); });
    } catch (err) {
      say(failures[kind]);
    }
  });

  if (window.ClipboardItem && navigator.clipboard && navigator.clipboard.write && window.isSecureContext) {
    tool.querySelector('[data-action="image"]').hidden = false;
  }

  // ---- Start ---------------------------------------------------------------------

  // A link from the blog carries an outline after #m=, deflated and in
  // base64url as the Mermaid editor's links are (scripts/mermaid_assets.py
  // payload); #b= is the same outline without compression. 200 KB inflated
  // is far past any outline, so a bigger link is dropped.
  var LIMIT = 200000;

  function fromBase64Url(text) {
    var b64 = text.replace(/-/g, "+").replace(/_/g, "/");
    while (b64.length % 4) b64 += "=";
    var bin = atob(b64);
    var bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
  }

  function inflate(bytes) {
    var reader = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate-raw")).getReader();
    var parts = [];
    var size = 0;
    function pump() {
      return reader.read().then(function (step) {
        if (step.done) {
          var out = new Uint8Array(size);
          var at = 0;
          parts.forEach(function (p) { out.set(p, at); at += p.length; });
          return out;
        }
        size += step.value.length;
        if (size > LIMIT) { reader.cancel(); throw new Error("too large"); }
        parts.push(step.value);
        return pump();
      });
    }
    return pump();
  }

  function shared(hash) {
    var m = /^#([mb])=([A-Za-z0-9_-]+)$/.exec(hash);
    if (!m) return Promise.resolve(null);
    try {
      var bytes = fromBase64Url(m[2]);
      if (m[1] === "b") return Promise.resolve(bytes.length > LIMIT ? null : new TextDecoder().decode(bytes));
      if (typeof DecompressionStream !== "function") { say(S.oldBrowser); return Promise.resolve(null); }
      return inflate(bytes).then(function (out) { return new TextDecoder().decode(out); }, function () { return null; });
    } catch (e) {
      return Promise.resolve(null);
    }
  }

  // A shared link opens its outline; otherwise the reader's last draft returns.
  shared(location.hash).then(function (text) {
    if (text !== null) { code.value = text; return; }
    try {
      var saved = localStorage.getItem(DRAFT_KEY);
      if (saved !== null && saved !== code.value) code.value = saved;
    } catch (e) { /* storage blocked */ }
  }).then(function () {
    return load(data.vendor).then(setup, function () { say(S.loadFailed); });
  });
})();
