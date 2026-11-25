// The slides page on /tools/markdown-slides/ (scripts/build-tools.py): Markdown
// on the left, the deck MiaoYan's PPT mode draws on the right. The deck is its
// own page (assets/tools/ppt-deck.js) in a frame whose sandbox allows scripts
// but not this site's origin, since reveal.js has to run there and so would
// any HTML written into a slide; the two talk only by postMessage. Present
// gives that frame the screen, PDF prints a second copy laid out a slide a
// page. Nothing leaves the browser.
(function () {
  "use strict";
  var data = JSON.parse(document.getElementById("ppt-data").textContent);
  var S = data.strings;
  var tool = document.getElementById("ppt-tool");
  var code = document.getElementById("ppt-code");
  var frame = document.getElementById("ppt-preview");
  var frameBox = frame.parentNode;
  var status = document.getElementById("ppt-status");
  var countEl = document.getElementById("ppt-count");
  var fileInput = document.getElementById("ppt-file");
  var darkButton = document.getElementById("ppt-dark");

  var DRAFT_KEY = "miaoyan.markdown-slides.draft";
  var THEME_KEY = "miaoyan.markdown-slides.theme";
  var MAX_BYTES = 5e6;
  // reveal's own separator: a line of three hyphens between blank-free lines.
  var SEPARATOR = /\r?\n---\r?\n/g;
  var edited = false;
  var fileName = "";
  var timer = 0;
  var ready = false;
  var expecting = false;
  var shownSlide = -1;
  var printFrame = null;
  var theme = "white";

  function track(name, params) {
    if (typeof window.gtag === "function") window.gtag("event", name, params || {});
  }
  function say(text) { status.textContent = text || ""; }
  function fill(s, n) { return s.replace("{n}", n).replace("{name}", n); }

  try { if (localStorage.getItem(THEME_KEY) === "night") theme = "night"; } catch (e) { /* storage blocked */ }
  darkButton.setAttribute("aria-pressed", String(theme === "night"));

  // ---- Talking to the deck --------------------------------------------------------

  function send(win, msg) {
    msg.type = "miaoyan-slides";
    win.postMessage(msg, "*");
  }

  function title() {
    var h = /^#{1,6}[ \t]+(.+)$/m.exec(code.value);
    var name = fileName || (h ? h[1].replace(/[*_`~[\]()!]/g, "").trim() : "");
    return name.replace(/[\\/:*?"<>|\u0000-\u001F]+/g, " ").trim().slice(0, 80) || "slides";
  }

  // The slide the caret is on, counted as reveal splits the text.
  function caretSlide() {
    var caret = code.selectionStart;
    var before = code.value.slice(0, caret + 1);
    var n = 0;
    SEPARATOR.lastIndex = 0;
    var m;
    while ((m = SEPARATOR.exec(before))) { if (m.index < caret) n++; }
    return n;
  }

  function slideCount() {
    var n = 1;
    SEPARATOR.lastIndex = 0;
    while (SEPARATOR.exec(code.value)) n++;
    return n;
  }

  function render() {
    timer = 0;
    countEl.textContent = fill(slideCount() === 1 ? S.slide : S.slides, slideCount());
    if (!ready) return;
    shownSlide = caretSlide();
    send(frame.contentWindow, { markdown: code.value, slide: shownSlide, theme: theme, title: title() });
  }

  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(render, code.value.length > 1e5 ? 500 : 200);
  }

  function follow() {
    if (!ready || timer) return;
    var n = caretSlide();
    if (n === shownSlide) return;
    shownSlide = n;
    send(frame.contentWindow, { slide: n });
  }

  // A deck that loads anything but itself (a slide's HTML moving the frame)
  // is put back.
  function loadDeck() {
    expecting = true;
    frame.src = data.deck;
  }

  frame.addEventListener("load", function () {
    if (expecting) { expecting = false; return; }
    ready = false;
    loadDeck();
  });

  window.addEventListener("message", function (e) {
    var msg = e.data;
    if (!msg || msg.type !== "miaoyan-deck") return;
    if (e.source === frame.contentWindow) {
      if (msg.event === "ready" && !msg.printing) {
        ready = true;
        render();
      } else if (msg.event === "leave") {
        present(false);
      }
    } else if (printFrame && e.source === printFrame.contentWindow) {
      if (msg.event === "ready") send(printFrame.contentWindow, { markdown: code.value, theme: theme, title: title() });
      else if (msg.event === "printed") { dropPrint(); say(""); }
    }
  });

  loadDeck();

  // ---- Editing ---------------------------------------------------------------------

  function store() {
    try { localStorage.setItem(DRAFT_KEY, code.value); } catch (e) {
      try { localStorage.removeItem(DRAFT_KEY); } catch (e2) { /* storage blocked */ }
    }
  }

  code.addEventListener("input", function () {
    if (!edited) { edited = true; track("tool_render", { tool: "markdown-slides" }); }
    say("");
    store();
    schedule();
  });
  ["keyup", "click", "select"].forEach(function (name) { code.addEventListener(name, follow); });

  window.MiaoYanEditor.attach(code, { save: saveMarkdown });

  darkButton.addEventListener("click", function () {
    theme = theme === "night" ? "white" : "night";
    darkButton.setAttribute("aria-pressed", String(theme === "night"));
    try { localStorage.setItem(THEME_KEY, theme); } catch (e) { /* storage blocked */ }
    if (ready) send(frame.contentWindow, { theme: theme });
  });

  // ---- Files -----------------------------------------------------------------------

  function openFile(file) {
    if (file.size > MAX_BYTES || !/\.(md|markdown|mdown|mkd|txt)$/i.test(file.name)) { say(S.fileType); return; }
    file.text().then(function (text) {
      code.value = text;
      fileName = file.name.replace(/\.[^.]+$/, "");
      edited = true;
      code.setSelectionRange(0, 0);
      code.scrollTop = 0;
      store();
      render();
      say(fill(S.opened, file.name));
      track("tool_import", { tool: "markdown-slides", source: "file" });
    }, function () { say(S.fileType); });
  }

  fileInput.addEventListener("change", function () {
    if (fileInput.files && fileInput.files[0]) openFile(fileInput.files[0]);
    fileInput.value = "";
  });

  tool.addEventListener("dragover", function (e) {
    if (!e.dataTransfer || Array.prototype.indexOf.call(e.dataTransfer.types || [], "Files") < 0) return;
    e.preventDefault();
    tool.classList.add("is-drop");
  });
  tool.addEventListener("dragleave", function (e) {
    if (!tool.contains(e.relatedTarget)) tool.classList.remove("is-drop");
  });
  tool.addEventListener("drop", function (e) {
    tool.classList.remove("is-drop");
    var file = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
    if (!file) return;
    e.preventDefault();
    openFile(file);
  });

  // ---- Present, PDF, Markdown ------------------------------------------------------

  // The frame takes the screen where the browser has element full screen,
  // and the window where it does not (an iPhone), left with Escape either way.
  var presenting = false;
  function screenElement() { return document.fullscreenElement || document.webkitFullscreenElement || null; }

  function present(on) {
    if (on === presenting) return;
    presenting = on;
    document.documentElement.classList.toggle("is-ppt-presenting", on);
    frameBox.classList.toggle("is-presenting", on);
    if (ready) send(frame.contentWindow, { presenting: on });
    if (on) {
      var ask = frameBox.requestFullscreen || frameBox.webkitRequestFullscreen;
      if (ask) {
        try {
          var p = ask.call(frameBox);
          if (p && p.catch) p.catch(function () { /* the window is the screen then */ });
        } catch (e) { /* the window is the screen then */ }
      }
      frame.focus();
      if (ready) send(frame.contentWindow, { focus: true });
      track("tool_present", { tool: "markdown-slides" });
    } else if (screenElement()) {
      (document.exitFullscreen || document.webkitExitFullscreen).call(document);
    }
  }

  function onScreenChange() { if (!screenElement() && presenting) present(false); }
  document.addEventListener("fullscreenchange", onScreenChange);
  document.addEventListener("webkitfullscreenchange", onScreenChange);
  document.addEventListener("keydown", function (e) { if (e.key === "Escape" && presenting && !screenElement()) present(false); });

  function dropPrint() {
    if (printFrame) printFrame.remove();
    printFrame = null;
  }

  // A second deck, unseen at the deck's own size, prints itself once reveal
  // has laid it out a slide a page.
  function printPdf() {
    dropPrint();
    printFrame = document.createElement("iframe");
    printFrame.className = "ppt-print";
    printFrame.setAttribute("aria-hidden", "true");
    printFrame.tabIndex = -1;
    printFrame.setAttribute("sandbox", frame.getAttribute("sandbox"));
    printFrame.src = data.deck + (data.deck.indexOf("?") < 0 ? "?" : "&") + "print-pdf";
    document.body.appendChild(printFrame);
    say(S.printing);
    track("tool_export", { tool: "markdown-slides", format: "pdf" });
  }

  function download(blob, name) {
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
  }

  function saveMarkdown() {
    try {
      download(new Blob([code.value.replace(/\n?$/, "\n")], { type: "text/markdown;charset=utf-8" }), title() + ".md");
      track("tool_export", { tool: "markdown-slides", format: "md" });
    } catch (e) {
      say(S.exportFailed);
    }
  }

  tool.addEventListener("click", function (e) {
    var button = e.target.closest("[data-action]");
    if (!button) return;
    if (timer) { clearTimeout(timer); render(); }
    var action = button.getAttribute("data-action");
    if (action === "present") present(true);
    else if (action === "pdf") printPdf();
    else if (action === "md") saveMarkdown();
  });

  // ---- Start ---------------------------------------------------------------------

  try {
    var saved = localStorage.getItem(DRAFT_KEY);
    if (saved) { code.value = saved; edited = true; }
  } catch (e) { /* storage blocked */ }
  render();
})();
