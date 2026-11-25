// HTML to Markdown page: rich text pasted, dropped or opened (a web page, a
// Word document or a Google Doc, an .html or .docx file) shows on the
// left as it looked, and html-to-markdown-core.js (a port of MiaoYan's paste
// conversion) writes it as Markdown on the right. The left pane only ever
// holds a copy rebuilt from an allowlist of tags and attributes, so pasted
// scripts, handlers and frames never reach the page; the Markdown is read
// from that copy, so editing either side is what gets converted.
(function () {
  "use strict";

  var data = JSON.parse(document.getElementById("h2m-data").textContent);
  var S = data.strings;
  var H = window.MiaoYanHtmlToMarkdown;
  var MAX_BYTES = 20 * 1024 * 1024;

  var tool = document.getElementById("h2m-tool");
  var source = document.getElementById("h2m-source");
  var code = document.getElementById("h2m-code");
  var status = document.getElementById("h2m-status");
  var fileInput = document.getElementById("h2m-file");

  var edited = false;
  var fileName = "";
  var timer = 0;
  var mammoth = null;

  function track(name, params) {
    if (typeof window.gtag === "function") window.gtag("event", name, params || {});
  }
  function say(text) { status.textContent = text || ""; }
  function fill(s, n) { return s.replace("{n}", n).replace("{name}", n); }

  // ---- The safe copy ---------------------------------------------------------------

  var KEEP = {};
  ("p div section article main header footer figure figcaption h1 h2 h3 h4 h5 h6 ul ol li blockquote pre code kbd samp " +
    "table thead tbody tfoot tr th td hr details summary br strong b em i del s strike a img sup sub").split(" ")
    .forEach(function (t) { KEEP[t] = 1; });
  // Dropped with everything inside; the converter drops the first nine too.
  var DROP = {};
  ("script style head meta link title svg button nav iframe frame frameset object embed noscript template form " +
    "input select textarea option canvas audio video math").split(" ").forEach(function (t) { DROP[t] = 1; });
  var SAFE_URL = /^(https?:|mailto:|#|\/|\.{0,2}\/|[^:]*$)/i;

  // Returns the copy and how many images could not come along (embedded or
  // local ones, which a Markdown file cannot hold).
  function sanitize(from) {
    var doc = source.ownerDocument;
    var lost = 0;
    function walk(node, into) {
      Array.prototype.forEach.call(node.childNodes, function (c) {
        if (c.nodeType === 3) { into.appendChild(doc.createTextNode(c.data)); return; }
        if (c.nodeType !== 1) return;
        var t = c.localName.toLowerCase();
        if (DROP[t]) return;
        if (!KEEP[t]) { walk(c, into); return; }
        var el = doc.createElement(t);
        if (t === "a") {
          var href = (c.getAttribute("href") || "").trim();
          if (href && SAFE_URL.test(href)) el.setAttribute("href", href);
        } else if (t === "img") {
          var src = (c.getAttribute("src") || "").trim();
          if (!src || !/^(https?:|\/|\.{0,2}\/|[^:]*$)/i.test(src)) { lost++; return; }
          el.setAttribute("src", src);
          if (c.getAttribute("alt")) el.setAttribute("alt", c.getAttribute("alt"));
          el.setAttribute("loading", "lazy");
          el.setAttribute("referrerpolicy", "no-referrer");
        } else if (t === "pre" || t === "code") {
          var lang = (c.getAttribute("class") || "").split(/\s+/).filter(function (k) { return k.indexOf("language-") === 0; })[0];
          if (lang) el.setAttribute("class", lang);
        } else if ((t === "td" || t === "th") && c.getAttribute("colspan")) {
          el.setAttribute("colspan", String(parseInt(c.getAttribute("colspan"), 10) || 1));
        }
        walk(c, el);
        into.appendChild(el);
      });
    }
    var frag = doc.createDocumentFragment();
    walk(from, frag);
    return { frag: frag, lost: lost };
  }

  function fromHtml(html) {
    var doc = new DOMParser().parseFromString(html, "text/html");
    H.prepare(doc);
    return sanitize(doc.body || doc.documentElement);
  }

  function fromText(text) {
    var doc = source.ownerDocument;
    var frag = doc.createDocumentFragment();
    text.replace(/\r\n?/g, "\n").split(/\n{2,}/).forEach(function (block) {
      if (!block.trim()) return;
      var p = doc.createElement("p");
      block.split("\n").forEach(function (line, i) {
        if (i) p.appendChild(doc.createElement("br"));
        p.appendChild(doc.createTextNode(line));
      });
      frag.appendChild(p);
    });
    return { frag: frag, lost: 0 };
  }

  // ---- Putting content in ----------------------------------------------------------

  function insideSource(range) {
    return range && source.contains(range.commonAncestorContainer);
  }

  // The first paste replaces the example; later ones go where the caret is.
  function put(copy, replace) {
    var sel = window.getSelection();
    var range = sel && sel.rangeCount ? sel.getRangeAt(0) : null;
    if (replace || !edited || !insideSource(range)) {
      source.replaceChildren(copy.frag);
      source.scrollTop = 0;
    } else {
      range.deleteContents();
      var last = copy.frag.lastChild;
      range.insertNode(copy.frag);
      if (last) {
        range.setStartAfter(last);
        range.collapse(true);
        sel.removeAllRanges();
        sel.addRange(range);
      }
    }
    edited = true;
    render();
    return copy.lost;
  }

  // A Chinese sentence runs on after its 。 with no space.
  function withLost(text, lost) {
    if (!lost) return text;
    return text + (/[。！？]$/.test(text) ? "" : " ") + (lost === 1 ? S.imageLost : fill(S.imagesLost, lost));
  }

  function pasteData(dt, replace) {
    var html = dt.getData("text/html");
    var text = dt.getData("text/plain");
    if (!html && !text) return false;
    fileName = "";
    var lost = put(html ? fromHtml(html) : fromText(text), replace);
    say(withLost(S.converted, lost));
    track("tool_import", { tool: "html-to-markdown", source: html ? "paste" : "text" });
    return true;
  }

  source.addEventListener("paste", function (e) {
    if (!e.clipboardData) return;
    e.preventDefault();
    pasteData(e.clipboardData, false);
  });

  // ⌘V anywhere on the page outside a field lands here too, replacing.
  document.addEventListener("paste", function (e) {
    if (e.defaultPrevented || !e.clipboardData) return;
    var t = e.target;
    if (t && t.closest && t.closest("input, textarea, [contenteditable]")) return;
    if (pasteData(e.clipboardData, true)) e.preventDefault();
  });

  // Typing or deleting in the left pane converts again.
  source.addEventListener("input", function () {
    edited = true;
    clearTimeout(timer);
    timer = setTimeout(render, 150);
  });

  // ---- Files -----------------------------------------------------------------------

  function loadMammoth() {
    if (mammoth) return mammoth;
    mammoth = new Promise(function (resolve, reject) {
      var s = document.createElement("script");
      s.src = data.mammoth;
      s.onload = function () { window.mammoth ? resolve(window.mammoth) : reject(new Error("mammoth")); };
      s.onerror = function () { mammoth = null; reject(new Error("mammoth")); };
      document.head.appendChild(s);
    });
    return mammoth;
  }

  function openFile(file) {
    var ext = (file.name.split(".").pop() || "").toLowerCase();
    if (file.size > MAX_BYTES || !(ext === "docx" || ext === "html" || ext === "htm")) {
      say(S.fileType);
      return;
    }
    var base = file.name.replace(/\.[^.]+$/, "");
    if (ext === "docx") {
      say(S.reading);
      Promise.all([loadMammoth(), file.arrayBuffer()]).then(function (r) {
        return r[0].convertToHtml({ arrayBuffer: r[1] });
      }).then(function (out) {
        var lost = put(fromHtml(out.value), true);
        fileName = base;
        say(withLost(fill(S.opened, file.name), lost));
        track("tool_import", { tool: "html-to-markdown", source: "docx" });
      }, function () { say(S.docxFailed); });
    } else {
      file.text().then(function (html) {
        var lost = put(fromHtml(html), true);
        fileName = base;
        say(withLost(fill(S.opened, file.name), lost));
        track("tool_import", { tool: "html-to-markdown", source: "html" });
      }, function () { say(S.fileType); });
    }
  }

  fileInput.addEventListener("change", function () {
    if (fileInput.files && fileInput.files[0]) openFile(fileInput.files[0]);
    fileInput.value = "";
  });

  // A selection dragged within the page moves as the browser moves it; only
  // what comes from outside is converted.
  var dragging = false;
  document.addEventListener("dragstart", function () { dragging = true; });
  document.addEventListener("dragend", function () { dragging = false; });

  tool.addEventListener("dragover", function (e) {
    if (!e.dataTransfer || dragging) return;
    var types = Array.prototype.slice.call(e.dataTransfer.types || []);
    if (types.indexOf("Files") >= 0 || types.indexOf("text/html") >= 0) {
      e.preventDefault();
      tool.classList.add("is-drop");
    }
  });
  tool.addEventListener("dragleave", function (e) {
    if (!tool.contains(e.relatedTarget)) tool.classList.remove("is-drop");
  });
  tool.addEventListener("drop", function (e) {
    if (!e.dataTransfer || dragging) return;
    tool.classList.remove("is-drop");
    var file = e.dataTransfer.files && e.dataTransfer.files[0];
    if (file) {
      e.preventDefault();
      openFile(file);
    } else if (e.dataTransfer.getData("text/html")) {
      e.preventDefault();
      pasteData(e.dataTransfer, true);
    }
  });

  // ---- Markdown out ----------------------------------------------------------------

  function render() {
    timer = 0;
    code.value = H.convert(source);
    source.classList.toggle("is-empty", !source.textContent.trim() && !source.querySelector("img, hr"));
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) return navigator.clipboard.writeText(text);
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
      if (ok) resolve(); else reject(new Error("copy"));
    });
  }

  // Named after the opened file, or else the first heading.
  function downloadName() {
    var name = fileName;
    if (!name) {
      var h = /^#{1,6}[ \t]+(.+)$/m.exec(code.value);
      name = h ? h[1].replace(/[*_`~[\]()!]/g, "") : "";
    }
    name = name.replace(/[\\/:*?"<>|\u0000-\u001F]+/g, " ").trim().slice(0, 80);
    return (name || "note") + ".md";
  }

  function download() {
    try {
      var blob = new Blob([code.value.replace(/\n?$/, "\n")], { type: "text/markdown;charset=utf-8" });
      var a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = downloadName();
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
      track("tool_export", { tool: "html-to-markdown", format: "md" });
    } catch (e) {
      say(S.exportFailed);
    }
  }

  tool.addEventListener("click", function (e) {
    var button = e.target.closest("[data-action]");
    if (!button) return;
    if (timer) { clearTimeout(timer); render(); }
    var action = button.getAttribute("data-action");
    if (action === "copy") {
      copyText(code.value).then(function () {
        say(S.copied);
        track("tool_copy", { tool: "html-to-markdown" });
      }, function () { say(S.copyFailed); });
    } else if (action === "download") {
      download();
    }
  });

  render();
})();
