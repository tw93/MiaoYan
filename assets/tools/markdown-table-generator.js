// The Markdown table generator on /tools/markdown-table-generator/
// (scripts/build-tools.py, which writes the same grid and output so the first
// paint needs no script). The table lives in `rows` and `align`; the grid and
// the Markdown are drawn from them. Pasting cells from a spreadsheet, a CSV, a
// web page or a Markdown table fills the grid; nothing leaves the browser.
(function () {
  "use strict";
  var data = JSON.parse(document.getElementById("table-data").textContent);
  var S = data.strings;
  var U = data.ui;
  var tool = document.getElementById("table-tool");
  var wrap = document.getElementById("table-wrap");
  var out = document.getElementById("table-md");
  var padBox = document.getElementById("table-pad");
  var status = document.getElementById("table-status");
  var undoButton = document.getElementById("table-undo");

  var DRAFT_KEY = "miaoyan.table-generator.draft";
  var MAX_ROWS = 500;
  var MAX_COLS = 30;
  var rows = data.start.rows.map(function (r) { return r.slice(); });
  var align = data.start.align.slice();
  var pristine = true;
  var edited = false;
  var undoState = null;

  function track(name, params) {
    if (typeof window.gtag === "function") window.gtag("event", name, params || {});
  }

  function say(text) { status.textContent = text || ""; }

  function fill(template, values) {
    return template.replace(/\{(\w+)\}/g, function (_, k) { return values[k]; });
  }

  // Columns are counted the way terminals and editors count them: CJK, Hangul,
  // full-width forms and most emoji take two. Same ranges as build-tools.py.
  var WIDE = [
    [0x1100, 0x115F], [0x231A, 0x231B], [0x23E9, 0x23EC], [0x23F0, 0x23F0], [0x23F3, 0x23F3],
    [0x25FD, 0x25FE], [0x2614, 0x2615], [0x2648, 0x2653], [0x267F, 0x267F], [0x2693, 0x2693],
    [0x26A1, 0x26A1], [0x26AA, 0x26AB], [0x26BD, 0x26BE], [0x26C4, 0x26C5], [0x26CE, 0x26CE],
    [0x26D4, 0x26D4], [0x26EA, 0x26EA], [0x26F2, 0x26F3], [0x26F5, 0x26F5], [0x26FA, 0x26FA],
    [0x26FD, 0x26FD], [0x2705, 0x2705], [0x270A, 0x270B], [0x2728, 0x2728], [0x274C, 0x274C],
    [0x274E, 0x274E], [0x2753, 0x2755], [0x2757, 0x2757], [0x2795, 0x2797], [0x27B0, 0x27B0],
    [0x27BF, 0x27BF], [0x2B1B, 0x2B1C], [0x2B50, 0x2B50], [0x2B55, 0x2B55],
    [0x2E80, 0x303E], [0x3041, 0x33FF], [0x3400, 0x4DBF], [0x4E00, 0x9FFF],
    [0xA000, 0xA4CF], [0xA960, 0xA97F], [0xAC00, 0xD7A3], [0xF900, 0xFAFF], [0xFE30, 0xFE4F],
    [0xFF00, 0xFF60], [0xFFE0, 0xFFE6], [0x1F004, 0x1F004], [0x1F0CF, 0x1F0CF], [0x1F18E, 0x1F18E],
    [0x1F191, 0x1F19A], [0x1F200, 0x1F202], [0x1F210, 0x1F23B], [0x1F240, 0x1F248], [0x1F250, 0x1F251],
    [0x1F300, 0x1F64F], [0x1F680, 0x1F6FF], [0x1F7E0, 0x1F7EB], [0x1F90C, 0x1F9FF], [0x1FA70, 0x1FAFF],
    [0x20000, 0x3FFFD]
  ];
  // Marks that join the character before them take no column of their own.
  var ZERO = [[0x0300, 0x036F], [0x200B, 0x200F], [0x20D0, 0x20FF], [0xFE00, 0xFE0F], [0x1F3FB, 0x1F3FF], [0xE0020, 0xE007F]];

  function within(list, cp) {
    for (var i = 0; i < list.length; i++) if (cp >= list[i][0] && cp <= list[i][1]) return true;
    return false;
  }

  function charWidth(ch) {
    var cp = ch.codePointAt(0);
    if (cp < 0x300) return 1;
    if (within(ZERO, cp)) return 0;
    return within(WIDE, cp) ? 2 : 1;
  }

  function textWidth(s) {
    var w = 0;
    for (var ch of s) w += charWidth(ch);
    return w;
  }

  function cell(s) { return s.trim().replace(/\\?\|/g, "\\|"); }

  function repeat(ch, n) { return n > 0 ? new Array(n + 1).join(ch) : ""; }

  function markdown(pad) {
    var cells = rows.map(function (r) { return r.map(cell); });
    var line = function (r) { return "| " + r.join(" | ") + " |"; };
    if (!pad) {
      var rule = align.map(function (a) { return { left: ":---", center: ":---:", right: "---:" }[a] || "---"; });
      return [line(cells[0]), line(rule)].concat(cells.slice(1).map(line)).join("\n");
    }
    var widths = align.map(function (_, c) {
      return Math.max.apply(null, [3].concat(cells.map(function (r) { return textWidth(r[c]); })));
    });
    var fit = function (s, c) {
      var gap = widths[c] - textWidth(s);
      if (align[c] === "right") return repeat(" ", gap) + s;
      if (align[c] === "center") return repeat(" ", Math.floor(gap / 2)) + s + repeat(" ", gap - Math.floor(gap / 2));
      return s + repeat(" ", gap);
    };
    var fitRow = function (r) { return line(r.map(fit)); };
    var rules = align.map(function (a, c) {
      var head = a === "left" || a === "center" ? ":" : "";
      var tail = a === "right" || a === "center" ? ":" : "";
      return head + repeat("-", widths[c] - head.length - tail.length) + tail;
    });
    return [fitRow(cells[0]), line(rules)].concat(cells.slice(1).map(fitRow)).join("\n");
  }

  function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  // Wide characters sit in a two-column box, so the columns line up on screen
  // even where the monospace font's CJK fallback is narrower than two columns.
  function showMarkdown() {
    var text = markdown(padBox.checked);
    var html = "";
    for (var ch of text) html += charWidth(ch) === 2 ? '<span class="w">' + esc(ch) + "</span>" : esc(ch);
    out.innerHTML = html;
  }

  function store() {
    try { localStorage.setItem(DRAFT_KEY, JSON.stringify({ rows: rows, align: align, pad: padBox.checked })); } catch (e) { /* storage blocked */ }
  }

  function changed() {
    pristine = false;
    showMarkdown();
    store();
  }

  // The grid, built exactly as build-tools.py writes it.
  function render(focus) {
    var ctrl = align.map(function (a, c) {
      var buttons = ["left", "center", "right"].map(function (k) {
        var label = U["align_" + k];
        return '<button type="button" class="table-btn" data-align="' + k + '" aria-pressed="' + (a === k) + '" aria-label="' + esc(label) + '" title="' + esc(label) + '">' + data.icons[k] + "</button>";
      }).join("");
      var del = fill(U.del_col, { col: c + 1 });
      return '<td><div class="table-col-ctrl"><div class="table-align" role="group" aria-label="' + esc(fill(U.align_group, { col: c + 1 })) + '">' + buttons + "</div>" +
        '<button type="button" class="table-btn table-x" data-del-col="' + c + '" aria-label="' + esc(del) + '" title="' + esc(del) + '">' + data.icons.x + "</button></div></td>";
    }).join("");
    var body = rows.map(function (row, r) {
      var cells = row.map(function (v, c) {
        return '<td data-align="' + (align[c] || "none") + '"><input class="table-cell" type="text" value="' + esc(v) + '" aria-label="' + esc(fill(U.cell, { row: r + 1, col: c + 1 })) + '" spellcheck="false" autocomplete="off" autocapitalize="off"></td>';
      }).join("");
      var del = fill(U.del_row, { row: r + 1 });
      return "<tr" + (r === 0 ? ' class="is-head"' : "") + ">" + cells + '<td class="table-end"><button type="button" class="table-btn table-x" data-del-row="' + r + '" aria-label="' + esc(del) + '" title="' + esc(del) + '">' + data.icons.x + "</button></td></tr>";
    }).join("");
    wrap.innerHTML = '<table class="table-grid" id="table-grid"><thead><tr class="table-ctrl">' + ctrl + '<td class="table-end"></td></tr></thead><tbody>' + body + "</tbody></table>";
    if (focus) focusCell(focus[0], focus[1]);
  }

  function focusCell(r, c) {
    var tr = wrap.querySelectorAll("tbody tr")[Math.max(0, Math.min(r, rows.length - 1))];
    var input = tr && tr.querySelectorAll(".table-cell")[Math.max(0, Math.min(c, align.length - 1))];
    if (input) { input.focus(); input.select(); }
  }

  function position(input) {
    var td = input.closest("td");
    var tr = td.parentElement;
    return [Array.prototype.indexOf.call(tr.parentElement.children, tr), Array.prototype.indexOf.call(tr.children, td)];
  }

  function snapshot() {
    undoState = { rows: rows.map(function (r) { return r.slice(); }), align: align.slice() };
    undoButton.hidden = false;
  }

  function hideUndo() {
    undoState = null;
    undoButton.hidden = true;
  }

  function addRow(at) {
    rows.splice(at, 0, align.map(function () { return ""; }));
  }

  function addCol(at) {
    rows.forEach(function (r) { r.splice(at, 0, ""); });
    align.splice(at, 0, "");
  }

  // Parsing what was pasted or dropped. Each returns { rows, align? } or null for
  // text that is not a table, which then pastes into one cell as usual.
  function splitPipes(line) {
    var s = line.trim();
    if (s.charAt(0) === "|") s = s.slice(1);
    if (s.slice(-1) === "|" && s.slice(-2) !== "\\|") s = s.slice(0, -1);
    var cells = [];
    var cur = "";
    for (var i = 0; i < s.length; i++) {
      if (s[i] === "\\" && s[i + 1] === "|") { cur += "|"; i++; continue; }
      if (s[i] === "|") { cells.push(cur.trim()); cur = ""; continue; }
      cur += s[i];
    }
    cells.push(cur.trim());
    return cells;
  }

  // A delimiter row: cells of dashes with optional colons, checked cell by cell
  // rather than with one regular expression that backtracks on long lines.
  function isRule(line) {
    if (line.indexOf("-") < 0) return false;
    var s = line.trim();
    if (s.charAt(0) === "|") s = s.slice(1);
    if (s.slice(-1) === "|") s = s.slice(0, -1);
    return s.split("|").every(function (c) { return /^\s*:?-+:?\s*$/.test(c); });
  }

  // The first pipe table in the lines: at the top when pasted, anywhere in a
  // dropped file. A blank line or a line without a pipe ends it, as in GFM.
  function parseMarkdown(lines, anywhere) {
    var start = -1;
    for (var i = 0; i + 1 < lines.length; i++) {
      if (!lines[i].trim()) continue;
      if (lines[i].indexOf("|") >= 0 && isRule(lines[i + 1])) { start = i; break; }
      if (!anywhere) return null;
    }
    if (start < 0) return null;
    var head = splitPipes(lines[start]);
    var rule = splitPipes(lines[start + 1]);
    var body = [];
    for (var j = start + 2; j < lines.length && lines[j].trim() && lines[j].indexOf("|") >= 0; j++) body.push(splitPipes(lines[j]));
    return {
      rows: [head].concat(body),
      align: rule.map(function (r) {
        var left = r.charAt(0) === ":";
        var right = r.slice(-1) === ":";
        return left && right ? "center" : right ? "right" : left ? "left" : "";
      })
    };
  }

  // Delimited text with quoted fields, as Excel and Sheets write it: a quoted
  // cell may hold the delimiter, a doubled quote and line breaks.
  function parseDelimited(text, delim) {
    var out = [[]];
    var cur = "";
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      var ch = text[i];
      if (quoted) {
        if (ch === '"' && text[i + 1] === '"') { cur += '"'; i++; }
        else if (ch === '"') quoted = false;
        else cur += ch;
      } else if (ch === '"' && cur === "") quoted = true;
      else if (ch === delim) { out[out.length - 1].push(cur); cur = ""; }
      else if (ch === "\n") { out[out.length - 1].push(cur); out.push([]); cur = ""; }
      else cur += ch;
    }
    out[out.length - 1].push(cur);
    return out
      .filter(function (r) { return r.length > 1 || r[0].trim(); })
      .map(function (r) { return r.map(function (c) { return c.replace(/\n/g, "<br>").trim(); }); });
  }

  function parseHtml(html) {
    var doc = new DOMParser().parseFromString(html, "text/html");
    var table = doc.querySelector("table");
    if (!table) return null;
    Array.prototype.forEach.call(table.querySelectorAll("br"), function (br) { br.replaceWith(""); });
    Array.prototype.forEach.call(table.querySelectorAll("style, script"), function (el) { el.remove(); });
    var grid = [];
    Array.prototype.forEach.call(table.rows, function (tr, r) {
      grid[r] = grid[r] || [];
      var c = 0;
      Array.prototype.forEach.call(tr.cells, function (td) {
        while (grid[r][c] !== undefined) c++;
        var text = td.textContent.replace(/\s+/g, " ").trim().replace(/ ? ?/g, "<br>");
        var span = Math.max(1, Math.min(MAX_COLS, td.colSpan || 1));
        var down = Math.max(1, Math.min(MAX_ROWS, td.rowSpan || 1));
        for (var dr = 0; dr < down; dr++) {
          grid[r + dr] = grid[r + dr] || [];
          for (var dc = 0; dc < span; dc++) grid[r + dr][c + dc] = dr === 0 && dc === 0 ? text : "";
        }
        c += span;
      });
    });
    grid = grid.map(function (r) { return Array.from(r, function (v) { return v || ""; }); });
    return grid.length ? { rows: grid } : null;
  }

  function nonEmpty(row) { return row.filter(function (c) { return c; }).length; }

  function parseText(text, hint) {
    text = text.replace(/\r\n?/g, "\n").replace(/\n+$/, "");
    if (!text.trim()) return null;
    var lines = text.split("\n");
    var md = parseMarkdown(lines, hint === "md");
    if (md || hint === "md") return md;
    if (hint === "tsv" || text.indexOf("\t") >= 0) {
      var tsv = parseDelimited(text, "\t");
      // One line with a tab in it is a table only when two cells hold something;
      // a line of code with a leading tab is not.
      if (!tsv.length || (tsv.length === 1 && nonEmpty(tsv[0]) < 2)) return null;
      return { rows: tsv };
    }
    // A comma inside one line of text is a sentence, not a table: pasted CSV needs
    // two lines with the same number of fields. A .csv file is taken as it is.
    var best = null;
    [",", ";"].forEach(function (d) {
      if (best) return;
      var parsed = parseDelimited(text, d);
      if (!parsed.length) return;
      var n = parsed[0].length;
      var even = parsed.every(function (r) { return r.length === n; });
      if (hint === "csv" ? parsed.some(function (r) { return r.length > 1; }) : n > 1 && even && parsed.length > 1) best = { rows: parsed };
    });
    return best;
  }

  function normalize(table) {
    var source = table.rows.slice(0, MAX_ROWS);
    var widest = 1;
    for (var i = 0; i < source.length; i++) widest = Math.max(widest, source[i].length);
    var width = Math.min(MAX_COLS, widest);
    var trimmed = table.rows.length > MAX_ROWS || widest > MAX_COLS;
    var body = source.map(function (r) {
      var row = r.slice(0, width);
      while (row.length < width) row.push("");
      return row;
    });
    var al = (table.align || []).slice(0, width);
    while (al.length < width) al.push("");
    return { rows: body, align: al, trimmed: trimmed };
  }

  function report(trimmed, r, c, source) {
    say(trimmed ? fill(S.trimmed, { rows: MAX_ROWS, cols: MAX_COLS }) : fill(S.pasted, { rows: r, cols: c }));
    track("tool_import", { tool: "table", source: source });
  }

  // A whole table replaces the grid; cells pasted into the middle of it fill from
  // that cell and grow the grid as needed. Both can be undone.
  function replaceAll(table, source) {
    snapshot();
    rows = table.rows;
    align = table.align;
    render([0, 0]);
    changed();
    report(table.trimmed, rows.length, align.length, source);
  }

  function fillFrom(r0, c0, table, source) {
    snapshot();
    var lost = table.trimmed;
    var placedRows = 0;
    var placedCols = 0;
    table.rows.forEach(function (row, dr) {
      var r = r0 + dr;
      if (r >= MAX_ROWS) { lost = true; return; }
      while (rows.length <= r) addRow(rows.length);
      placedRows = dr + 1;
      row.forEach(function (v, dc) {
        var c = c0 + dc;
        if (c >= MAX_COLS) { lost = true; return; }
        while (align.length <= c) addCol(align.length);
        rows[r][c] = v;
        placedCols = Math.max(placedCols, dc + 1);
      });
    });
    render([r0, c0]);
    changed();
    report(lost, placedRows, placedCols, source);
  }

  // Spreadsheets and browsers put both tab-separated text and HTML on the
  // clipboard. The text is exact, so it wins, unless the HTML table merges cells,
  // which only the HTML can place.
  function readClipboard(e) {
    var cd = e.clipboardData;
    if (!cd) return null;
    var text = cd.getData("text/plain") || "";
    var lines = text.replace(/\r\n?/g, "\n").split("\n");
    var md = parseMarkdown(lines, false);
    if (md) return { table: md, source: "markdown", whole: true };
    var html = cd.getData("text/html") || "";
    var fromHtml = /<table/i.test(html) ? parseHtml(html) : null;
    var multi = fromHtml && (fromHtml.rows.length > 1 || fromHtml.rows[0].length > 1);
    if (multi && /\b(?:col|row)span\s*=\s*["']?\s*[2-9]/i.test(html)) return { table: fromHtml, source: "html" };
    if (text.indexOf("\t") >= 0) {
      var tsv = parseText(text, "tsv");
      if (tsv) return { table: tsv, source: "tsv" };
    }
    if (multi) return { table: fromHtml, source: "html" };
    var csv = parseText(text);
    return csv ? { table: csv, source: "csv" } : null;
  }

  document.addEventListener("paste", function (e) {
    var target = e.target;
    var inCell = target.classList && target.classList.contains("table-cell");
    var elsewhere = !inCell && target.closest && target.closest("input, textarea, [contenteditable]");
    if (elsewhere) return;
    var got = readClipboard(e);
    if (!got) return;
    e.preventDefault();
    var table = normalize(got.table);
    var at = inCell ? position(target) : [0, 0];
    if (got.whole || pristine || (at[0] === 0 && at[1] === 0)) replaceAll(table, got.source);
    else fillFrom(at[0], at[1], table, got.source);
  });

  // A dropped .csv, .tsv, .md or .txt file opens as the table.
  tool.addEventListener("dragover", function (e) {
    if (e.dataTransfer && Array.prototype.indexOf.call(e.dataTransfer.types, "Files") >= 0) {
      e.preventDefault();
      tool.classList.add("is-drop");
    }
  });
  tool.addEventListener("dragleave", function (e) {
    if (!tool.contains(e.relatedTarget)) tool.classList.remove("is-drop");
  });
  var TEXT_FILES = { csv: "csv", tsv: "tsv", tab: "tsv", txt: "", md: "md", markdown: "md" };

  // UTF-8 first; a file that is not valid UTF-8 is read as GB18030, which is how
  // Excel on Chinese Windows saves CSV.
  function decode(buffer) {
    var bytes = new Uint8Array(buffer);
    try { return new TextDecoder("utf-8", { fatal: true }).decode(bytes); } catch (err) { /* not UTF-8 */ }
    try { return new TextDecoder("gb18030").decode(bytes); } catch (err) { return new TextDecoder("utf-8").decode(bytes); }
  }

  tool.addEventListener("drop", function (e) {
    var file = e.dataTransfer && e.dataTransfer.files[0];
    tool.classList.remove("is-drop");
    if (!file) return;
    e.preventDefault();
    var ext = (file.name.split(".").pop() || "").toLowerCase();
    if (!(ext in TEXT_FILES) || file.size > 4e6 || !file.arrayBuffer) { say(S.fileType); return; }
    file.arrayBuffer().then(function (buffer) {
      var parsed = parseText(decode(buffer).replace(/^\uFEFF/, ""), TEXT_FILES[ext]);
      if (!parsed) { say(S.noTable); return; }
      replaceAll(normalize(parsed), "file");
    }, function () { say(S.noTable); });
  });

  wrap.addEventListener("input", function (e) {
    if (!e.target.classList.contains("table-cell")) return;
    var at = position(e.target);
    rows[at[0]][at[1]] = e.target.value;
    hideUndo();
    say("");
    if (!edited) { edited = true; track("tool_render", { tool: "table" }); }
    changed();
  });

  // Enter moves down a row, adding one at the end; Shift+Enter moves up. The
  // arrow keys move between rows; Tab moves between cells as in any form.
  wrap.addEventListener("keydown", function (e) {
    if (!e.target.classList.contains("table-cell") || e.isComposing || e.keyCode === 229) return;
    var at = position(e.target);
    if (e.altKey || e.ctrlKey || e.metaKey) return;
    var arrow = e.key === "ArrowDown" || e.key === "ArrowUp";
    if (arrow && e.shiftKey) return;
    var down = (e.key === "Enter" && !e.shiftKey) || e.key === "ArrowDown";
    var up = (e.key === "Enter" && e.shiftKey) || e.key === "ArrowUp";
    if (!down && !up) return;
    e.preventDefault();
    if (up && at[0] === 0) return;
    if (down && at[0] === rows.length - 1) {
      if (e.key !== "Enter" || rows.length >= MAX_ROWS) return;
      addRow(rows.length);
      hideUndo();
      render([at[0] + 1, at[1]]);
      changed();
      return;
    }
    focusCell(at[0] + (down ? 1 : -1), at[1]);
  });

  wrap.addEventListener("click", function (e) {
    var button = e.target.closest("button");
    if (!button) return;
    var col = button.closest("td");
    if (button.dataset.align) {
      var c = Array.prototype.indexOf.call(col.parentElement.children, col);
      align[c] = align[c] === button.dataset.align ? "" : button.dataset.align;
      hideUndo();
      render();
      changed();
      var again = wrap.querySelectorAll(".table-ctrl td")[c].querySelector('[data-align="' + button.dataset.align + '"]');
      if (again) again.focus();
    } else if (button.dataset.delCol !== undefined) {
      if (align.length === 1) return;
      var dc = Number(button.dataset.delCol);
      snapshot();
      rows.forEach(function (r) { r.splice(dc, 1); });
      align.splice(dc, 1);
      render([0, Math.min(dc, align.length - 1)]);
      changed();
      say(S.deleted);
    } else if (button.dataset.delRow !== undefined) {
      if (rows.length === 1) return;
      var dr = Number(button.dataset.delRow);
      snapshot();
      rows.splice(dr, 1);
      render([Math.min(dr, rows.length - 1), 0]);
      changed();
      say(S.deleted);
    }
  });

  tool.querySelector(".table-bar").addEventListener("click", function (e) {
    var button = e.target.closest("[data-op]");
    if (!button) return;
    var op = button.dataset.op;
    if (op !== "clear") hideUndo();
    if (op === "row" && rows.length < MAX_ROWS) {
      addRow(rows.length);
      render([rows.length - 1, 0]);
      changed();
    } else if (op === "col" && align.length < MAX_COLS) {
      addCol(align.length);
      render([0, align.length - 1]);
      changed();
    } else if (op === "clear") {
      snapshot();
      rows = [["", "", ""], ["", "", ""], ["", "", ""]];
      align = ["", "", ""];
      render([0, 0]);
      changed();
      say(S.cleared);
    }
  });

  undoButton.addEventListener("click", function () {
    if (!undoState) return;
    rows = undoState.rows;
    align = undoState.align;
    hideUndo();
    render([0, 0]);
    changed();
    say("");
  });

  padBox.addEventListener("change", function () {
    showMarkdown();
    store();
  });

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

  tool.querySelector('[data-action="copy"]').addEventListener("click", function () {
    copyText(markdown(padBox.checked)).then(function () {
      say(S.copied);
      track("tool_copy", { tool: "table", kind: "markdown" });
    }, function () { say(S.copyFailed); });
  });

  // Restore the last table from this browser, if it is a sound one.
  function restore() {
    var saved = null;
    try { saved = JSON.parse(localStorage.getItem(DRAFT_KEY) || "null"); } catch (e) { saved = null; }
    if (!saved || !Array.isArray(saved.rows) || !Array.isArray(saved.align) || !saved.rows.length || !saved.align.length) return;
    var width = saved.align.length;
    var sound = saved.rows.length <= MAX_ROWS && width <= MAX_COLS && saved.rows.every(function (r) {
      return Array.isArray(r) && r.length === width && r.every(function (v) { return typeof v === "string"; });
    });
    if (!sound) return;
    rows = saved.rows;
    align = saved.align.map(function (a) { return a === "left" || a === "center" || a === "right" ? a : ""; });
    padBox.checked = saved.pad !== false;
    pristine = false;
    render();
    showMarkdown();
  }

  restore();
})();
