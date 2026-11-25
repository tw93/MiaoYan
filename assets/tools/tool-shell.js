// What every tool page shares: the switch at the end of the toolbar that gives
// the tool the whole screen. The tool fills the window as a fixed layer (the
// only way on an iPhone, which has no element full screen) and, where the
// browser allows it, the screen too through the Fullscreen API, so Esc or the
// system's own exit leaves both. The panes take the height left under the
// toolbar, measured here rather than guessed in CSS, since each tool stacks a
// different set of rows.
(function () {
  "use strict";
  var button = document.querySelector(".tool-full");
  if (!button) return;
  var tool = button.closest(".tool");
  var root = document.documentElement;
  var full = false;

  function panes() {
    return tool.querySelector(".tool-grid, .nnw-frame, .table-wrap");
  }

  function measure() {
    if (!full) return;
    tool.style.removeProperty("--full-h");
    var first = panes();
    var foot = tool.querySelector(".tool-foot");
    var bottom = parseFloat(getComputedStyle(tool).paddingBottom) || 0;
    var top = first ? first.getBoundingClientRect().top - tool.getBoundingClientRect().top : 0;
    var below = foot ? foot.offsetHeight + (parseFloat(getComputedStyle(foot).marginTop) || 0) : 0;
    var h = tool.clientHeight - top - below - bottom;
    tool.style.setProperty("--full-h", Math.max(240, Math.floor(h)) + "px");
  }

  function label() {
    var text = full ? button.dataset.off : button.dataset.on;
    button.setAttribute("aria-pressed", String(full));
    button.setAttribute("aria-label", text);
    button.title = text;
  }

  function set(on) {
    if (on === full) return;
    full = on;
    tool.classList.toggle("is-full", on);
    root.classList.toggle("has-full-tool", on);
    label();
    if (on) {
      measure();
      requestAnimationFrame(measure);
    } else {
      tool.style.removeProperty("--full-h");
    }
    // Panes that fit a drawing to their size (the diagram editors) listen
    // for resize; a fixed layer changes their size without one.
    window.dispatchEvent(new Event("resize"));
  }

  function screenElement() {
    return document.fullscreenElement || document.webkitFullscreenElement || null;
  }

  function enter() {
    set(true);
    var request = tool.requestFullscreen || tool.webkitRequestFullscreen;
    if (request) {
      try {
        var p = request.call(tool);
        if (p && p.catch) p.catch(function () {});
      } catch (e) { /* the fixed layer alone */ }
    }
  }

  function leave() {
    if (screenElement() === tool) {
      var exit = document.exitFullscreen || document.webkitExitFullscreen;
      if (exit) {
        try {
          var p = exit.call(document);
          if (p && p.catch) p.catch(function () {});
        } catch (e) { /* the class below still restores the page */ }
      }
    }
    set(false);
  }

  button.addEventListener("click", function () {
    if (full) leave(); else enter();
    if (typeof window.gtag === "function" && full) {
      window.gtag("event", "tool_fullscreen", { tool: tool.id.replace(/-tool$/, "") });
    }
  });

  function onScreenChange() {
    // Esc or the system's button left the screen: leave the layer too.
    if (full && screenElement() !== tool) set(false);
    else measure();
  }
  document.addEventListener("fullscreenchange", onScreenChange);
  document.addEventListener("webkitfullscreenchange", onScreenChange);

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && full && !screenElement()) leave();
  });
  window.addEventListener("resize", function () {
    if (full) measure();
  });
})();
