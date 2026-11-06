// requestAnimationFrame never fires in a page that is not on screen: the PDF
// export's offscreen window, or a preview behind other windows. d3 steps every
// transition on it and reads the clock it caches between frames, so Markmap
// stayed at its first, empty step and printed as a blank box. A callback the
// native frame has not run within 100ms runs from a timer instead; on screen
// the native frame always comes first. Loaded before d3, which keeps the
// function it finds when it loads.
(function () {
  const nativeRequest = window.requestAnimationFrame?.bind(window);
  const nativeCancel = window.cancelAnimationFrame?.bind(window);
  if (!nativeRequest || !nativeCancel) return;

  const pending = new Map();
  let nextId = 1;

  window.requestAnimationFrame = function (callback) {
    const id = nextId++;
    const run = (time) => {
      const entry = pending.get(id);
      if (!entry) return;
      pending.delete(id);
      nativeCancel(entry.frame);
      clearTimeout(entry.timer);
      callback(time);
    };
    pending.set(id, {
      frame: nativeRequest(run),
      timer: setTimeout(() => run(performance.now()), 100),
    });
    return id;
  };

  window.cancelAnimationFrame = function (id) {
    const entry = pending.get(id);
    if (!entry) return;
    pending.delete(id);
    nativeCancel(entry.frame);
    clearTimeout(entry.timer);
  };
})();
