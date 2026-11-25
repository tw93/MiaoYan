// The Mermaid live editor on /tools/mermaid-editor/ (scripts/build-tools.py).
// The page arrives with the default template's diagram already drawn, so the
// first paint needs no script. Mermaid itself, 660 KB over the wire, loads when
// the reader touches the editor or once the page has settled, never while the
// page is only being prerendered from a hover.
(function () {
  "use strict";
  var data = JSON.parse(document.getElementById("mermaid-data").textContent);
  var S = data.strings;
  var code = document.getElementById("mermaid-code");
  var preview = document.getElementById("mermaid-preview");
  var frame = document.getElementById("mermaid-frame");
  var lines = document.getElementById("mermaid-lines");
  var status = document.getElementById("mermaid-status");
  var undoButton = document.getElementById("mermaid-undo");
  var syntax = document.getElementById("mermaid-syntax");
  var chips = Array.prototype.slice.call(document.querySelectorAll(".tool-chip"));
  var byId = {};
  data.templates.forEach(function (t) { byId[t.id] = t; });

  var DRAFT_KEY = "miaoyan.mermaid-editor.draft";
  var loading = null;
  var ready = false;
  var seq = 0;
  var timer = 0;
  var lastGood = "";
  var lastGoodCode = "";
  var undoCode = null;
  var edited = false;
  var rendered = false;

  function track(name, params) {
    if (typeof window.gtag === "function") window.gtag("event", name, params || {});
  }

  var renderError = false;

  // Line numbers beside the code, scrolled with it; the line Mermaid stopped at
  // is marked.
  function updateLines(errorLine) {
    var count = code.value.split("\n").length;
    if (lines.childElementCount !== count) {
      var html = "";
      for (var i = 1; i <= count; i++) html += "<span>" + i + "</span>";
      lines.innerHTML = html;
    }
    var marked = lines.querySelector(".is-error");
    if (marked) marked.classList.remove("is-error");
    if (errorLine && lines.children[errorLine - 1]) lines.children[errorLine - 1].classList.add("is-error");
    syncScroll();
  }

  function syncScroll() {
    lines.style.transform = "translateY(" + -code.scrollTop + "px)";
  }

  // Preview zoom: the diagram fits the frame until the reader zooms; after that
  // edits keep the zoom and position, and Fit returns to the fitted view.
  var view = { scale: 1, x: 0, y: 0, fitted: true };

  function contentSize() {
    var el = preview.firstElementChild;
    if (!el) return null;
    var w = parseFloat(el.getAttribute("width"));
    var h = parseFloat(el.getAttribute("height"));
    return w > 0 && h > 0 ? { w: w, h: h } : null;
  }

  function apply() {
    preview.style.transform = "translate(" + view.x + "px," + view.y + "px) scale(" + view.scale + ")";
    frame.classList.toggle("is-zoomed", !view.fitted);
  }

  function fit() {
    var size = contentSize();
    if (!size) return;
    // The frame's own padding, as the CSS sets it before the script takes over.
    var pad = window.matchMedia("(max-width: 560px)").matches ? 16 : 24;
    var fw = frame.clientWidth;
    var fh = frame.clientHeight;
    if (fw <= 0 || fh <= 0) return;
    // A small diagram grows a little to fill the larger frame, as far as 1.4x.
    view.scale = Math.min(1.4, (fw - pad * 2) / size.w, (fh - pad * 2) / size.h);
    view.x = (fw - size.w * view.scale) / 2;
    view.y = (fh - size.h * view.scale) / 2;
    view.fitted = true;
    frame.classList.add("is-live");
    apply();
  }

  function zoomAt(factor, cx, cy) {
    var next = Math.min(6, Math.max(0.1, view.scale * factor));
    view.x = cx - (cx - view.x) * (next / view.scale);
    view.y = cy - (cy - view.y) * (next / view.scale);
    view.scale = next;
    view.fitted = false;
    apply();
  }

  // Mermaid sizes its SVG to 100% of its parent; give it the drawing's own size
  // so the zoom works in diagram units.
  function place() {
    var svg = preview.querySelector("svg");
    if (svg && svg.viewBox && svg.viewBox.baseVal && svg.viewBox.baseVal.width) {
      svg.setAttribute("width", String(Math.ceil(svg.viewBox.baseVal.width)));
      svg.setAttribute("height", String(Math.ceil(svg.viewBox.baseVal.height)));
      svg.style.removeProperty("max-width");
    }
    if (view.fitted) fit(); else apply();
  }

  function say(text, isError) {
    status.textContent = text || "";
    status.classList.toggle("is-error", !!isError);
    renderError = false;
  }

  function store(value) {
    try { localStorage.setItem(DRAFT_KEY, value); } catch (e) { /* private window or blocked storage */ }
  }

  function stored() {
    try { return localStorage.getItem(DRAFT_KEY); } catch (e) { return null; }
  }

  function kindOf(text) {
    var first = (text.trim().split(/\s+/)[0] || "");
    var match = data.templates.filter(function (t) { return t.code.trim().split(/\s+/)[0] === first; })[0];
    return match ? match.kind : "";
  }

  function label(text) {
    var kind = kindOf(text);
    preview.setAttribute("aria-label", data.preview.replace("{kind}", kind).trim());
  }

  // Scripts load in order: the theme defines window.ThemeColors, Mermaid reads it.
  function load() {
    if (loading) return loading;
    loading = data.vendor.reduce(function (chain, src) {
      return chain.then(function () {
        return new Promise(function (resolve, reject) {
          var s = document.createElement("script");
          s.src = src;
          s.onload = resolve;
          s.onerror = reject;
          document.head.appendChild(s);
        });
      });
    }, Promise.resolve()).then(function () {
      var base = window.ThemeColors.getMermaidConfig(false);
      window.mermaid.initialize(Object.assign({}, base, data.config, { startOnLoad: false }));
      ready = true;
    });
    loading.catch(function () { loading = null; say(S.loadFailed, true); });
    return loading;
  }

  function render() {
    var text = code.value;
    var id = "mermaid-live-" + (++seq);
    var mine = seq;
    updateLines(0);
    if (!text.trim()) {
      preview.innerHTML = "";
      lastGood = "";
      say(S.empty);
      return Promise.resolve(false);
    }
    if (!ready) say(S.loading);
    return load().then(function () {
      return window.mermaid.render(id, text);
    }).then(function (out) {
      if (mine !== seq) return false;
      preview.innerHTML = out.svg;
      preview.classList.remove("is-stale");
      place();
      updateLines(0);
      lastGood = out.svg;
      lastGoodCode = text;
      label(text);
      if (renderError || status.textContent === S.loading) say("");
      if (edited && !rendered) { rendered = true; track("tool_render", { tool: "mermaid" }); }
      return true;
    }, function (error) {
      var stray = document.getElementById("d" + id);
      if (stray) stray.remove();
      if (mine !== seq || !ready) return false;
      preview.classList.add("is-stale");
      var message = String((error && (error.message || error.str)) || error || "");
      var at = /line (\d+)/i.exec(message);
      updateLines(at ? Number(at[1]) : 0);
      say(message.split("\n").slice(0, 4).join("\n"), true);
      renderError = true;
      return false;
    });
  }

  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(render, 250);
  }

  function hideUndo() {
    undoCode = null;
    undoButton.hidden = true;
  }

  function pick(id, quiet) {
    var t = byId[id];
    if (!t) return;
    var before = code.value;
    var known = data.templates.some(function (x) { return x.code === before; });
    code.value = t.code;
    chips.forEach(function (c) { c.setAttribute("aria-pressed", String(c.dataset.template === id)); });
    setSyntax(t);
    store(t.code);
    clearHash();
    if (!quiet && before.trim() && !known) {
      undoCode = before;
      undoButton.hidden = false;
      say(S.replaced);
    } else {
      hideUndo();
      if (!quiet) say("");
    }
    render();
  }

  function setSyntax(t) {
    if (t && t.syntax) {
      syntax.href = t.syntax;
      syntax.textContent = t.syntaxLabel;
      syntax.hidden = false;
    } else {
      syntax.hidden = true;
    }
  }

  function syncChips() {
    var match = data.templates.filter(function (t) { return t.code === code.value; })[0];
    chips.forEach(function (c) { c.setAttribute("aria-pressed", String(!!match && c.dataset.template === match.id)); });
  }

  function clearHash() {
    if (location.hash) history.replaceState(null, "", location.pathname + location.search);
  }

  // Share links: the code, deflated and in base64url, after #m=. A browser
  // without CompressionStream writes #b=, the code in plain base64url.
  function toBase64Url(bytes) {
    var bin = "";
    for (var i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }

  function fromBase64Url(text) {
    var b64 = text.replace(/-/g, "+").replace(/_/g, "/");
    while (b64.length % 4) b64 += "=";
    var bin = atob(b64);
    var bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
  }

  // Mermaid refuses text over 50 KB, so a link that inflates past 200 KB is
  // dropped before it can fill the tab's memory.
  var LIMIT = 200000;

  function streamed(bytes, Stream) {
    var reader = new Blob([bytes]).stream().pipeThrough(new Stream("deflate-raw")).getReader();
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

  function encode(text) {
    var bytes = new TextEncoder().encode(text);
    if (typeof CompressionStream === "function") {
      return streamed(bytes, CompressionStream).then(function (out) { return "m=" + toBase64Url(out); }, function () { return "b=" + toBase64Url(bytes); });
    }
    return Promise.resolve("b=" + toBase64Url(bytes));
  }

  function decode(hash) {
    var m = /^#([mb])=([A-Za-z0-9_-]+)$/.exec(hash);
    if (!m) return Promise.resolve(null);
    try {
      var bytes = fromBase64Url(m[2]);
      if (m[1] === "b") return Promise.resolve(bytes.length > LIMIT ? null : new TextDecoder().decode(bytes));
      if (typeof DecompressionStream !== "function") { say(S.oldBrowser, true); return Promise.resolve(null); }
      return streamed(bytes, DecompressionStream).then(function (out) { return new TextDecoder().decode(out); }, function () { return null; });
    } catch (e) {
      return Promise.resolve(null);
    }
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
      try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
      area.remove();
      ok ? resolve() : reject(new Error("copy"));
    });
  }

  function download(blob, name) {
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 4000);
  }

  // The drawn SVG for the code in the editor now, rendering it first when the
  // preview still shows the page's own picture or an older draft.
  function currentSvg() {
    var fresh = ready && lastGood && lastGoodCode === code.value && !preview.classList.contains("is-stale");
    return (fresh ? Promise.resolve(true) : render()).then(function (ok) {
      if (!ok) throw new Error("render");
      var svg = preview.querySelector("svg");
      if (!svg) throw new Error("render");
      return svg;
    });
  }

  function svgText(svg) {
    var copy = svg.cloneNode(true);
    var box = svg.viewBox && svg.viewBox.baseVal;
    copy.setAttribute("xmlns", "http://www.w3.org/2000/svg");
    if (box && box.width) {
      copy.setAttribute("width", String(Math.ceil(box.width)));
      copy.setAttribute("height", String(Math.ceil(box.height)));
      copy.style.removeProperty("max-width");
    }
    return { text: new XMLSerializer().serializeToString(copy), width: box ? box.width : svg.clientWidth, height: box ? box.height : svg.clientHeight };
  }

  function exportSvg() {
    return currentSvg().then(function (svg) {
      download(new Blob([svgText(svg).text], { type: "image/svg+xml" }), "mermaid-diagram.svg");
      track("tool_export", { tool: "mermaid", format: "svg" });
    });
  }

  function pngBlob() {
    return currentSvg().then(function (svg) {
      var out = svgText(svg);
      // Twice the size, capped so a huge diagram stays within canvas limits.
      var scale = Math.min(2, Math.sqrt(16e6 / Math.max(1, out.width * out.height)));
      var pad = 24;
      var url = URL.createObjectURL(new Blob([out.text], { type: "image/svg+xml" }));
      return new Promise(function (resolve, reject) {
        var img = new Image();
        img.onload = function () {
          var canvas = document.createElement("canvas");
          canvas.width = Math.ceil((out.width + pad * 2) * scale);
          canvas.height = Math.ceil((out.height + pad * 2) * scale);
          var ctx = canvas.getContext("2d");
          ctx.fillStyle = window.ThemeColors.getThemeColors(false).diagramBg;
          ctx.fillRect(0, 0, canvas.width, canvas.height);
          ctx.drawImage(img, pad * scale, pad * scale, out.width * scale, out.height * scale);
          URL.revokeObjectURL(url);
          canvas.toBlob(function (blob) { blob ? resolve(blob) : reject(new Error("png")); }, "image/png");
        };
        img.onerror = function () { URL.revokeObjectURL(url); reject(new Error("png")); };
        img.src = url;
      });
    });
  }

  function exportPng() {
    return pngBlob().then(function (blob) {
      download(blob, "mermaid-diagram.png");
      track("tool_export", { tool: "mermaid", format: "png" });
    });
  }

  // Safari wants the ClipboardItem made inside the click, holding a promise.
  function copyImage() {
    return navigator.clipboard.write([new ClipboardItem({ "image/png": pngBlob() })]).then(function () {
      say(S.copiedImage);
      track("tool_copy", { tool: "mermaid", kind: "image" });
    });
  }

  function copyMarkdown() {
    return copyText("```mermaid\n" + code.value.replace(/\s+$/, "") + "\n```\n").then(function () {
      say(S.copiedMarkdown);
      track("tool_copy", { tool: "mermaid", kind: "markdown" });
    });
  }

  function copyLink() {
    return encode(code.value).then(function (fragment) {
      // Copied, not written into the address bar: a history change would hand
      // the fragment to analytics as a new page view.
      return copyText(location.origin + location.pathname + "#" + fragment);
    }).then(function () {
      say(S.copiedLink);
      track("tool_copy", { tool: "mermaid", kind: "link" });
    });
  }

  var actions = { png: exportPng, image: copyImage, svg: exportSvg, markdown: copyMarkdown, link: copyLink };
  var failures = { png: S.exportFailed, image: S.copyFailed, svg: S.exportFailed, markdown: S.copyFailed, link: S.copyFailed };
  if (window.ClipboardItem && navigator.clipboard && navigator.clipboard.write && window.isSecureContext) {
    document.querySelector('[data-action="image"]').hidden = false;
  }

  document.querySelector(".tool-actions").addEventListener("click", function (e) {
    var button = e.target.closest("[data-action]");
    if (!button) return;
    var name = button.dataset.action;
    hideUndo();
    actions[name]().catch(function (error) {
      if (error && error.message === "render") return;
      say(failures[name], true);
    });
  });

  chips.forEach(function (chip) {
    chip.addEventListener("click", function () {
      edited = true;
      pick(chip.dataset.template, false);
    });
  });

  undoButton.addEventListener("click", function () {
    if (undoCode === null) return;
    code.value = undoCode;
    store(undoCode);
    hideUndo();
    syncChips();
    say("");
    render();
    code.focus();
  });

  code.addEventListener("focus", load, { once: true });
  code.addEventListener("scroll", syncScroll);

  // Tab indents by four spaces and Shift+Tab outdents, as in a code editor; after
  // Escape the next Tab leaves the editor, so keyboard users are never trapped.
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
    if (!e.shiftKey && start === end) {
      insert(start, end, "    ");
      return;
    }
    // Whole lines, as code editors do: a selection that ends at the start of a
    // line leaves that line alone, and Shift+Tab with no selection outdents the
    // line the caret is on.
    var last = end > start && value.charAt(end - 1) === "\n" ? end - 1 : end;
    var lineEnd = value.indexOf("\n", last);
    if (lineEnd < 0) lineEnd = value.length;
    var block = value.slice(lineStart, lineEnd);
    var changed = e.shiftKey
      ? block.replace(/^( {1,4}|\t)/gm, "")
      : block.replace(/^(?=.)/gm, "    ");
    if (changed === block) return;
    insert(lineStart, lineEnd, changed);
    if (start === end) {
      var caret = Math.max(lineStart, start - (block.length - changed.length));
      code.setSelectionRange(caret, caret);
    } else {
      code.setSelectionRange(lineStart, lineStart + changed.length);
    }
  });

  // execCommand keeps the browser's own undo stack; setRangeText is the fallback.
  function insert(start, end, text) {
    code.setSelectionRange(start, end);
    var ok = false;
    try { ok = document.execCommand("insertText", false, text); } catch (err) { ok = false; }
    if (!ok) {
      code.setRangeText(text, start, end, "end");
      code.dispatchEvent(new Event("input", { bubbles: true }));
    }
  }

  frame.querySelector(".tool-zoom").addEventListener("click", function (e) {
    var button = e.target.closest("[data-zoom]");
    if (!button) return;
    var kind = button.dataset.zoom;
    if (kind === "fit") return fit();
    zoomAt(kind === "in" ? 1.25 : 0.8, frame.clientWidth / 2, frame.clientHeight / 2);
  });

  // Pinch on a trackpad arrives as a wheel event with ctrlKey; a plain wheel
  // still scrolls the page.
  frame.addEventListener("wheel", function (e) {
    if (!e.ctrlKey && !e.metaKey) return;
    e.preventDefault();
    var box = frame.getBoundingClientRect();
    zoomAt(Math.exp(-e.deltaY * 0.01), e.clientX - box.left, e.clientY - box.top);
  }, { passive: false });

  // Dragging pans only once zoomed, so a finger on a fitted diagram scrolls the page.
  var drag = null;
  frame.addEventListener("pointerdown", function (e) {
    if (view.fitted || e.button !== 0 || e.target.closest(".tool-zoom")) return;
    drag = { id: e.pointerId, x: e.clientX - view.x, y: e.clientY - view.y };
    frame.setPointerCapture(e.pointerId);
    frame.classList.add("is-dragging");
  });
  frame.addEventListener("pointermove", function (e) {
    if (!drag || e.pointerId !== drag.id) return;
    view.x = e.clientX - drag.x;
    view.y = e.clientY - drag.y;
    apply();
  });
  function endDrag(e) {
    if (!drag || e.pointerId !== drag.id) return;
    drag = null;
    frame.classList.remove("is-dragging");
  }
  frame.addEventListener("pointerup", endDrag);
  frame.addEventListener("pointercancel", endDrag);

  if (window.ResizeObserver) new ResizeObserver(function () { if (view.fitted) fit(); }).observe(frame);
  var firstImage = preview.querySelector("img");
  if (firstImage) fit();

  code.addEventListener("input", function () {
    edited = true;
    updateLines(0);
    hideUndo();
    clearHash();
    store(code.value);
    syncChips();
    schedule();
  });

  // A shared link opens its diagram; otherwise the reader's last draft returns.
  function start() {
    decode(location.hash).then(function (shared) {
      var text = shared;
      if (text === null) {
        var draft = stored();
        if (draft && draft !== code.value) text = draft;
      }
      if (text === null || text === code.value) return;
      code.value = text;
      syncChips();
      setSyntax(data.templates.filter(function (t) { return t.code === text; })[0]);
      preview.classList.add("is-stale");
      render();
    });
  }

  function idleLoad() {
    var go = function () { load(); };
    window.requestIdleCallback ? requestIdleCallback(go, { timeout: 4000 }) : setTimeout(go, 1500);
  }

  function arm() {
    start();
    document.readyState === "complete" ? idleLoad() : addEventListener("load", idleLoad, { once: true });
  }

  // A link pasted into the address bar of an open editor only changes the hash.
  addEventListener("hashchange", function () {
    decode(location.hash).then(function (shared) {
      if (shared === null || shared === code.value) return;
      code.value = shared;
      store(shared);
      hideUndo();
      syncChips();
      setSyntax(data.templates.filter(function (t) { return t.code === shared; })[0]);
      preview.classList.add("is-stale");
      render();
    });
  });

  document.prerendering ? document.addEventListener("prerenderingchange", arm, { once: true }) : arm();
})();
