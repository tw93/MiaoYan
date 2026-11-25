// Chinese typography cleaner page: the text on the left goes through
// typography-cleaner.js (a port of MiaoYan's Clean Typography) and the result
// on the right marks every place that changed.
(function () {
  "use strict";

  var data = JSON.parse(document.getElementById("typography-data").textContent);
  var S = data.strings;
  var DRAFT = "miaoyan.chinese-typography-cleaner.draft";
  var TEXT_FILES = { md: 1, markdown: 1, mdown: 1, mkd: 1, txt: 1 };
  var MAX_BYTES = 5 * 1024 * 1024;
  // A line pair longer than this is marked whole rather than diffed, and so is
  // every changed line once a render has diffed this many characters.
  var MAX_DIFF = 4000;
  var RENDER_BUDGET = 200000;
  var budget = 0;

  var tool = document.getElementById("typography-tool");
  var code = document.getElementById("typography-code");
  var result = document.getElementById("typography-result");
  var status = document.getElementById("typography-status");
  var fileInput = document.getElementById("typography-file");

  var cleaned = "";
  var fileName = "";
  // An opened file's line endings and byte order mark, given back on download:
  // the textarea keeps only LF.
  var fileCRLF = false;
  var fileBOM = false;
  var edited = false;
  var timer = 0;
  var segmenter = typeof Intl !== "undefined" && Intl.Segmenter ? new Intl.Segmenter("und", { granularity: "grapheme" }) : null;

  function track(name, params) {
    if (typeof window.gtag === "function") window.gtag("event", name, params || {});
  }

  function say(text) { status.textContent = text || ""; }

  function graphemes(s) {
    if (!segmenter) return Array.from(s);
    var out = [];
    var it = segmenter.segment(s)[Symbol.iterator]();
    for (var step = it.next(); !step.done; step = it.next()) out.push(step.value.segment);
    return out;
  }

  // ---- Diff ------------------------------------------------------------------------

  // Myers' diff over two short arrays, as a list of [op, item] with op "=",
  // "+" (only in b) or "-" (only in a); null when it would take too long.
  // V is indexed k + offset; round d keeps only the 2d + 1 diagonals it can
  // reach, so the trace grows with d squared, not with the line.
  function myers(a, b) {
    var n = a.length;
    var m = b.length;
    var limit = Math.min(n + m, 600);
    var offset = limit + 1;
    var v = new Int32Array(2 * offset + 1);
    var trace = [];
    for (var d = 0; d <= limit; d++) {
      trace.push(v.slice(offset - d - 1, offset + d + 2));
      for (var k = -d; k <= d; k += 2) {
        var x = (k === -d || (k !== d && v[offset + k - 1] < v[offset + k + 1])) ? v[offset + k + 1] : v[offset + k - 1] + 1;
        var y = x - k;
        while (x < n && y < m && a[x] === b[y]) { x++; y++; }
        v[offset + k] = x;
        if (x >= n && y >= m) return backtrack(trace, a, b, d);
      }
    }
    return null;
  }

  function backtrack(trace, a, b, dEnd) {
    var out = [];
    var x = a.length;
    var y = b.length;
    for (var d = dEnd; d > 0; d--) {
      // trace[d] starts at diagonal -d - 1.
      var row = trace[d];
      var at = function (k) { return row[k + d + 1]; };
      var k = x - y;
      var prevK = (k === -d || (k !== d && at(k - 1) < at(k + 1))) ? k + 1 : k - 1;
      var prevX = at(prevK);
      var prevY = prevX - prevK;
      while (x > prevX && y > prevY) { out.push(["=", b[y - 1]]); x--; y--; }
      if (x === prevX) out.push(["+", b[y - 1]]);
      else out.push(["-", a[x - 1]]);
      x = prevX;
      y = prevY;
    }
    while (x > 0 && y > 0) { out.push(["=", b[y - 1]]); x--; y--; }
    return out.reverse();
  }

  function esc(s) {
    return s.replace(/[&<>]/g, function (c) { return c === "&" ? "&amp;" : c === "<" ? "&lt;" : "&gt;"; });
  }

  // One changed line: kept text plain, new text marked, a removed space a thin
  // mark between its neighbours. Returns [html, places changed].
  function lineDiff(before, after) {
    var a = graphemes(before);
    var b = graphemes(after);
    var start = 0;
    while (start < a.length && start < b.length && a[start] === b[start]) start++;
    var endA = a.length;
    var endB = b.length;
    while (endA > start && endB > start && a[endA - 1] === b[endB - 1]) { endA--; endB--; }
    var head = esc(b.slice(0, start).join(""));
    var tail = esc(b.slice(endB).join(""));
    var midA = a.slice(start, endA);
    var midB = b.slice(start, endB);
    var size = midA.length + midB.length;
    var ops = size <= MAX_DIFF && size <= budget ? myers(midA, midB) : null;
    budget -= size;
    if (!ops) return [head + '<mark class="tc-add">' + esc(midB.join("")) + "</mark>" + tail, 1];
    // A lone space kept between two changes is one change to a reader: Myers
    // pairs the space a new one replaced with a space removed elsewhere.
    for (var s = 1; s < ops.length - 1; s++) {
      if (ops[s][0] === "=" && /^\s$/.test(ops[s][1]) && ops[s - 1][0] !== "=" && ops[s + 1][0] !== "=") {
        ops.splice(s, 1, ["-", ops[s][1]], ["+", ops[s][1]]);
        s++;
      }
    }
    var html = head;
    var places = 0;
    var run = null;
    var removed = false;
    // A removal next to an addition is a replacement and shows as the addition.
    function close() {
      if (run !== null) html += '<mark class="tc-add">' + esc(run) + "</mark>";
      else if (removed) html += '<span class="tc-del" aria-hidden="true"></span>';
      if (run !== null || removed) places++;
      run = null;
      removed = false;
    }
    for (var i = 0; i < ops.length; i++) {
      var op = ops[i];
      if (op[0] === "=") { close(); html += esc(op[1]); }
      else if (op[0] === "+") run = (run || "") + op[1];
      else removed = true;
    }
    close();
    return [html + tail, places];
  }

  var BLANK = /^[\p{White_Space}​]*$/u;

  // The cleaner keeps one output line per input line except for blank lines it
  // folds, so the two sides align by walking them together.
  function compare(before, after) {
    var a = before.split("\n");
    var b = after.split("\n");
    var html = [];
    var places = 0;
    var j = 0;
    var dropped = false;
    // Folded blank lines leave a mark at the end of the line kept above them.
    function foldMark() {
      places++;
      if (html.length) html[html.length - 1] += '<span class="tc-del tc-del-line" aria-hidden="true"></span>';
    }
    for (var i = 0; i < a.length; i++) {
      if (j < b.length && a[i] === b[j]) {
        if (dropped) { foldMark(); dropped = false; }
        html.push(esc(b[j]));
        j++;
      } else if (BLANK.test(a[i])) {
        dropped = true;
      } else if (j < b.length) {
        if (dropped) { foldMark(); dropped = false; }
        var d = lineDiff(a[i], b[j]);
        html.push(d[0]);
        places += d[1];
        j++;
      } else {
        return null;
      }
    }
    if (dropped) foldMark();
    for (; j < b.length; j++) { html.push('<mark class="tc-add">' + esc(b[j]) + "</mark>"); places++; }
    return { html: html.join("\n"), places: places };
  }

  // ---- Render ------------------------------------------------------------------------

  function render() {
    timer = 0;
    budget = RENDER_BUDGET;
    var text = code.value;
    cleaned = window.MiaoYanTypography.clean(text);
    var diff = text === cleaned ? { html: esc(text), places: 0 } : compare(text, cleaned);
    // A trailing newline needs a character after it to take up a line.
    result.innerHTML = (diff ? diff.html : esc(cleaned)) + "\n";
    if (!text.trim() || !diff) say("");
    else if (diff.places) say(diff.places === 1 && S.changedOne ? S.changedOne : S.changed.replace("{n}", diff.places));
    else say(S.clean);
    if (edited) store();
  }

  function schedule() {
    if (timer) clearTimeout(timer);
    // A long text cleans in about a second, so wait for a real pause.
    timer = setTimeout(render, code.value.length > 200000 ? 800 : 120);
  }

  function store() {
    // A text too big to store must not leave an older draft to come back.
    try { localStorage.setItem(DRAFT, code.value); } catch (e) {
      try { localStorage.removeItem(DRAFT); } catch (e2) { /* private mode */ }
    }
  }

  function restore() {
    try {
      var saved = localStorage.getItem(DRAFT);
      if (saved !== null) code.value = saved;
    } catch (e) { /* private mode */ }
  }

  code.addEventListener("input", function () {
    if (!edited) { edited = true; track("tool_render", { tool: "typography" }); }
    schedule();
  });

  // Scroll the result with the text, by proportion, since both wrap alike but
  // the result can be a few lines shorter.
  var syncing = null;
  function sync(from, to) {
    if (syncing && syncing !== from) return;
    syncing = from;
    var range = from.scrollHeight - from.clientHeight;
    to.scrollTop = range > 0 ? (from.scrollTop / range) * (to.scrollHeight - to.clientHeight) : 0;
    requestAnimationFrame(function () { syncing = null; });
  }
  code.addEventListener("scroll", function () { sync(code, result); });
  result.addEventListener("scroll", function () { sync(result, code); });

  // ---- Files -------------------------------------------------------------------------

  var opening = 0;

  function decode(buffer) {
    var text;
    try {
      text = new TextDecoder("utf-8", { fatal: true }).decode(buffer);
    } catch (e) {
      try { text = new TextDecoder("gb18030").decode(buffer); } catch (e2) { text = new TextDecoder("utf-8").decode(buffer); }
    }
    return text;
  }

  function openFile(file) {
    var ext = (file.name.split(".").pop() || "").toLowerCase();
    var mine = ++opening;
    if (!(ext in TEXT_FILES) || file.size > MAX_BYTES || !file.arrayBuffer) { say(S.fileType); return; }
    file.arrayBuffer().then(function (buffer) {
      if (mine !== opening) return;
      // TextDecoder drops a UTF-8 byte order mark, so read it from the bytes.
      var head = new Uint8Array(buffer, 0, Math.min(3, buffer.byteLength));
      fileBOM = head.length === 3 && head[0] === 0xef && head[1] === 0xbb && head[2] === 0xbf;
      var text = decode(buffer).replace(/^\ufeff/, "");
      fileCRLF = text.indexOf("\r\n") >= 0 && text.replace(/\r\n/g, "").indexOf("\n") < 0;
      code.value = text;
      fileName = file.name;
      edited = true;
      code.scrollTop = 0;
      render();
      say(S.opened.replace("{name}", function () { return file.name; }) + " " + status.textContent);
      track("tool_import", { tool: "typography", source: "file" });
    }, function () { if (mine === opening) say(S.fileType); });
  }

  fileInput.addEventListener("change", function () {
    if (fileInput.files[0]) openFile(fileInput.files[0]);
    fileInput.value = "";
  });

  tool.addEventListener("dragover", function (e) {
    if (e.dataTransfer && Array.prototype.indexOf.call(e.dataTransfer.types, "Files") >= 0) {
      e.preventDefault();
      tool.classList.add("is-drop");
    }
  });
  tool.addEventListener("dragleave", function (e) {
    if (!tool.contains(e.relatedTarget)) tool.classList.remove("is-drop");
  });
  tool.addEventListener("drop", function (e) {
    var file = e.dataTransfer && e.dataTransfer.files[0];
    tool.classList.remove("is-drop");
    if (!file) return;
    e.preventDefault();
    openFile(file);
  });

  // ---- Actions -----------------------------------------------------------------------

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

  function download() {
    try {
      var body = fileCRLF ? cleaned.replace(/\n/g, "\r\n") : cleaned;
      var blob = new Blob([(fileBOM ? "\ufeff" : "") + body], { type: "text/markdown;charset=utf-8" });
      var a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = fileName && /\.(md|markdown|mdown|mkd|txt)$/i.test(fileName) ? fileName : "note.md";
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
      track("tool_export", { tool: "typography", format: "md" });
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
      copyText(cleaned).then(function () {
        say(S.copied);
        track("tool_copy", { tool: "typography" });
      }, function () { say(S.copyFailed); });
    } else if (action === "download") {
      download();
    }
  });

  restore();
  render();
})();
