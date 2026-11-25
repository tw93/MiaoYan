// The markdown-it rules MiaoYan's pages share (the Markdown viewer, Markdown
// to Word and Markdown to image, and Learn Markdown): $ math as Pandoc reads
// it, and GitHub task boxes. Each page renders the math tokens its own way.
(function () {
  "use strict";

  // $...$ inline and $$...$$ blocks, kept away from emphasis and escapes so a
  // formula reaches KaTeX as written. An opening $ is followed by a non-space,
  // a closing one preceded by a non-space and not followed by a digit, as in
  // Pandoc, so "$5 and $6" stays text.
  // A $ is escaped when an odd number of backslashes sits before it, so the
  // TeX line break in $a\\$ still closes.
  function escaped(src, at) {
    var n = 0;
    while (at - 1 - n >= 0 && src.charCodeAt(at - 1 - n) === 0x5C) n++;
    return n % 2 === 1;
  }

  function mathInline(state, silent) {
    var src = state.src;
    var pos = state.pos;
    if (src.charCodeAt(pos) !== 0x24) return false;
    // $$...$$ inside a sentence is display math, as in Pandoc.
    var display = src.charCodeAt(pos + 1) === 0x24;
    var open = display ? 2 : 1;
    var first = src.charAt(pos + open);
    if (!first || /\s/.test(first)) return false;
    var end = pos + open;
    for (;;) {
      end = src.indexOf(display ? "$$" : "$", end);
      if (end < 0) return false;
      if (escaped(src, end)) { end++; continue; }
      break;
    }
    var content = src.slice(pos + open, end);
    if (/\s/.test(src.charAt(end - 1))) return false;
    if (!display && /[0-9]/.test(src.charAt(end + 1))) return false;
    // A backtick inside means the closing $ belongs to a code span.
    if (content.indexOf("`") >= 0) return false;
    if (!silent) {
      var token = state.push("math_inline", "math", 0);
      token.content = content;
      token.meta = { display: display };
    }
    state.pos = end + open;
    return true;
  }

  // A display block ends at the first line ending in $$ and never crosses a
  // blank line (Pandoc's rule). A start that found no end marks the lines up
  // to that blank line, so later starts in them give up at once: an unclosed
  // $$ on every line stays linear.
  function mathBlock(state, startLine, endLine, silent) {
    var pos = state.bMarks[startLine] + state.tShift[startLine];
    var max = state.eMarks[startLine];
    if (state.sCount[startLine] - state.blkIndent >= 4) return false;
    if (state.src.slice(pos, pos + 2) !== "$$") return false;
    var miss = state.env.mathMiss;
    if (miss && startLine > miss[0] && startLine < miss[1]) return false;
    var rest = state.src.slice(pos + 2, max).trim();
    var content = null;
    var last = startLine;
    if (rest.length >= 2 && rest.slice(-2) === "$$") {
      content = rest.slice(0, -2);
      // $$a$$ and $$b$$ on one line is two formulas in a paragraph.
      for (var at = content.indexOf("$$"); at >= 0; at = content.indexOf("$$", at + 1)) {
        if (!escaped(content, at)) return false;
      }
    } else {
      // $$a$$ and $$b$$. followed by more text opens no block either.
      for (var open = rest.indexOf("$$"); open >= 0; open = rest.indexOf("$$", open + 1)) {
        if (!escaped(rest, open)) return false;
      }
      var lines = rest ? [rest] : [];
      for (var line = startLine + 1; line < endLine; line++) {
        if (state.isEmpty(line)) break;
        var text = state.src.slice(state.bMarks[line] + state.tShift[line], state.eMarks[line]);
        if (text.trim().slice(-2) === "$$") {
          lines.push(text.trim().slice(0, -2));
          content = lines.join("\n");
          last = line;
          break;
        }
        lines.push(text);
      }
    }
    if (content === null) {
      state.env.mathMiss = [startLine, line];
      return false;
    }
    if (silent) return true;
    var token = state.push("math_block", "math", 0);
    token.block = true;
    token.content = content;
    token.map = [startLine, last + 1];
    state.line = last + 1;
    return true;
  }

  function taskLists(state) {
    // GitHub task list items: "[ ] " or "[x] " at the start of an item.
    var tokens = state.tokens;
    for (var i = 2; i < tokens.length; i++) {
      if (tokens[i].type !== "inline" || tokens[i - 1].type !== "paragraph_open" || tokens[i - 2].type !== "list_item_open") continue;
      var first = tokens[i].children[0];
      var m = first && first.type === "text" && /^\[([ xX])\](?=\s|$)/.exec(first.content);
      if (!m) continue;
      first.content = first.content.slice(3).replace(/^\s/, "");
      var box = new state.Token("html_inline", "", 0);
      box.content = '<input type="checkbox" disabled' + (m[1] === " " ? "" : " checked") + "> ";
      tokens[i].children.unshift(box);
    }
  
  }

  function use(md) {
    md.inline.ruler.before("escape", "math_inline", mathInline);
    md.block.ruler.before("fence", "math_block", mathBlock, { alt: ["paragraph", "reference", "blockquote", "list"] });
    md.core.ruler.after("inline", "task_lists", taskLists);
  }

  window.MiaoYanMarkdownRules = { use: use };
})();
