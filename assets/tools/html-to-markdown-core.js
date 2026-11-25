// A port of MiaoYan's HtmlToMarkdown (Helpers/HtmlToMarkdown.swift), what the
// app does with rich text pasted into a note, so this page turns a pasted web
// page, a Word document or a Google Doc into the Markdown MiaoYan would write.
// scripts/check-html-to-markdown.mjs runs it against the compiled Swift.
// The app parses with Foundation's HTML tidy and this with the browser's
// DOMParser; both build the same tree for well-formed HTML, which is what a
// clipboard carries. Like tidy, link and image addresses get their spaces and
// non-ASCII characters percent-encoded, so a path with a space stays one
// Markdown link. Two things tidy does are bugs this page leaves out, and
// convert(html, { tidy: true }) puts them back so the check can still compare
// byte for byte: tidy is HTML4 and does not know <figure> and <figcaption>,
// so an image and its caption run together as "![a](x.png)caption", and it
// keeps a comment's text, so a clipboard's <!--EndFragment--> lands in the
// note.
// Before converting, the page also reads three shapes the app does not
// (prepare below): Google Docs wraps a whole copy in one <b> and writes bold
// and italic as span styles, Word writes some of them as styles too, and
// Word's own lists arrive as paragraphs with a "·" in front.
(function (root) {
  "use strict";

  var DROPPED = { script: 1, style: 1, head: 1, meta: 1, link: 1, title: 1, svg: 1, button: 1, nav: 1 };
  var BLOCK = {
    p: 1, div: 1, section: 1, article: 1, main: 1, header: 1, footer: 1, figure: 1, figcaption: 1,
    h1: 1, h2: 1, h3: 1, h4: 1, h5: 1, h6: 1, ul: 1, ol: 1, li: 1, blockquote: 1, pre: 1, table: 1, hr: 1, details: 1, summary: 1
  };
  var STRUCTURE = /<(h[1-6]|table|ul|ol|blockquote|pre)[\s>]/i;
  var BR = "\u2028";
  // Character.isWhitespace is Unicode's White_Space; Foundation's
  // .whitespacesAndNewlines also holds U+200B; .whitespaces is Zs and tab.
  var IS_SPACE = /^\p{White_Space}$/u;
  var TRIM = /^[\p{White_Space}\u200B]+|[\p{White_Space}\u200B]+$/gu;
  var TRIM_LINE = /^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu;

  var tidy = false;

  function name(node) {
    return node.nodeType === 1 ? node.localName.toLowerCase() : null;
  }
  function kids(node) {
    return Array.prototype.slice.call(node.childNodes);
  }
  function trim(s) { return s.replace(TRIM, ""); }

  function text(node) {
    if (node.nodeType === 3 || node.nodeType === 4) return node.data;
    if (node.nodeType !== 1 && node.nodeType !== 11 && node.nodeType !== 9) return "";
    var out = "";
    kids(node).forEach(function (c) { out += text(c); });
    return out;
  }

  function normalize(s) {
    var out = "";
    var pending = false;
    for (var ch of s) {
      if (ch === BR) {
        out = out.replace(/ +$/, "") + "\n";
        pending = false;
      } else if (IS_SPACE.test(ch)) {
        pending = out.length > 0 && out.slice(-1) !== "\n";
      } else {
        if (pending) out += " ";
        pending = false;
        out += ch;
      }
    }
    return trim(out);
  }

  function blockChildren(node) {
    var blocks = [];
    var run = "";
    function flush() {
      var t = normalize(run);
      if (trim(t)) blocks.push(t);
      run = "";
    }
    kids(node).forEach(function (child) {
      var n = name(child);
      if (n && DROPPED[n]) return;
      if (n && BLOCK[n] && !(tidy && (n === "figure" || n === "figcaption"))) {
        flush();
        var b = block(child, n);
        if (b) blocks.push(b);
      } else {
        run += inline(child);
      }
    });
    flush();
    return blocks.join("\n\n");
  }

  function block(el, n) {
    switch (n) {
      case "h1": case "h2": case "h3": case "h4": case "h5": case "h6": {
        var t = normalize(inlineChildren(el)).replace(/\n/g, " ");
        return t ? "######".slice(0, +n.charAt(1)) + " " + t : "";
      }
      case "p": case "summary": case "figcaption":
        return normalize(inlineChildren(el));
      case "hr":
        return "---";
      case "blockquote": {
        var inner = blockChildren(el);
        if (!inner) return "";
        return inner.split("\n").map(function (l) { return l ? "> " + l : ">"; }).join("\n");
      }
      case "pre":
        return pre(el);
      case "ul": case "ol":
        return list(el, n === "ol", "");
      case "table":
        return table(el);
      case "li":
        return "- " + normalize(inlineChildren(el));
      default:
        return blockChildren(el);
    }
  }

  function pre(el) {
    var host = el;
    kids(el).some(function (c) { if (name(c) === "code") { host = c; return true; } return false; });
    var cls = (host.getAttribute("class") || el.getAttribute("class") || "").split(/\s+/);
    var lang = "";
    for (var i = 0; i < cls.length; i++) {
      if (cls[i].indexOf("language-") === 0) { lang = cls[i].slice(9); break; }
    }
    var code = text(host).replace(/^[\n\r\u0085\u2028\u2029\u000B\u000C]+|[\n\r\u0085\u2028\u2029\u000B\u000C]+$/g, "");
    var fence = "```";
    while (code.indexOf(fence) >= 0) fence += "`";
    return fence + lang + "\n" + code + "\n" + fence;
  }

  function list(el, ordered, indent) {
    var lines = [];
    var counter = 1;
    kids(el).forEach(function (item) {
      if (name(item) !== "li") return;
      var marker = ordered ? counter + ". " : "- ";
      counter++;
      var inner = indent + " ".repeat(marker.length);
      var pieces = [];
      var run = "";
      function flush() {
        var t = normalize(run);
        if (t) pieces.push([false, t]);
        run = "";
      }
      kids(item).forEach(function (g) {
        var n = name(g);
        if (n && DROPPED[n]) return;
        if (n === "ul" || n === "ol") {
          flush();
          pieces.push([true, list(g, n === "ol", inner)]);
        } else if (n === "p" || n === "div") {
          run += " " + inlineChildren(g);
        } else if (n && BLOCK[n]) {
          var b = block(g, n);
          if (b) {
            flush();
            pieces.push([true, b.split("\n").map(function (l) { return inner + l; }).join("\n")]);
          }
        } else {
          run += inline(g);
        }
      });
      flush();
      if (pieces.length && !pieces[0][0]) {
        lines.push(indent + marker + pieces.shift()[1]);
      } else {
        lines.push(indent + marker.slice(0, -1));
      }
      pieces.forEach(function (p) {
        lines.push(p[0] ? p[1] : p[1].split("\n").map(function (l) { return inner + l; }).join("\n"));
      });
    });
    return lines.join("\n");
  }

  function table(el) {
    var rows = [];
    var headerCount = 0;
    function collect(node) {
      kids(node).forEach(function (c) {
        var n = name(c);
        if (n === "tr") {
          var cells = [];
          var header = false;
          kids(c).forEach(function (cell) {
            var cn = name(cell);
            if (cn !== "td" && cn !== "th") return;
            if (cn === "th") header = true;
            cells.push(normalize(inlineChildren(cell)).replace(/\|/g, "\\|").replace(/\n/g, " "));
          });
          if (cells.length) {
            if (header && !rows.length) headerCount = cells.length;
            rows.push(cells);
          }
        } else if (n === "thead" || n === "tbody" || n === "tfoot") {
          collect(c);
        }
      });
    }
    collect(el);
    if (!rows.length) return "";
    var columns = Math.max.apply(null, rows.map(function (r) { return r.length; }));
    if (!columns) return "";
    var lines = [];
    rows.forEach(function (row, i) {
      var cells = row.slice();
      while (cells.length < columns) cells.push("");
      lines.push("| " + cells.join(" | ") + " |");
      if (i === 0) lines.push("|" + " --- |".repeat(columns));
    });
    return lines.join("\n");
  }

  function inlineChildren(el) {
    var out = "";
    kids(el).forEach(function (c) { out += inline(c); });
    return out;
  }

  function address(s) {
    var out = "";
    for (var ch of s) out += ch === " " || ch.charCodeAt(0) > 0x7E ? encodeURIComponent(ch) : ch;
    return out;
  }

  function inline(node) {
    if (node.nodeType === 8) return tidy ? node.data : "";
    if (node.nodeType !== 1) return node.nodeType === 3 || node.nodeType === 4 ? node.data : "";
    var n = name(node);
    if (DROPPED[n]) return "";
    var inner;
    switch (n) {
      case "br":
        return BR;
      case "strong": case "b":
        inner = normalize(inlineChildren(node));
        return inner ? "**" + inner + "**" : "";
      case "em": case "i":
        inner = normalize(inlineChildren(node));
        return inner ? "*" + inner + "*" : "";
      case "del": case "s": case "strike":
        inner = normalize(inlineChildren(node));
        return inner ? "~~" + inner + "~~" : "";
      case "code": case "kbd": case "samp": {
        inner = text(node);
        if (!inner) return "";
        var d = inner.indexOf("`") >= 0 ? "``" : "`";
        var padded = inner.charAt(0) === "`" || inner.slice(-1) === "`" ? " " + inner + " " : inner;
        return d + padded + d;
      }
      case "li":
        inner = normalize(inlineChildren(node));
        return inner ? inner + " " : "";
      case "a": {
        inner = normalize(inlineChildren(node));
        var href = address(node.getAttribute("href") || "");
        if (!href || href.charAt(0) === "#") return inner;
        return inner ? "[" + inner + "](" + href + ")" : href;
      }
      case "img": {
        var src = address(node.getAttribute("src") || "");
        if (!src || src.indexOf("data:") === 0) return "";
        return "![" + (node.getAttribute("alt") || "") + "](" + src + ")";
      }
      default:
        return inlineChildren(node);
    }
  }

  // ---- What the page reads that tidy's app does not ----------------------------

  function style(el) { return (el.getAttribute("style") || "").toLowerCase(); }

  function unwrap(el) {
    while (el.firstChild) el.parentNode.insertBefore(el.firstChild, el);
    el.parentNode.removeChild(el);
  }

  function wrap(el, tag) {
    var w = el.ownerDocument.createElement(tag);
    while (el.firstChild) w.appendChild(el.firstChild);
    el.appendChild(w);
  }

  function inHeading(el) {
    for (var p = el.parentNode; p && p.nodeType === 1; p = p.parentNode) {
      if (/^h[1-6]$/.test(name(p))) return true;
    }
    return false;
  }

  var BOLD = /font-weight\s*:\s*(bold|bolder|[6-9]00)\b/;
  var NORMAL = /font-weight\s*:\s*(normal|[1-5]00)\b/;
  var ITALIC = /font-style\s*:\s*italic/;
  var STRIKE = /text-decoration(-line)?\s*:[^;]*line-through/;
  var WORD_LIST = /mso-list\s*:\s*l\d+\s+level(\d+)/;
  var ORDERED = /^[(\s]*(\d+|[a-z]|[ivxlc]+)[.)、]/i;

  // Word's lists: consecutive paragraphs styled mso-list, each starting with
  // its marker in a span styled mso-list:Ignore, become one nested list.
  function wordLists(doc) {
    var items = Array.prototype.filter.call(doc.querySelectorAll("p[style]"), function (p) {
      return WORD_LIST.test(style(p));
    });
    var done = [];
    items.forEach(function (p) {
      if (done.indexOf(p) >= 0) return;
      var group = [p];
      for (var n = p.nextElementSibling; n && items.indexOf(n) >= 0; n = n.nextElementSibling) group.push(n);
      done = done.concat(group);
      var stack = [];
      var top = null;
      group.forEach(function (q) {
        var level = +WORD_LIST.exec(style(q))[1];
        var marker = "";
        Array.prototype.slice.call(q.querySelectorAll("span[style]")).forEach(function (s) {
          if (/mso-list\s*:\s*ignore/.test(style(s))) { marker += s.textContent; s.parentNode.removeChild(s); }
        });
        var li = doc.createElement("li");
        while (q.firstChild) li.appendChild(q.firstChild);
        while (stack.length && stack[stack.length - 1].level > level) stack.pop();
        var cur = stack[stack.length - 1];
        if (!cur || cur.level < level) {
          var list = doc.createElement(ORDERED.test(marker) ? "ol" : "ul");
          if (cur) {
            var last = cur.list.lastElementChild || cur.list.appendChild(doc.createElement("li"));
            last.appendChild(list);
          } else {
            top = list;
          }
          cur = { level: level, list: list };
          stack.push(cur);
        }
        cur.list.appendChild(li);
      });
      p.parentNode.insertBefore(top, p);
      group.forEach(function (q) { q.parentNode.removeChild(q); });
    });
  }

  function prepare(doc) {
    wordLists(doc);
    Array.prototype.slice.call(doc.querySelectorAll("b, strong")).forEach(function (b) {
      if (/^docs-internal-guid/.test(b.id || "") || NORMAL.test(style(b))) unwrap(b);
    });
    Array.prototype.slice.call(doc.querySelectorAll("span[style]")).forEach(function (s) {
      var css = style(s);
      if (STRIKE.test(css)) wrap(s, "del");
      if (ITALIC.test(css)) wrap(s, "em");
      if (BOLD.test(css) && !inHeading(s)) wrap(s, "strong");
    });
  }

  function collapse(s) {
    var lines = [];
    var blank = 0;
    var fence = false;
    s.split("\n").forEach(function (line) {
      var t = line.replace(TRIM_LINE, "");
      if (t.indexOf("```") === 0) fence = !fence;
      if (!fence && !t) {
        blank++;
        if (blank === 1) lines.push("");
      } else {
        blank = 0;
        lines.push(line);
      }
    });
    return lines.join("\n");
  }

  function convert(html, options) {
    tidy = !!(options && options.tidy);
    var doc = typeof html === "string" ? new DOMParser().parseFromString(html, "text/html") : html;
    if (!tidy) prepare(doc);
    var body = doc.body || doc.documentElement || doc;
    return trim(collapse(blockChildren(body)));
  }

  var api = {
    convert: convert,
    prepare: prepare,
    hasStructure: function (html) { return STRUCTURE.test(html); }
  };
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.MiaoYanHtmlToMarkdown = api;
})(this);
