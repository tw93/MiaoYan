/**
 * MiaoYan Common Utilities
 */

const MiaoYanCommon = {
  isDarkMode() {
    // Delegate to ThemeConfig for consistent dark mode detection
    return window.ThemeConfig?.isDarkMode?.() || 'CUSTOM_CSS' === 'darkmode';
  },

  // Utility: Apply styles to multiple elements
  applyStylesToElements(selector, styles) {
    document.querySelectorAll(selector).forEach(el => {
      Object.assign(el.style, styles);
    });
  },

  // Utility: Set attributes to multiple elements
  setAttributesToElements(selector, attributes) {
    document.querySelectorAll(selector).forEach(el => {
      Object.entries(attributes).forEach(([key, value]) => {
        el.setAttribute(key, value);
      });
    });
  },

  // The selection as plain text and HTML for the clipboard. A selection that
  // is one heading, as a triple-click makes it, loses its <h1>-<h6> wrapper:
  // apps that turn pasted HTML into Markdown, the editor included, otherwise
  // paste "## Title" when only the title's words were wanted.
  selectionPayload() {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0) return { text: '', html: '', heading: false };
    const text = selection.toString() || '';
    const container = document.createElement('div');
    container.appendChild(selection.getRangeAt(0).cloneContents());
    const only = container.children.length === 1 ? container.children[0] : null;
    if (only && /^H[1-6]$/.test(only.tagName) && container.textContent.trim() === only.textContent.trim()) {
      return { text: text.trim(), html: only.innerHTML, heading: true };
    }
    return { text: text, html: container.innerHTML || '', heading: false };
  },

  setupTextSelection() {
    // Edit > Copy goes through MPreviewView.copySelectionToPasteboard; the
    // context menu's Copy reaches the page as a copy event. Only a lone
    // heading is rewritten there: any other selection keeps WebKit's own copy,
    // whose HTML carries the styles that rich-text apps paste.
    document.addEventListener('copy', (e) => {
      const payload = MiaoYanCommon.selectionPayload();
      if (!payload.heading || !payload.text || !e.clipboardData) return;
      e.preventDefault();
      e.clipboardData.setData('text/plain', payload.text);
      if (payload.html) e.clipboardData.setData('text/html', payload.html);
    });

    function getSelectionAndSendMessage() {
      const txt = document.getSelection().toString();
      window.webkit?.messageHandlers.newSelectionDetected?.postMessage(txt);
    }

    document.onmouseup = getSelectionAndSendMessage;
    document.onkeyup = getSelectionAndSendMessage;
    document.oncontextmenu = getSelectionAndSendMessage;
  },

  setupCheckboxes() {
    document.querySelectorAll('input').forEach(input => {
      input.disabled = true;

      const parent = input.parentNode;
      const grandParent = parent?.parentNode;

      if (parent?.tagName === 'P' && grandParent?.tagName === 'LI') {
        grandParent.parentNode?.classList.add('cb');
      } else if (parent?.tagName === 'LI') {
        grandParent?.classList.add('cb');
      }
    });
  },

  // Give every rendered table a scroll container. Doing it here rather than in
  // the Markdown renderer keeps the generated HTML plain, and a table whose
  // content cannot shrink (a KaTeX formula, an unbreakable token) then scrolls
  // instead of disappearing under #write's `overflow-x: hidden` (#560).
  wrapWideTables() {
    document.querySelectorAll('#write table').forEach((table) => {
      if (table.parentElement?.classList.contains('table-scroll')) return;
      const wrapper = document.createElement('div');
      wrapper.className = 'table-scroll';
      table.parentNode.insertBefore(wrapper, table);
      wrapper.appendChild(table);
    });
  },

  setupInteractiveCheckboxes() {
    this.setupCheckboxes();

    const checkboxList = document.querySelectorAll('input[type=checkbox]');
    checkboxList.forEach((checkbox, i) => {
      if (checkbox.parentNode.nodeName === 'LI' && checkbox.hasAttribute('checked')) {
        checkbox.parentNode.classList.add('strike');
      }

      checkbox.disabled = false;
      checkbox.dataset.checkbox = i;
      // The source line of the task item lets the app edit that exact line;
      // counting checkboxes cannot tell them apart from task-like text in
      // code blocks or from `* [ ]` and numbered tasks.
      const item = checkbox.closest('li[data-sourcepos]');
      if (item) checkbox.dataset.line = item.dataset.sourcepos.split(':')[0];

      // A live update keeps the blocks that did not change, and their boxes
      // with them; a second listener would toggle the line twice.
      if (checkbox.__miaoyanBound) return;
      checkbox.__miaoyanBound = true;
      checkbox.addEventListener('click', (event) => {
        this.handleCheckboxClick(event.target);
      });
    });
  },

  handleCheckboxClick(element) {
    if (element.parentNode.nodeName === 'LI') {
      element.parentNode.classList.remove('strike');
    }

    const id = element.dataset.checkbox;
    const line = element.dataset.line;
    if (window.webkit?.messageHandlers.checkbox) {
      window.webkit.messageHandlers.checkbox.postMessage(line ? `line:${line}` : id);
    }

    const input = document.createElement('input');
    input.type = 'checkbox';
    input.dataset.checkbox = id;
    if (line) input.dataset.line = line;

    if (!element.hasAttribute('checked')) {
      input.defaultChecked = true;
      if (element.parentNode.nodeName === 'LI') {
        element.parentNode.classList.add('strike');
      }
    }

    element.parentNode.replaceChild(input, element);
    input.__miaoyanBound = true;
    input.addEventListener('click', () => {
      this.handleCheckboxClick(input);
    });
  },

  optimizeImages() {
    const allImages = document.querySelectorAll('img');

    // Configuration
    const INTERSECTION_MARGIN = '400px'; // Start loading 400px before viewport for smoother experience
    const PLACEHOLDER = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

    allImages.forEach((img) => {
      img.style.maxWidth = '100%';
      img.style.height = 'auto';

      // Swift already marked lazy images with class="lazy-image" and data-src
      // Just ensure eager images have the attribute set
      if (!img.classList.contains('lazy-image')) {
        img.setAttribute('loading', 'eager');
        if (!img.src.startsWith('data:') && !img.classList.contains('emoji')) this.holdImageBox(img);
      }
    });

    // A remote image MiaoYan has not seen before asks the app for the size in
    // its file's header (applyImageSize answers, well before a large file has
    // arrived) and reports its size again once it loads, so the next time the
    // note opens its box is already reserved. Until the answer one standing
    // alone in its paragraph holds a full-width 16:9 box, not a 1px point the
    // text jumps away from. Those nearest the view ask first.
    const asks = [];
    document.querySelectorAll('img[data-measure]').forEach((img) => {
      if (img.__miaoyanMeasured) return;
      img.__miaoyanMeasured = true;
      const parent = img.parentElement;
      if (img.classList.contains('lazy-image') && parent && parent.tagName === 'P' && parent.children.length === 1 && !parent.textContent.trim()) {
        img.classList.add('media-reserve');
        img.addEventListener('error', () => img.classList.remove('media-reserve'), { once: true });
      }
      if (img.dataset.src) asks.push(img);
      const report = () => {
        const src = img.currentSrc || img.src;
        if (!src || src.startsWith('data:') || img.naturalWidth < 2) return false;
        img.classList.remove('media-reserve');
        img.removeAttribute('data-measure');
        // The picture itself now holds the box.
        if (img.dataset.probed) img.style.aspectRatio = '';
        window.webkit?.messageHandlers.imageSize?.postMessage({ src, width: img.naturalWidth, height: img.naturalHeight });
        return true;
      };
      const onLoad = () => { if (report()) img.removeEventListener('load', onLoad); };
      if (!(img.complete && report())) img.addEventListener('load', onLoad);
    });
    if (asks.length && window.webkit?.messageHandlers.imageProbe) {
      const middle = window.innerHeight / 2;
      const distance = (img) => {
        const box = img.getBoundingClientRect();
        return Math.abs((box.top + box.bottom) / 2 - middle);
      };
      asks.sort((a, b) => distance(a) - distance(b))
        .forEach((img) => window.webkit.messageHandlers.imageProbe.postMessage(img.dataset.src));
    }

    // Lazy images start only once the page has loaded. An image whose src is
    // set before the load event holds that event back, and the app shows a
    // note only after it, so a note with many images, or one slow server,
    // stayed hidden until those images had arrived. Text shows first now and
    // the images fill their reserved boxes right after.
    if (document.readyState !== 'complete') {
      if (!this._lazyAfterLoad) {
        this._lazyAfterLoad = true;
        window.addEventListener('load', () => this.optimizeImages(), { once: true });
      }
      return;
    }

    this.prepareVideos();

    // Intersection Observer for aggressive lazy loading
    if ('IntersectionObserver' in window) {
      // One observer for the page: a split-view update calls this again, and
      // a second observer would watch the same images twice.
      if (this._imageObserver) {
        document.querySelectorAll('img.lazy-image').forEach(img => this._imageObserver.observe(img));
        return;
      }
      const imageObserver = this._imageObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            const img = entry.target;
            if (img.dataset.src) {
              img.src = img.dataset.src;
              img.classList.remove('lazy-image');
              delete img.dataset.src;
              observer.unobserve(img);
              MiaoYanCommon.holdImageBox(img);

              // Re-initialize Lightense for this image after it loads
              if (window.Lightense && (img.closest('#write') || img.parentElement?.tagName === 'P' || img.closest('table'))) {
                img.addEventListener('load', () => {
                  window.Lightense([img], {
                    background: MiaoYanCommon.isDarkMode() ? 'rgba(33, 38, 43, .8)' : 'rgba(255, 255, 255, .8)',
                  });
                }, { once: true });
              }
            }
          }
        });
      }, {
        rootMargin: INTERSECTION_MARGIN,
        threshold: 0.01
      });

      document.querySelectorAll('img.lazy-image').forEach(img => {
        imageObserver.observe(img);
      });
    } else {
      // Fallback for older browsers (shouldn't happen on macOS 11.5+)
      document.querySelectorAll('img.lazy-image').forEach(img => {
        if (img.dataset.src) {
          img.src = img.dataset.src;
          delete img.dataset.src;
        }
      });
    }
  },

  // The size the app read from a remote image's header: the box takes the
  // picture's ratio, at the width the note wrote or the image's own, until
  // the picture arrives and holds it itself. An image that has loaded, or
  // whose note set its own ratio, is left alone. A box above the view grows
  // without moving the text being read, and one whose file then fails to
  // load gives back what it was given.
  applyImageSize(src, width, height) {
    document.querySelectorAll('img[data-measure]').forEach((img) => {
      if (img.dataset.src !== src && img.getAttribute('src') !== src) return;
      if (!img.src.startsWith('data:') && img.complete && img.naturalWidth > 1) return;
      if (img.style.aspectRatio || img.dataset.probed) return;
      const before = img.getBoundingClientRect();
      const scrolled = window.scrollY;
      img.dataset.probed = '1';
      img.classList.remove('media-reserve');
      img.style.aspectRatio = `${width} / ${height}`;
      const added = !img.hasAttribute('width') && !img.hasAttribute('height');
      if (added) {
        img.setAttribute('width', width);
        img.setAttribute('height', height);
      }
      img.addEventListener('error', () => {
        img.style.aspectRatio = '';
        if (added) {
          img.removeAttribute('width');
          img.removeAttribute('height');
        }
      }, { once: true });
      // Newer WebKit anchors the scroll itself; older ones leave it to us.
      if (before.bottom <= 0) {
        const grown = img.getBoundingClientRect().height - before.height;
        const missing = grown - (window.scrollY - scrolled);
        if (Math.abs(missing) >= 1) window.scrollBy(0, missing);
      }
    });
  },

  // An image keeps a tinted box until it has painted, so a slow one reads
  // as on its way rather than as a gap in the note. The tint goes once it
  // loads, so a transparent image does not sit on a card.
  holdImageBox(img) {
    if (img.complete && img.naturalWidth > 1) return;
    img.classList.add('media-pending');
    const done = () => img.classList.remove('media-pending');
    img.addEventListener('load', done, { once: true });
    img.addEventListener('error', done, { once: true });
  },

  // Swift starts every video with preload="none" (PreviewMedia
  // .deferredVideoTags), since one that loads holds back the page's load
  // event. Once the page is up, a video near the view loads its metadata
  // and moves to its first frame, so the player shows a picture instead of
  // an empty box. A video with its own poster keeps showing that.
  prepareVideos() {
    const videos = document.querySelectorAll('#write video[data-preload]');
    if (!videos.length) return;
    const start = (video) => {
      video.removeAttribute('data-preload');
      if (video.hasAttribute('poster') || !video.paused) return;
      video.preload = 'metadata';
      video.addEventListener('loadedmetadata', () => {
        if (video.paused && video.currentTime === 0) video.currentTime = 0.001;
      }, { once: true });
      video.load();
    };
    if (!('IntersectionObserver' in window)) {
      videos.forEach(start);
      return;
    }
    if (!this._videoObserver) {
      this._videoObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
          if (!entry.isIntersecting) return;
          observer.unobserve(entry.target);
          start(entry.target);
        });
      }, { rootMargin: '400px' });
    }
    videos.forEach(video => this._videoObserver.observe(video));
  },

  // While an image runs under the top edge, two paper-coloured corner pieces
  // sit on its top corners, so it keeps its rounded corners there instead of
  // ending in a straight cut. They follow that image's own left edge, width
  // and radius, so narrow and indented images are covered too, and stay
  // hidden at the top of the page, which is also where PNG export captures.
  setupScrollCorners() {
    if (document.querySelector('.scroll-corners')) return;
    const corners = document.createElement('div');
    corners.className = 'scroll-corners';
    document.body.appendChild(corners);
    let shown = '';
    const place = () => {
      let target = null;
      if (window.scrollY > 0) {
        for (const media of document.querySelectorAll('#write img, #write video')) {
          const rect = media.getBoundingClientRect();
          if (rect.top < 0 && rect.bottom > 0 && rect.width > 0) {
            target = { rect, radius: parseFloat(getComputedStyle(media).borderTopLeftRadius) || 0 };
            break;
          }
        }
      }
      // Reads first, then at most one write, and none while nothing changed.
      const next = target && target.radius > 0 ? `${target.rect.left}|${target.rect.width}|${target.radius}` : '';
      if (next === shown) return;
      shown = next;
      if (!next) {
        corners.classList.remove('visible');
        return;
      }
      corners.style.left = target.rect.left + 'px';
      corners.style.width = target.rect.width + 'px';
      corners.style.setProperty('--corner-radius', target.radius + 'px');
      corners.classList.add('visible');
    };
    window.addEventListener('scroll', place, { passive: true });
    window.addEventListener('resize', place);
    place();
  },

  setupImageZoom() {
    const zoomImgs = document.querySelectorAll('#write>img, #write>p>img, #write>table img');
    if (zoomImgs.length > 0 && window.Lightense) {
      window.Lightense(zoomImgs, {
        background: this.isDarkMode() ? 'rgba(33, 38, 43, .8)' : 'rgba(255, 255, 255, .8)',
      });
    }
  },

  setupHeaderAnchors() {
    // Generate unique IDs for headings, handling duplicates
    const usedIds = new Set();
    document.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach((h) => {
      let baseId = h.innerText.trim();
      let id = baseId;
      let counter = 1;

      while (usedIds.has(id)) {
        id = `${baseId}-${counter}`;
        counter++;
      }

      h.id = id;
      usedIds.add(id);
    });

    document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
      anchor.addEventListener('click', function (e) {
        e.preventDefault();
        document.querySelector(decodeURIComponent(this.getAttribute('href')))?.scrollIntoView({
          behavior: 'smooth',
        });
      });
    });
  },

  initializeCore() {
    if (window.hljs) {
      hljs.configure({ cssSelector: 'pre code' });
      hljs.highlightAll();
    }

    this.escapeCurrencyLikeMath();

    if (window.EmojiConvertor) {
      const writeElement = document.getElementById('write');
      const emoji = new EmojiConvertor();

      // Use TreeWalker to replace emoji only in text nodes, avoiding code blocks
      const walker = document.createTreeWalker(
        writeElement,
        NodeFilter.SHOW_TEXT,
        {
          acceptNode: function(node) {
            // Skip text nodes inside code or pre elements
            let parent = node.parentElement;
            while (parent && parent !== writeElement) {
              if (parent.tagName === 'CODE' || parent.tagName === 'PRE') {
                return NodeFilter.FILTER_REJECT;
              }
              parent = parent.parentElement;
            }
            return NodeFilter.FILTER_ACCEPT;
          }
        }
      );

      const nodesToReplace = [];
      let node;
      while (node = walker.nextNode()) {
        if (/:[^:\s]*(?:::[^:\s]*)*:/.test(node.textContent)) {
          nodesToReplace.push(node);
        }
      }

      // Replace emoji in collected text nodes
      nodesToReplace.forEach(textNode => {
        const replacedHTML = emoji.replace_colons(textNode.textContent);
        if (replacedHTML !== textNode.textContent) {
          const span = document.createElement('span');
          span.innerHTML = replacedHTML;
          textNode.parentNode.replaceChild(span, textNode);
        }
      });
    }
  },

  escapeCurrencyLikeMath() {
    const writeElement = document.getElementById('write');
    if (!writeElement) {
      return;
    }

    const walker = document.createTreeWalker(
      writeElement,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode(node) {
          if (!node.textContent.includes('$')) {
            return NodeFilter.FILTER_REJECT;
          }

          let parent = node.parentElement;
          while (parent && parent !== writeElement) {
            const tagName = parent.tagName;
            if (
              tagName === 'CODE' ||
              tagName === 'PRE' ||
              tagName === 'SCRIPT' ||
              tagName === 'STYLE' ||
              parent.classList.contains('katex') ||
              parent.classList.contains('skip-math-dollar')
            ) {
              return NodeFilter.FILTER_REJECT;
            }
            parent = parent.parentElement;
          }

          return NodeFilter.FILTER_ACCEPT;
        }
      }
    );

    const nodesToUpdate = [];
    let currentNode;
    while ((currentNode = walker.nextNode())) {
      nodesToUpdate.push(currentNode);
    }

    const currencyRegex = /^\$(?![0-9]+(?:[.,][0-9]+)?[$(])([0-9]+(?:[.,][0-9]+)?)(?=$|[^0-9A-Za-z+\-*/=<>^_\\])/;

    nodesToUpdate.forEach(node => {
      const text = node.textContent;
      if (!text.includes('$')) {
        return;
      }

      const fragment = document.createDocumentFragment();
      let index = 0;
      let lastIndex = 0;
      let replaced = false;

      while (index < text.length) {
        const char = text[index];

        if (char === '\\' && index + 1 < text.length && text[index + 1] === '$') {
          index += 2;
          continue;
        }

        if (char === '$') {
          const remaining = text.slice(index);
          const match = remaining.match(currencyRegex);
          if (match) {
            if (index > lastIndex) {
              fragment.appendChild(document.createTextNode(text.slice(lastIndex, index)));
            }
            const span = document.createElement('span');
            span.className = 'skip-math-dollar';
            span.textContent = match[0];
            fragment.appendChild(span);
            index += match[0].length;
            lastIndex = index;
            replaced = true;
            continue;
          }
        }

        index += 1;
      }

      if (!replaced) {
        return;
      }

      if (lastIndex < text.length) {
        fragment.appendChild(document.createTextNode(text.slice(lastIndex)));
      }

      node.parentNode?.replaceChild(fragment, node);
    });
  },

  onDOMReady(callback) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', callback);
    } else {
      callback();
    }
  },

  // A live update replaces only the top-level blocks that changed, as VS
  // Code's Markdown preview reconciles its page. Replacing the whole body on
  // every save reloaded every image and redrew every diagram and formula, so
  // a note being written to, from the editor beside it or from another app,
  // blinked on each write. A block is matched by its rendered HTML without
  // its source positions, which a line added above it shifts.
  // Source positions count from the block's own first line, so a block that
  // only moved still matches, while one whose inner lines changed (a blank
  // line added inside a quote renders the same HTML) does not: shifting it
  // as a whole would leave its task boxes pointing at the wrong lines.
  blockKey(node) {
    if (node.nodeType === Node.ELEMENT_NODE) {
      const base = parseInt(node.getAttribute('data-sourcepos'), 10) || 0;
      return node.outerHTML.replace(/ data-sourcepos="(\d+)(:\d+-)(\d+)(:\d+)"/g,
        (_, a, mid, b, end) => ` data-sourcepos="${a - base}${mid}${b - base}${end}"`);
    }
    if (node.nodeType === Node.TEXT_NODE) return '#text' + node.textContent;
    return '#node';
  },

  blockEntry(node) {
    const pos = node.nodeType === Node.ELEMENT_NODE ? node.getAttribute('data-sourcepos') : null;
    return { node, key: this.blockKey(node), line: pos ? parseInt(pos, 10) : null };
  },

  // Taken while the page still holds the renderer's HTML, before highlighting,
  // tables and lazy images change it, so the first update can match blocks.
  recordBlocks(container) {
    if (!container) return;
    container.__miaoyanBlocks = Array.from(container.childNodes).map(node => this.blockEntry(node));
  },

  shiftSourceLines(root, delta) {
    if (root.nodeType !== Node.ELEMENT_NODE) return;
    const shift = (el) => {
      const pos = el.getAttribute('data-sourcepos');
      if (!pos) return;
      el.setAttribute('data-sourcepos', pos.replace(/^(\d+)(:\d+-)(\d+)/, (_, a, mid, b) => `${+a + delta}${mid}${+b + delta}`));
    };
    shift(root);
    root.querySelectorAll('[data-sourcepos]').forEach(shift);
  },

  // Everything the page does to a note's freshly rendered HTML: at load
  // (index.html) and again for each note opened in place.
  renderPage() {
    this.initializeCore();
    this.setupHeaderAnchors();
    this.optimizeImages();
    this.setupImageZoom();
    this.setupScrollCorners();
    if (window.DiagramHandler) DiagramHandler.initializeAll();
    this.wrapWideTables();
    this.setupInteractiveCheckboxes();

    // Deferred so it does not hold up the first paint.
    const renderMath = () => {
      if (typeof renderMathInElement !== 'function') return;
      renderMathInElement(document.body, {
        delimiters: [
          { left: "$$", right: "$$", display: true },
          { left: "$", right: "$", display: false },
          { left: "\\(", right: "\\)", display: false },
          { left: "\\[", right: "\\]", display: true }
        ],
        processEscapes: true,
        ignoredClasses: ['katex-display', 'katex', 'skip-math-dollar']
      });
    };
    if ('requestIdleCallback' in window) {
      requestIdleCallback(renderMath, { timeout: 200 });
    } else {
      setTimeout(renderMath, 0);
    }
  },

  // Opens another note in this page instead of loading the page again, as
  // VS Code's preview swaps its body when the document changes. A reload
  // parsed every script again and the preview went blank between notes.
  showNote(html) {
    const container = document.getElementById('write');
    if (!container) return false;
    container.__miaoyanBlocks = null;
    this.patchContent(container, html);
    window.scrollTo(0, 0);
    this.renderPage();
    window.MiaoYanTOC.refresh();
    if (window.__miaoyanSync) window.__miaoyanSync.rebuild();
    return true;
  },

  // Puts `html` into `container` and returns the nodes it inserted.
  patchContent(container, html) {
    const template = document.createElement('template');
    template.innerHTML = html;
    const fresh = Array.from(template.content.childNodes).map(node => this.blockEntry(node));
    const old = container.__miaoyanBlocks;
    // A tracked block is the container's child itself, or, for a table, the
    // scroll box it was wrapped in. Anything else on the page means the
    // record no longer describes it, and the page is rebuilt.
    const children = container.childNodes;
    const tops = old ? old.map(block => {
      let node = block.node;
      while (node && node.parentNode !== container) node = node.parentNode;
      return node;
    }) : null;
    const usable = tops && tops.length === children.length && tops.every((top, i) => top === children[i]);
    if (!usable) {
      container.replaceChildren(...fresh.map(block => block.node));
      container.__miaoyanBlocks = fresh;
      return fresh.map(block => block.node);
    }

    let start = 0;
    while (start < old.length && start < fresh.length && old[start].key === fresh[start].key) start++;
    let endOld = old.length;
    let endFresh = fresh.length;
    while (endOld > start && endFresh > start && old[endOld - 1].key === fresh[endFresh - 1].key) {
      endOld--;
      endFresh--;
    }

    const keep = (i, now) => {
      const was = old[i];
      if (was.line != null && now.line != null && was.line !== now.line) this.shiftSourceLines(tops[i], now.line - was.line);
      return { node: was.node, key: now.key, line: now.line };
    };

    // Between the shared start and end, an edit near the top and another
    // further down leave unchanged blocks in the middle too. Elements are
    // matched in order by key and reused; whitespace text is cheap, so it is
    // always taken fresh. The search looks a bounded way ahead, so a note
    // rewritten throughout costs no more than replacing it.
    const middle = [];
    const reused = new Set();
    let cursor = start;
    for (let j = start; j < endFresh; j++) {
      const now = fresh[j];
      let match = -1;
      if (now.node.nodeType === Node.ELEMENT_NODE) {
        for (let i = cursor; i < endOld && i < cursor + 64; i++) {
          if (old[i].node.nodeType === Node.ELEMENT_NODE && old[i].key === now.key) { match = i; break; }
        }
      }
      if (match >= 0) {
        reused.add(match);
        cursor = match + 1;
        middle.push({ block: keep(match, now), dom: tops[match], fresh: false });
      } else {
        middle.push({ block: now, dom: now.node, fresh: true });
      }
    }
    for (let i = start; i < endOld; i++) if (!reused.has(i)) tops[i].remove();
    // Placed from the end backwards; a reused block already in place is not
    // moved, so its image or diagram is left alone.
    let ref = endOld < old.length ? tops[endOld] : null;
    for (let k = middle.length - 1; k >= 0; k--) {
      const dom = middle[k].dom;
      if (dom.nextSibling !== ref || dom.parentNode !== container) container.insertBefore(dom, ref);
      ref = dom;
    }

    const blocks = [];
    for (let i = 0; i < start; i++) blocks.push(keep(i, fresh[i]));
    middle.forEach(entry => blocks.push(entry.block));
    for (let k = 0; endOld + k < old.length; k++) blocks.push(keep(endOld + k, fresh[endFresh + k]));
    container.__miaoyanBlocks = blocks;
    return middle.filter(entry => entry.fresh).map(entry => entry.dom);
  }
};

