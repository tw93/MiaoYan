// Inside the slides page's deck (/tools/markdown-slides/deck.html), which the
// page frames with a sandbox that allows scripts but not the site's origin, so
// HTML written in a deck runs where it cannot reach miaoyan.app's storage. It
// does what MiaoYan's ppt.html does (Resources/DownView.bundle on the app's
// main branch): reveal.js 4.3.1 with its Markdown and highlight plugins, ---
// between slides, a <!-- key: value --> comment at the top read as reveal
// options, math shielded from Markdown first (Business/Markdown.swift's
// protectMarkdownMath) and drawn by KaTeX after. The page sends the Markdown
// with postMessage; with ?print-pdf in its address the deck lays itself out a
// slide a page and prints.
(function () {
  "use strict";

  var printing = /print-pdf/i.test(location.search);
  var slidesEl = document.querySelector(".reveal .slides");
  var theme = document.getElementById("theme");
  var started = null;
  var pending = null;
  var appliedOptions = "";

  // ---- Math shielding, after protectMarkdownMath -------------------------------
  // Math is written as numeric character references, which Markdown leaves
  // alone and the browser turns back into the formula's own text for KaTeX.

  var DELIMS = [["$$", "$$"], ["$", "$"], ["\\(", "\\)"], ["\\[", "\\]"]].map(function (d) {
    return [Array.from(d[0]), Array.from(d[1])];
  });

  function isWs(c) { return c !== undefined && /\s/.test(c); }
  function isBreak(c) { return c === "\n" || c === "\r"; }
  function isDigit(c) { return c !== undefined && c >= "0" && c <= "9"; }
  function isInlineDollar(d) { return d.length === 1 && d[0] === "$"; }

  function matches(d, s, i, mask) {
    if (i + d.length > s.length) return false;
    for (var k = 0; k < d.length; k++) if (mask[i + k] || s[i + k] !== d[k]) return false;
    return true;
  }

  function isEscaped(s, i) {
    var n = 0;
    for (var k = i - 1; k >= 0 && s[k] === "\\"; k--) n++;
    return n % 2 === 1;
  }

  // A price such as $5 or $1,200 is not math; $2+2$ is.
  function isCurrency(d, s, i) {
    if (!isInlineDollar(d)) return false;
    var c = i + 1;
    var digits = c;
    while (c < s.length && isDigit(s[c])) c++;
    if (c === digits) return false;
    if (c < s.length && (s[c] === "." || s[c] === ",")) {
      var frac = ++c;
      while (c < s.length && isDigit(s[c])) c++;
      if (c === frac) c--;
    }
    if (c >= s.length) return true;
    var next = s[c];
    if (/[0-9A-Za-z]/.test(next)) return false;
    if ("(*+-/<=>\\^_".indexOf(next) >= 0) return false;
    return next !== d[0];
  }

  function canOpen(d, s, i) {
    return !isInlineDollar(d) || (i + 1 < s.length && !isWs(s[i + 1]));
  }

  function canClose(d, s, i, start) {
    if (!isInlineDollar(d)) return true;
    if (i <= start || isWs(s[i - 1])) return false;
    return i + 1 >= s.length || !isDigit(s[i + 1]);
  }

  function startsBlankLine(s, i) {
    if (!isBreak(s[i])) return false;
    var c = i + 1;
    if (s[i] === "\r" && s[c] === "\n") c++;
    while (c < s.length && (s[c] === " " || s[c] === "\t")) c++;
    return c < s.length && isBreak(s[c]);
  }

  function findEnd(d, s, start, mask) {
    var i = start;
    var level = 0;
    while (i < s.length) {
      if (mask[i]) return -1;
      if (isInlineDollar(d) && startsBlankLine(s, i)) return -1;
      if (level <= 0 && matches(d, s, i, mask) && !isCurrency(d, s, i) && canClose(d, s, i, start)) return i;
      if (s[i] === "\\") i += Math.min(2, s.length - i);
      else { if (s[i] === "{") level++; else if (s[i] === "}") level--; i++; }
    }
    return -1;
  }

  // Code, where math is never looked for: fenced and indented blocks, read a
  // line at a time (the app asks cmark), inline code spans, and the HTML
  // elements KaTeX skips.
  var FENCE_OPEN = /^[ \t>]*(?:(?:[-*+]|\d{1,9}[.)])[ \t]+)?[ \t]*(`{3,}|~{3,})(.*)$/;
  var FENCE_CLOSE = /^[ \t>]*(`{3,}|~{3,})[ \t]*$/;
  var LIST_LINE = /^[ \t>]*(?:[-*+]|\d{1,9}[.)])[ \t]/;
  var IGNORED_HTML = /<(script|noscript|style|textarea|pre|code|option)\b[^>]*>[\s\S]*?<\/\1\s*>/gi;

  function codeMask(s, text) {
    var mask = new Array(s.length).fill(false);
    var lines = [];
    var from = 0;
    for (var i = 0; i <= s.length; i++) {
      if (i === s.length || s[i] === "\n") { lines.push([from, i + 1]); from = i + 1; }
    }
    var fence = null;
    var prevBlank = true;
    var prevIndented = false;
    var inList = false;
    lines.forEach(function (range) {
      var line = s.slice(range[0], range[1]).join("").replace(/\r?\n$/, "");
      var blank = !line.trim();
      var cover = false;
      var m;
      if (fence) {
        cover = true;
        m = FENCE_CLOSE.exec(line);
        if (m && m[1][0] === fence[0] && m[1].length >= fence.length) fence = null;
        prevIndented = false;
      } else if ((m = FENCE_OPEN.exec(line)) && !(m[1][0] === "`" && m[2].indexOf("`") >= 0)) {
        cover = true;
        fence = m[1];
        prevIndented = false;
      } else if (!blank && /^( {4}|\t)/.test(line) && (prevBlank || prevIndented) && !inList) {
        cover = true;
        prevIndented = true;
      } else if (!blank) {
        prevIndented = false;
        inList = LIST_LINE.test(line) || (inList && /^[ \t]/.test(line));
      }
      if (cover) for (var k = range[0]; k < Math.min(range[1], s.length); k++) mask[k] = true;
      prevBlank = blank;
    });

    var j = 0;
    while (j < s.length) {
      if (mask[j] || s[j] !== "`" || isEscaped(s, j)) { j++; continue; }
      var run = 0;
      while (s[j + run] === "`") run++;
      var c = j + run;
      var found = -1;
      while (c < s.length) {
        if (mask[c]) break;
        if (s[c] === "`") {
          var n = 0;
          while (s[c + n] === "`") n++;
          if (n === run) { found = c; break; }
          c += n;
        } else c++;
      }
      if (found < 0) { j += run; continue; }
      for (var q = j; q < found + run; q++) mask[q] = true;
      j = found + run;
    }

    // Regex offsets count UTF-16 units; the mask counts code points.
    var at = [];
    var u = 0;
    s.forEach(function (ch, idx) { at[u] = idx; u += ch.length; });
    at[u] = s.length;
    IGNORED_HTML.lastIndex = 0;
    var hit;
    while ((hit = IGNORED_HTML.exec(text))) {
      var a = at[hit.index];
      var b = at[hit.index + hit[0].length];
      if (a === undefined || b === undefined || a >= b || mask[a]) continue;
      for (var z = a; z < b; z++) mask[z] = true;
    }
    return mask;
  }

  function opensDollarMath(s, mask) {
    for (var i = 0; i < s.length; i++) {
      if (s[i] !== "$" || mask[i]) continue;
      for (var k = 0; k < 2; k++) {
        var d = DELIMS[k];
        if (matches(d[0], s, i, mask) && !isEscaped(s, i) && !isCurrency(d[0], s, i) && canOpen(d[0], s, i) &&
            findEnd(d[1], s, i + d[0].length, mask) >= 0) return true;
      }
    }
    return false;
  }

  var SKIP = '<span class="skip-math-dollar">&#36;</span>';

  // Inside the (...) of a [text](address) on the same line.
  function inLinkAddress(s, i) {
    for (var k = i - 1; k > 0 && s[k] !== "\n"; k--) {
      if (s[k] === ")" || s[k] === " ") return false;
      if (s[k] === "(" ) return s[k - 1] === "]";
    }
    return false;
  }

  function encode(chars) {
    return chars.map(function (ch) { return isBreak(ch) ? ch : "&#" + ch.codePointAt(0) + ";"; }).join("");
  }

  function protectMath(text) {
    if (text.indexOf("$") < 0 && text.indexOf("\\(") < 0 && text.indexOf("\\[") < 0) return text;
    var s = Array.from(text);
    var mask = codeMask(s, text);
    // \( and \[ count as math only in a deck that writes no $ math; beside it
    // they are Markdown escapes, as in \[1\].
    var brackets = text.indexOf("$") < 0 || !(text.indexOf("\\(") >= 0 || text.indexOf("\\[") >= 0) || !opensDollarMath(s, mask);
    var delims = brackets ? DELIMS : DELIMS.slice(0, 2);
    var out = "";
    var i = 0;
    var inTag = false;
    while (i < s.length) {
      // A dollar that opens no math, written \$ or not, goes in its own span:
      // KaTeX's auto-render pairs any two dollars in one run of text, so
      // "$5 and $10" or "$HOME and $PATH" would be set as a formula (the
      // app's slides do; its preview guards prices the same way). Not inside
      // a tag or a link's address, where a span would break them.
      if (!mask[i] && !inTag) {
        if (s[i] === "\\" && s[i + 1] === "$" && !mask[i + 1] && !isEscaped(s, i) && !inLinkAddress(s, i)) { out += SKIP; i += 2; continue; }
      }
      var d = null;
      if (!mask[i]) {
        for (var k = 0; k < delims.length; k++) {
          var L = delims[k][0];
          if (matches(L, s, i, mask) && !isEscaped(s, i) && !isCurrency(L, s, i) && canOpen(L, s, i)) { d = delims[k]; break; }
        }
      }
      var end = d ? findEnd(d[1], s, i + d[0].length, mask) : -1;
      if (end < 0) {
        if (!mask[i]) {
          if (s[i] === "<" && /[A-Za-z\/!]/.test(s[i + 1] || "")) inTag = true;
          else if (s[i] === ">") inTag = false;
        }
        out += s[i] === "$" && !mask[i] && !inTag && !inLinkAddress(s, i) ? SKIP : s[i];
        i++;
        continue;
      }
      out += encode(d[0]) + encode(s.slice(i + d[0].length, end)) + encode(d[1]);
      i = end + d[1].length;
    }
    return out;
  }

  // ---- Options, as ppt.html reads them -------------------------------------------

  function inlineOptions(text) {
    var lead = /^\s*/.exec(text)[0].length;
    if (text.slice(lead, lead + 4) !== "<!--") return { options: {}, text: text };
    var close = text.indexOf("-->", lead + 4);
    if (close < 0) return { options: {}, text: text };
    var options = {};
    text.slice(lead + 4, close).split("\n").map(function (l) { return l.trim(); })
      .filter(function (l) { return l && l.indexOf(":") >= 0; })
      .forEach(function (line) {
        var colon = line.indexOf(":");
        var key = line.slice(0, colon).trim();
        var value = line.slice(colon + 1).trim();
        if (!key) return;
        var v;
        if (value.charAt(0) === "[" && value.slice(-1) === "]") {
          v = value.slice(1, -1).split(",").map(function (x) { return x.trim(); }).filter(Boolean);
        } else {
          if ((value.charAt(0) === '"' && value.slice(-1) === '"') || (value.charAt(0) === "'" && value.slice(-1) === "'")) value = value.slice(1, -1);
          if (/^null$/i.test(value)) v = null;
          else if (/^undefined$/i.test(value)) v = undefined;
          else if (/^(true|false)$/i.test(value)) v = /^true$/i.test(value);
          else if (value !== "" && !isNaN(Number(value))) v = Number(value);
          else v = value;
        }
        var path = key.split(".");
        var at = options;
        path.forEach(function (seg, n) {
          if (n === path.length - 1) { at[seg] = v; return; }
          if (!at[seg] || typeof at[seg] !== "object") at[seg] = {};
          at = at[seg];
        });
      });
    return { options: options, text: (text.slice(0, lead) + text.slice(close + 3)).replace(/^\s+/, "") };
  }

  function merge(target, source) {
    Object.keys(source).forEach(function (k) {
      var v = source[k];
      if (Array.isArray(v)) target[k] = v.slice();
      else if (v && typeof v === "object") {
        if (!target[k] || typeof target[k] !== "object" || Array.isArray(target[k])) target[k] = {};
        merge(target[k], v);
      } else target[k] = v;
    });
    return target;
  }

  // ppt.html's defaults, with two changes for a page: the deck is a fixed
  // 1600 by 900 that reveal scales to its frame or the screen (the app's
  // 100% fills its own window), and the frame keeps no history or #/ address.
  var DEFAULTS = {
    width: 1600,
    height: 900,
    controls: true,
    progress: true,
    history: false,
    hash: false,
    transition: "slide",
    backgroundTransition: "none",
    center: false,
    pdfSeparateFragments: false,
    slideNumber: false,
    showSlideNumber: "all",
  };

  // ---- Building the deck ----------------------------------------------------------

  function section(text) {
    var sec = document.createElement("section");
    sec.setAttribute("data-markdown", "");
    var t = document.createElement("script");
    t.type = "text/template";
    t.textContent = text;
    sec.appendChild(t);
    slidesEl.replaceChildren(sec);
  }

  // A slide of one element is centred; one taller than three quarters of the
  // deck has less padding and scrolls (ppt.html's section-center and
  // section-option).
  function classify() {
    Array.prototype.forEach.call(slidesEl.querySelectorAll("section"), function (s) {
      if (s.querySelector("section")) return;
      if (s.childElementCount === 1) s.classList.add("section-center", "center");
    });
  }

  function fitCurrent() {
    var s = window.Reveal && Reveal.getCurrentSlide();
    if (!s || s.classList.contains("section-center") || s.classList.contains("section-option")) return;
    if (s.scrollHeight > 0.75 * DEFAULTS.height) s.classList.add("section-option");
  }

  function guardMhchem() {
    var k = window.katex;
    if (!k || k.__miaoyanMhchemGuarded || typeof k.render !== "function") return;
    k.__miaoyanMhchemGuarded = true;
    var render = k.render;
    k.render = function () {
      try { return render.apply(this, arguments); } catch (e) {
        if (Array.isArray(e) && typeof e[0] === "string" && (e[0].indexOf("Mhchem") === 0 || e[0] === "ExtraCloseMissingOpen") && typeof k.ParseError === "function") {
          throw new k.ParseError(e[1] || e[0]);
        }
        throw e;
      }
    };
  }

  function drawMath() {
    if (typeof window.renderMathInElement !== "function") return;
    guardMhchem();
    window.renderMathInElement(slidesEl, {
      delimiters: [
        { left: "$$", right: "$$", display: true },
        { left: "$", right: "$", display: false },
        { left: "\\(", right: "\\)", display: false },
        { left: "\\[", right: "\\]", display: true },
      ],
      ignoredTags: ["script", "noscript", "style", "textarea", "pre", "code"],
    });
  }

  // A web link opens a tab; anything else that would move the frame is held.
  document.addEventListener("click", function (e) {
    var a = e.target.closest && e.target.closest("a[href]");
    if (!a) return;
    var href = a.getAttribute("href");
    if (/^(https?:|mailto:)/i.test(href)) { a.target = "_blank"; a.rel = "noopener"; return; }
    if (href.charAt(0) === "#") return;
    e.preventDefault();
  }, true);
  document.addEventListener("submit", function (e) { e.preventDefault(); }, true);

  function prepare(text) {
    var parsed = inlineOptions(text.replace(/\r\n?/g, "\n"));
    return { options: parsed.options, text: protectMath(parsed.text) };
  }

  function start(msg) {
    var prepared = prepare(msg.markdown);
    appliedOptions = JSON.stringify(prepared.options);
    section(prepared.text);
    var options = merge(merge({}, DEFAULTS), prepared.options);
    options.highlight = {
      highlightOnLoad: true,
      lineNumbers: true,
      beforeHighlight: function (hljs) {
        hljs.configure({ noHighlightRe: /^(no-?highlight|mermaid|plantuml|markmap)$/i });
      },
    };
    options.plugins = [window.RevealMarkdown, window.RevealHighlight];
    started = Reveal.initialize(options).then(function () {
      classify();
      drawMath();
      Reveal.layout();
      if (msg.slide) Reveal.slide(msg.slide, 0);
      fitCurrent();
      Reveal.on("slidechanged", function (e) {
        fitCurrent();
        tell({ event: "slide", h: e.indexh });
      });
    });
    if (printing) {
      window.addEventListener("afterprint", function () { tell({ event: "printed" }); });
      Reveal.on("pdf-ready", function () { setTimeout(function () { window.print(); }, 100); });
    }
  }

  function update(msg) {
    var prepared = prepare(msg.markdown);
    var key = JSON.stringify(prepared.options);
    if (key !== appliedOptions) {
      appliedOptions = key;
      Reveal.configure(merge(merge({}, DEFAULTS), prepared.options));
    }
    var now = Reveal.getIndices();
    section(prepared.text);
    var md = Reveal.getPlugin("markdown");
    var hl = Reveal.getPlugin("highlight");
    return md.processSlides(Reveal.getRevealElement()).then(function () {
      md.convertSlides();
      Array.prototype.forEach.call(slidesEl.querySelectorAll("pre code"), function (block) { hl.highlightBlock(block); });
      classify();
      drawMath();
      Reveal.sync();
      if (msg.slide === undefined || msg.slide === now.h) Reveal.slide(now.h, 0, now.f);
      else Reveal.slide(msg.slide, 0);
      Reveal.layout();
      fitCurrent();
    });
  }

  function tell(data) {
    data.type = "miaoyan-deck";
    window.parent.postMessage(data, "*");
  }

  function setTheme(name) {
    var file = name === "night" ? "night.css" : "white.css";
    if (theme.getAttribute("href").indexOf(file) < 0) theme.setAttribute("href", theme.getAttribute("data-" + (name === "night" ? "night" : "white")));
    document.documentElement.style.colorScheme = name === "night" ? "dark" : "light";
  }

  var busy = false;
  function drain() {
    if (busy || !pending) return;
    var msg = pending;
    pending = null;
    if (!started) { start(msg); return; }
    busy = true;
    started.then(function () { return update(msg); }).catch(function () { /* the next text tries again */ }).then(function () {
      busy = false;
      drain();
    });
  }

  window.addEventListener("message", function (e) {
    if (e.source !== window.parent || !e.data || e.data.type !== "miaoyan-slides") return;
    var msg = e.data;
    if (msg.title) document.title = msg.title;
    if (msg.theme) setTheme(msg.theme);
    if (typeof msg.markdown === "string") {
      if (printing && started) return;
      pending = msg;
      drain();
    } else if (typeof msg.slide === "number" && started) {
      started.then(function () {
        if (Reveal.getIndices().h !== msg.slide) Reveal.slide(msg.slide, 0);
      });
    } else if (msg.focus) {
      window.focus();
    }
  });

  // Escape leaves presenting where the page is the deck's whole screen
  // without the browser's full screen (an iPhone), before reveal opens its
  // overview with it.
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && document.documentElement.classList.contains("is-presenting")) {
      e.stopPropagation();
      e.preventDefault();
      tell({ event: "leave" });
    }
  }, true);
  window.addEventListener("message", function (e) {
    if (e.source !== window.parent || !e.data || e.data.type !== "miaoyan-slides" || typeof e.data.presenting !== "boolean") return;
    document.documentElement.classList.toggle("is-presenting", e.data.presenting);
  });

  tell({ event: "ready", printing: printing });
})();
