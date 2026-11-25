// Save to MiaoYan, on the tool pages and Learn Markdown (maintainer
// 2026-11-25, after YouMind's tools, which carry a result on into their app):
// on a Mac a button hands the tool's Markdown to the MiaoYan app as a new
// note through miaoyan://new?title=..&txt=.., a route the Mac app has had
// since 2020 (MiaoYan Controllers/AppDelegate+URLRoutes.swift). The iPhone
// app's route is in no released build yet, so other systems never see the
// button. The app reads "+" as a space before parsing, which
// encodeURIComponent never leaves bare. When the page keeps its focus for two
// seconds the status says how to get MiaoYan, worded as a condition: Safari
// asks inside the page, so its prompt is still open then (test Mac, 2026-11-25).
// Chrome drops a URL over 2 MB without a word, so a longer note is refused here
// (MAX_URL); 1.46 million characters, a 500,000-character note, went through
// both browsers byte for byte, 5.8 million did not reach the app.
(function () {
  "use strict";
  var buttons = Array.prototype.slice.call(document.querySelectorAll("[data-miaoyan-save]"));
  var mac = /Mac/.test(navigator.platform || "") && (navigator.maxTouchPoints || 0) < 2;
  if (!buttons.length || !mac) return;
  var MAX_URL = 2000000;

  function markdown(button) {
    if (button.hasAttribute("data-text")) return button.getAttribute("data-text").replace(/\s+$/, "");
    var el = document.querySelector(button.getAttribute("data-source"));
    if (!el) return "";
    var body = (el.value != null ? el.value : el.textContent).replace(/\s+$/, "");
    var lang = button.getAttribute("data-fence");
    if (!lang || !body) return body;
    var fence = "```";
    while (body.indexOf(fence) >= 0) fence += "`";
    return fence + lang + "\n" + body + "\n" + fence;
  }

  // The note's name is the first heading, as MiaoYan names one it creates;
  // without one MiaoYan asks for a name itself.
  function title(body) {
    var m = /^#{1,6}[ \t]+(.+?)[ \t#]*$/m.exec(body);
    if (!m) return "";
    return m[1].replace(/[*_`~[\]()!]/g, "").replace(/[\\/:*?"<>|\u0000-\u001F]+/g, " ").trim().slice(0, 80);
  }

  buttons.forEach(function (button) {
    button.hidden = false;
    button.addEventListener("click", function () {
      var status = document.querySelector(button.getAttribute("data-status"));
      var body = markdown(button);
      if (!body.trim()) {
        if (status) status.textContent = button.getAttribute("data-empty");
        return;
      }
      var url = "miaoyan://new?title=" + encodeURIComponent(title(body)) + "&txt=" + encodeURIComponent(body + "\n");
      if (url.length > MAX_URL) {
        if (status) status.textContent = button.getAttribute("data-long");
        return;
      }
      if (status) status.textContent = "";
      var left = false;
      function away() { left = true; }
      window.addEventListener("blur", away);
      document.addEventListener("visibilitychange", away);
      var link = document.createElement("a");
      link.href = url;
      link.hidden = true;
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(function () {
        window.removeEventListener("blur", away);
        document.removeEventListener("visibilitychange", away);
        if (!left && status) status.textContent = button.getAttribute("data-missing");
      }, 2000);
      if (typeof window.gtag === "function") window.gtag("event", "tool_save", { tool: button.getAttribute("data-tool") });
    });
  });
})();