// TOC configuration constants
const TOC_CONFIG = {
  MIN_HEADINGS: 2,
  MIN_SCREEN_WIDTH: 600,
  AUTO_HIDE_DELAY: 3000,
  INIT_DELAY: 200,
  SCROLL_OFFSET_TOP: 60,
  SCROLL_OFFSET_BOTTOM: 80,
  SCROLL_DEBOUNCE: 100
};

(function() {
  // Default no-op so a menu/shortcut trigger never hits an undefined call
  // before initTOC runs (or when there are too few headings to build a TOC).
  window.MiaoYanTOC = { toggle: function() {}, refresh: function() {} };

  // Wired once per page. A note opened in place (MiaoYanCommon.showNote)
  // calls refresh, which recounts the headings and rebuilds the list.
  let hasTOC = false;
  let refreshTOC = () => {};

  function initTOC() {
    const nav = document.querySelector('.toc-nav');
    const trigger = document.querySelector('.toc-hover-trigger');
    const tocContainer = document.querySelector('.toc-content');
    const pinBtn = document.querySelector('.toc-pin-btn');
    if (!nav || !trigger || !tocContainer || nav.__miaoyanTOC) return;
    nav.__miaoyanTOC = true;

    let fadeTimer = null;
    let scrollTimeout = null;
    let isPinned = localStorage.getItem('toc-pinned') === 'true';

    const startAutoHideTimer = () => {
      if (isPinned) return;
      clearTimeout(fadeTimer);
      fadeTimer = setTimeout(() => {
        trigger.style.opacity = '0';
      }, TOC_CONFIG.AUTO_HIDE_DELAY);
    };

    const cancelAutoHideTimer = () => {
      clearTimeout(fadeTimer);
      trigger.style.opacity = '';
    };

    const show = () => {
      if (!hasTOC) return;
      nav.classList.add('active');
      trigger.classList.add('hidden');
      cancelAutoHideTimer();
    };

    const hide = () => {
      if (isPinned) return;
      nav.classList.remove('active');
      trigger.classList.remove('hidden');
    };

    // Menu / keyboard toggle: opening pins the panel so it stays visible
    // instead of auto-hiding; closing unpins and hides. Bypasses the
    // isPinned guard in hide() on purpose so the shortcut always works.
    const menuToggle = () => {
      if (!hasTOC) return;
      if (nav.classList.contains('active')) {
        isPinned = false;
        localStorage.setItem('toc-pinned', 'false');
        nav.classList.remove('pinned');
        nav.classList.remove('active');
        trigger.classList.remove('hidden');
        startAutoHideTimer();
      } else {
        isPinned = true;
        localStorage.setItem('toc-pinned', 'true');
        nav.classList.add('pinned');
        show();
      }
    };
    window.MiaoYanTOC = { toggle: menuToggle, refresh: () => refreshTOC() };

    // Auto-scroll active link into view within TOC panel
    const scrollToActive = () => {
      const activeLink = tocContainer.querySelector('.is-active-link');
      if (!activeLink || !nav.classList.contains('active')) return;

      const linkTop = activeLink.offsetTop;
      const navScroll = nav.scrollTop;
      const navHeight = nav.clientHeight;

      if (linkTop < navScroll + TOC_CONFIG.SCROLL_OFFSET_TOP ||
          linkTop > navScroll + navHeight - TOC_CONFIG.SCROLL_OFFSET_BOTTOM) {
        nav.scrollTo({ top: linkTop - TOC_CONFIG.SCROLL_OFFSET_TOP, behavior: 'smooth' });
      }
    };

    const observer = new MutationObserver(() => {
      clearTimeout(scrollTimeout);
      scrollTimeout = setTimeout(scrollToActive, TOC_CONFIG.SCROLL_DEBOUNCE);
    });

    observer.observe(tocContainer, { subtree: true, attributeFilter: ['class'] });

    // Pin button handler
    if (pinBtn) {
      pinBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        isPinned = !isPinned;
        localStorage.setItem('toc-pinned', isPinned);

        if (isPinned) {
          nav.classList.add('pinned');
          show();
        } else {
          nav.classList.remove('pinned');
          hide();
          startAutoHideTimer();
        }
      });
    }

    // Initialize pinned state
    if (isPinned) {
      nav.classList.add('pinned');
      show();
    }

    trigger.addEventListener('mouseenter', show);
    nav.addEventListener('mouseenter', show);

    trigger.addEventListener('mouseover', () => {
      cancelAutoHideTimer();
      trigger.style.opacity = '0.2';
    });

    document.addEventListener('mousedown', (e) => {
      if (nav.classList.contains('active') &&
          !nav.contains(e.target) &&
          !trigger.contains(e.target)) {
        hide();
      }
    });

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && nav.classList.contains('active')) {
        hide();
      }
    });

    const handleResize = () => {
      const narrow = window.innerWidth < TOC_CONFIG.MIN_SCREEN_WIDTH;
      trigger.style.display = narrow || !hasTOC ? 'none' : '';
      if (narrow) hide();
    };
    window.addEventListener('resize', handleResize);

    // Enough headings (h1 to h3) for a TOC, or the trigger stays hidden.
    refreshTOC = () => {
      hasTOC = document.querySelectorAll('#write h1, #write h2, #write h3').length >= TOC_CONFIG.MIN_HEADINGS;
      if (window.tocbot) {
        tocbot.destroy();
        if (hasTOC) {
          // tocbot adds its smooth-scroll click listener on every init; the
          // first one keeps working for later notes, so it is added once.
          const smooth = !nav.__miaoyanSmooth;
          nav.__miaoyanSmooth = true;
          tocbot.init({
            tocSelector: '.toc-content',
            contentSelector: '#write',
            headingSelector: 'h1, h2, h3',
            hasInnerContainers: true,
            collapseDepth: 3,
            scrollSmooth: smooth,
            scrollSmoothDuration: 200,
            headingsOffset: 80,
            ignoreHiddenElements: true
          });
        }
      }
      if (!hasTOC) {
        nav.classList.remove('active');
        trigger.classList.remove('hidden');
      } else if (isPinned) {
        nav.classList.add('pinned');
        show();
      }
      handleResize();
      // Each note shows the trigger again before it fades, as a fresh page did.
      cancelAutoHideTimer();
      if (!isPinned) startAutoHideTimer();
    };
    refreshTOC();
  }

  // Wait for tocbot to be available and render TOC
  MiaoYanCommon.onDOMReady(() => {
    setTimeout(() => {
      if (window.tocbot && document.querySelector('.toc-nav')) {
        initTOC();
      }
    }, TOC_CONFIG.INIT_DELAY);
  });
})();

MiaoYanCommon.recordBlocks(document.getElementById('write'));

window.MiaoYanCommon = MiaoYanCommon;
