// The editing keys of every tool's Markdown textarea, as MiaoYan's editors
// have them: Tab and Shift+Tab indent, Command-B, -I, -K, -E and Shift-
// Command-E format, Return carries a list or a quote on, Command-S saves
// through the page's own save. Used by the Markdown viewer, Markdown to Word
// and the slides page.
(function () {
  "use strict";

  function attach(code, options) {
    var save = (options && options.save) || function () {};

    // Tab indents by four spaces, Shift+Tab outdents; after Escape the next Tab
    // leaves the editor.
    var tabLeaves = false;
    code.addEventListener("keydown", function (e) {
      if (e.key === "Escape") { tabLeaves = true; return; }
      if (e.key === "Shift" || e.key === "Control" || e.key === "Alt" || e.key === "Meta") return;
      if (e.isComposing || e.keyCode === 229) return;
      if ((e.metaKey || e.ctrlKey) && !e.altKey && shortcut(e)) { e.preventDefault(); tabLeaves = false; return; }
      if (e.key === "Enter" && !e.metaKey && !e.ctrlKey && !e.altKey && !e.shiftKey && continueList()) { e.preventDefault(); tabLeaves = false; return; }
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
      try { ok = document.execCommand(text ? "insertText" : "delete", false, text); } catch (err) { ok = false; }
      if (!ok) {
        code.setRangeText(text, start, end, "end");
        code.dispatchEvent(new Event("input", { bubbles: true }));
      }
    }

    // MiaoYan's formatting keys (its Format menu): Command-B bold, -I italic,
    // -K link, -E inline code, Shift-Command-E code block, with the caret where
    // the app leaves it (Helpers/TextFormatter.swift); Command-S saves the
    // Markdown. MiaoYan's Command-T task belongs to the browser here.
    function wrap(mark) {
      var start = code.selectionStart;
      var end = code.selectionEnd;
      var sel = code.value.slice(start, end);
      insert(start, end, mark + sel + mark);
      var caret = sel ? end + 2 * mark.length : start + mark.length;
      code.setSelectionRange(caret, caret);
    }

    function shortcut(e) {
      var start = code.selectionStart;
      var end = code.selectionEnd;
      var sel = code.value.slice(start, end);
      var key = (e.key || "").toLowerCase();
      var caret;
      if (e.shiftKey) {
        if (key !== "e") return false;
        insert(start, end, "```\n" + sel + (sel && sel.slice(-1) !== "\n" ? "\n" : sel ? "" : "\n") + "```" + (sel ? "\n" : ""));
        caret = start + 3;
      } else if (key === "b") { wrap("**"); return true; }
      else if (key === "i") { wrap("*"); return true; }
      else if (key === "e") { wrap("`"); return true; }
      else if (key === "k") {
        insert(start, end, "[" + sel + "]()");
        caret = sel ? end + 3 : start + 1;
      } else if (key === "s") {
        save();
        return true;
      } else {
        return false;
      }
      code.setSelectionRange(caret, caret);
      return true;
    }

    // Return at the end of a list or quote line writes the next item's marker
    // or the quote's >, and Return on an empty item or quote line ends it, as
    // MiaoYan's editors do (MiaoYanCore ListContinuation); not inside a fence.
    var ITEM = /^([ \t]*(?:>[ \t]*)*)([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\][ \t]+|\[[ xX]\]$)?(.*)$/;
    var QUOTE = /^([ \t]*(?:>[ \t]*)*>[ \t]+)(.*)$/;
    var RULE = /^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$/;

    function inFence(value, target) {
      if (value.indexOf("```") < 0) return false;
      var lines = value.split("\n");
      var opened = -1;
      var inside = false;
      for (var i = 0; i < lines.length; i++) {
        if (opened >= 0) {
          if (/^```[ \t]*$/.test(lines[i])) {
            inside = opened < target && target <= i;
            opened = -1;
            if (inside || i >= target) break;
          }
          continue;
        }
        if (lines[i].slice(0, 3) === "```") opened = i;
        if (i >= target) break;
      }
      return inside;
    }

    function continueList() {
      var value = code.value;
      var caret = code.selectionStart;
      if (caret !== code.selectionEnd) return false;
      var lineStart = value.lastIndexOf("\n", caret - 1) + 1;
      var lineEnd = value.indexOf("\n", caret);
      if (lineEnd < 0) lineEnd = value.length;
      if (caret !== lineEnd) return false;
      var line = value.slice(lineStart, lineEnd);
      if (inFence(value, value.slice(0, lineStart).split("\n").length - 1)) return false;
      var m = RULE.test(line) ? null : ITEM.exec(line);
      var prefix;
      if (m) {
        if (!m[4].trim()) { insert(lineStart, lineEnd, ""); return true; }
        var n = /^(\d+)([.)])$/.exec(m[2]);
        prefix = m[1] + (n ? (+n[1] + 1) + n[2] : m[2]) + " " + (m[3] ? "[ ] " : "");
      } else if ((m = QUOTE.exec(line))) {
        if (!m[2].trim()) { insert(lineStart, lineEnd, ""); return true; }
        prefix = m[1];
      } else {
        return false;
      }
      insert(caret, caret, "\n" + prefix);
      return true;
    }
  }

  window.MiaoYanEditor = { attach: attach };
})();
