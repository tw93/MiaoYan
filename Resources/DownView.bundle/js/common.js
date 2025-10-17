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

  setupTextSelection() {
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

  setupInteractiveCheckboxes() {
    this.setupCheckboxes();

    const checkboxList = document.querySelectorAll('input[type=checkbox]');
    checkboxList.forEach((checkbox, i) => {
      if (checkbox.parentNode.nodeName === 'LI' && checkbox.hasAttribute('checked')) {
        checkbox.parentNode.classList.add('strike');
      }

      checkbox.disabled = false;
      checkbox.dataset.checkbox = i;

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
    if (window.webkit?.messageHandlers.checkbox) {
      window.webkit.messageHandlers.checkbox.postMessage(id);
    }

    const input = document.createElement('input');
    input.type = 'checkbox';
    input.dataset.checkbox = id;

    if (!element.hasAttribute('checked')) {
      input.defaultChecked = true;
      if (element.parentNode.nodeName === 'LI') {
        element.parentNode.classList.add('strike');
      }
    }

    element.parentNode.replaceChild(input, element);
    input.addEventListener('click', () => {
      this.handleCheckboxClick(input);
    });
  },

  optimizeImages() {
    const allImages = document.querySelectorAll('img');
    allImages.forEach((img, index) => {
      img.setAttribute('loading', index < 3 ? 'eager' : 'lazy');
      img.style.maxWidth = '100%';
      img.style.height = 'auto';
    });
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

  onDOMReady(callback) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', callback);
    } else {
      callback();
    }
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
  function initTOC() {
    const nav = document.querySelector('.toc-nav');
    const trigger = document.querySelector('.toc-hover-trigger');
    if (!nav || !trigger) return;

    // Check if we have enough headings (only count h1-h3 for TOC)
    const headings = document.querySelectorAll('#write h1, #write h2, #write h3');
    if (headings.length < TOC_CONFIG.MIN_HEADINGS) {
      trigger.style.display = 'none';
      return;
    }

    // Initialize tocbot (only show 3 levels: h1, h2, h3)
    if (window.tocbot) {
      tocbot.init({
        tocSelector: '.toc-nav',
        contentSelector: '#write',
        headingSelector: 'h1, h2, h3',
        hasInnerContainers: true,
        collapseDepth: 3,
        scrollSmooth: true,
        scrollSmoothDuration: 200,
        headingsOffset: 80,
        ignoreHiddenElements: true
      });
    }

    let fadeTimer = null;
    let scrollTimeout = null;

    const startAutoHideTimer = () => {
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
      nav.classList.add('active');
      trigger.classList.add('hidden');
      cancelAutoHideTimer();
    };

    const hide = () => {
      nav.classList.remove('active');
      trigger.classList.remove('hidden');
    };

    // Auto-scroll active link into view within TOC panel
    const scrollToActive = () => {
      const activeLink = nav.querySelector('.is-active-link');
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

    observer.observe(nav, { subtree: true, attributeFilter: ['class'] });

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
      trigger.style.display = window.innerWidth < TOC_CONFIG.MIN_SCREEN_WIDTH ? 'none' : '';
      if (window.innerWidth < TOC_CONFIG.MIN_SCREEN_WIDTH) hide();
    };
    window.addEventListener('resize', handleResize);
    handleResize();

    startAutoHideTimer();
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

window.MiaoYanCommon = MiaoYanCommon;
