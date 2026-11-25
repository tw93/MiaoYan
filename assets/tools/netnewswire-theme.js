// The NetNewsWire theme page: switch the preview between the theme's light
// and dark appearance, and after the install link say what to do when
// NetNewsWire is not there to take it (a browser gives no sign either way).
(function () {
  "use strict";
  var tool = document.getElementById("nnw-tool");
  if (!tool) return;
  var data = JSON.parse(document.getElementById("nnw-data").textContent);
  var frame = document.getElementById("nnw-frame");
  var status = document.getElementById("nnw-status");
  var chips = tool.querySelectorAll("[data-scheme].tool-chip");
  var shots = frame.querySelectorAll(".nnw-shot");

  function show(scheme) {
    Array.prototype.forEach.call(chips, function (c) { c.setAttribute("aria-pressed", String(c.dataset.scheme === scheme)); });
    Array.prototype.forEach.call(shots, function (s) { s.hidden = s.dataset.scheme !== scheme; });
    frame.classList.toggle("is-dark", scheme === "dark");
    frame.classList.toggle("is-light", scheme !== "dark");
    frame.scrollTop = 0;
  }
  Array.prototype.forEach.call(chips, function (c) {
    c.addEventListener("click", function () { show(c.dataset.scheme); });
  });
  var install = tool.querySelector('[data-action="install"]');
  install.addEventListener("click", function () {
    if (typeof window.gtag === "function") window.gtag("event", "tool_export", { tool: "netnewswire-theme", format: "install" });
    setTimeout(function () { status.textContent = data.strings.installing; }, 1200);
  });
})();
