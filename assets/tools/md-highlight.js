// Markdown in a tool's editor, coloured as MiaoYan's own editor colours it
// (Helpers/MarkdownRuleHighlighter.swift and Theme in the app): headings in the
// title purple with their # marks quiet, list and quote marks quiet, italic in
// the title purple, bold, strikethrough and inline code in the HTML amber, link
// text in the link teal with its brackets and address quiet, fenced code in the
// plain code ink. The textarea keeps the text and the caret; its letters are
// transparent over a <pre> behind it that holds the same text with colour, set
// with the same classes so both wrap on the same characters.
(function () {
  "use strict";

  function esc(s) {
    return s.replace(/[&<>]/g, function (c) { return c === "&" ? "&amp;" : c === "<" ? "&lt;" : "&gt;"; });
  }
  function span(cls, s) { return s ? '<span class="md-' + cls + '">' + esc(s) + "</span>" : ""; }

  // One pass over a line's inline markup, earliest match first; code spans win
  // so a * inside backticks never pairs up, as in the app.
  var INLINE = /(`+)([\s\S]*?[^`])\1(?!`)|(!?)\[([^\]\n]*)\]\(([^)\s]*(?:\s+"[^"]*")?)\)|(\*\*|__)(?=\S)([\s\S]*?\S)\6|(~~)(?=\S)([\s\S]*?\S)~~|(\*|_)(?=[^\s*_])([^*_\n]*?[^\s*_])\10(?![*_\w])|(https?:\/\/[^\s<>()]+[^\s<>().,;:!?'"])/g;

  function inline(text) {
    var out = "";
    var at = 0;
    var m;
    INLINE.lastIndex = 0;
    while ((m = INLINE.exec(text))) {
      out += esc(text.slice(at, m.index));
      if (m[1]) out += span("code", m[0]);
      else if (m[4] !== undefined && m[5] !== undefined) {
        out += span("syn", m[3] + "[") + span("link", m[4]) + span("syn", "](" + m[5] + ")");
      } else if (m[6]) out += span("syn", m[6]) + span("bold", m[7]) + span("syn", m[6]);
      else if (m[8]) out += span("syn", "~~") + span("bold", m[9]) + span("syn", "~~");
      else if (m[10]) out += span("syn", m[10]) + span("italic", m[11]) + span("syn", m[10]);
      else if (m[12]) out += span("link", m[12]);
      else out += esc(m[0]);
      at = m.index + m[0].length;
    }
    return out + esc(text.slice(at));
  }

  var FENCE = /^ {0,3}(`{3,}|~{3,})/;

  function highlight(text) {
    var lines = text.split("\n");
    var fence = null;
    var html = lines.map(function (line) {
      var f = FENCE.exec(line);
      if (fence) {
        if (f && f[1].charAt(0) === fence.charAt(0) && f[1].length >= fence.length && !line.slice(f[0].length).trim()) fence = null;
        return span("block", line);
      }
      if (f) { fence = f[1]; return span("block", line); }
      var h = /^( {0,3}#{1,6})(\s.*|$)/.exec(line);
      if (h) return span("syn", h[1]) + span("title", h[2]);
      var q = /^ {0,3}>/.exec(line);
      if (q) return span("quote", line);
      var l = /^(\s*)([-*+]|\d{1,9}[.)])(\s+)(\[[ xX]\](?=\s))?/.exec(line);
      if (l) return esc(l[1]) + span("syn", l[2]) + esc(l[3]) + span("syn", l[4] || "") + inline(line.slice(l[0].length));
      return inline(line);
    });
    // Each source line in its own span, so a line's height after wrapping can
    // be read (lineTops). A trailing newline still needs a line box, or the
    // last line of a long text scrolls out of step with the textarea.
    return html.map(function (line) { return '<span class="md-line">' + line + "</span>"; }).join("\n") + "\n ";
  }

  function attach(code) {
    var box = document.createElement("div");
    box.className = "md-hl-box";
    var pre = document.createElement("pre");
    pre.className = code.className + " md-hl";
    pre.setAttribute("aria-hidden", "true");
    code.parentNode.insertBefore(box, code);
    box.appendChild(pre);
    box.appendChild(code);
    code.classList.add("md-hl-input");

    var frame = 0;
    function paint() {
      frame = 0;
      pre.innerHTML = highlight(code.value);
      pre.scrollTop = code.scrollTop;
    }
    function schedule() { if (!frame) frame = requestAnimationFrame(paint); }

    // Scripts set .value when a draft, a link or a file arrives, and that
    // fires no input event; repaint on those too.
    var own = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value");
    Object.defineProperty(code, "value", {
      configurable: true,
      get: function () { return own.get.call(this); },
      set: function (v) { own.set.call(this, v); schedule(); },
    });
    code.addEventListener("input", schedule);
    code.addEventListener("scroll", function () { pre.scrollTop = code.scrollTop; });
    paint();
    code._mdLineTops = function () {
      if (frame) { cancelAnimationFrame(frame); paint(); }
      var pad = parseFloat(getComputedStyle(pre).paddingTop) || 0;
      return Array.prototype.map.call(pre.children, function (line) { return line.offsetTop - pad; });
    };
  }

  // Where each source line of a highlighted textarea starts, in its scroll
  // coordinates (0 is the first line at the top), wrapping included.
  function lineTops(code) {
    return code._mdLineTops ? code._mdLineTops() : null;
  }

  window.MiaoYanHighlight = { attach: attach, highlight: highlight, lineTops: lineTops };
  Array.prototype.forEach.call(document.querySelectorAll("textarea[data-highlight]"), attach);
})();
