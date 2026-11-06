/**
 * Diagram Handler (Mermaid, PlantUML, Markmap)
 */

const DiagramHandler = {
  // Performance optimization: cache rendered diagram content hashes
  _renderedHashes: new Map(),

  createLoadingIndicator(diagramType) {
    const loader = document.createElement('div');
    loader.className = 'diagram-loading';
    loader.innerHTML = `<span style="opacity: 0.6; font-size: 12px;">Rendering ${diagramType}...</span>`;
    loader.style.cssText = 'padding: 10px; text-align: center; color: var(--text-color);';
    return loader;
  },

  showError(loader, message) {
    loader.innerHTML = `<span style="opacity: 0.5; font-size: 12px; color: #f44;">${message}</span>`;
    setTimeout(() => loader.remove(), 2000);
  },

  initializeAll() {
    const isDark = this.isDarkMode();

    window.ThemeConfig?.applyCSSVariables?.(isDark);

    this.initializeMermaid();
    this.initializePlantUML();
    this.initializeMarkmap();
    this.updateContainerStyles();
  },

  // Simple hash function for content comparison
  _simpleHash(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      hash = ((hash << 5) - hash) + str.charCodeAt(i);
      hash |= 0; // Convert to 32bit integer
    }
    return hash;
  },

  // Cache for SVG content to support zero-delay re-rendering
  _svgCache: new Map(),

  async initializeMermaid() {
    if (!window.mermaid) return;

    const isDark = this.isDarkMode();
    const config = window.ThemeConfig?.getMermaidConfig(isDark) || {};

    mermaid.initialize(config);

    const mermaidElements = document.querySelectorAll('.language-mermaid');

    const renderPromises = Array.from(mermaidElements).map(async (element) => {
      if (element.dataset.processed === 'true') return;

      const content = element.dataset.mermaidSource || element.textContent || '';
      if (!content.trim()) return;
      // The source, kept for drawing the diagram again in the other theme.
      element.dataset.mermaidSource = content;

      // Light and dark draw the same source differently.
      const hash = this._simpleHash((isDark ? 'dark:' : 'light:') + content);

      // 1. Check Cache
      if (this._svgCache.has(hash)) {
        element.innerHTML = this._svgCache.get(hash);
        element.dataset.mermaidRendered = 'true';
        element.setAttribute('data-processed', 'true');
        return;
      }

      // 2. Render fresh
      const elementId = 'mermaid-' + Math.random().toString(36).substr(2, 9);
      const loader = this.createLoadingIndicator('Mermaid diagram');
      element.parentNode.insertBefore(loader, element);

      try {
        const { svg } = await mermaid.render(elementId, content);
        this._svgCache.set(hash, svg);
        element.innerHTML = svg;
        element.dataset.mermaidRendered = 'true';
        element.setAttribute('data-processed', 'true');
      } catch (error) {
        console.error('Mermaid rendering failed:', error);
        // Keep the original fenced-block source in place; do not inject verbose error HTML
        // into the DOM (it leaks into PDF exports and prints).
        element.dataset.mermaidRendered = 'failed';
        element.setAttribute('data-processed', 'true');
        const pre = element.closest('pre');
        if (pre) {
          pre.classList.add('mermaid-source-fallback');
        }
      } finally {
        if (loader.parentNode) {
          loader.remove();
        }
      }
    });

    await Promise.all(renderPromises);
  },

  initializePlantUML() {
    if (typeof window.plantumlEncoder === 'undefined') {
      console.warn('PlantUML encoder not loaded, retrying...');
      setTimeout(() => this.initializePlantUML(), 500);
      return;
    }

    const plantumlElements = document.querySelectorAll('.language-plantuml');
    plantumlElements.forEach(code => {
      if (code.dataset.processed === 'true') return;
      this.processPlantumlElement(code);
    });
  },

  // The server URL for a PlantUML block drawn in the given theme.
  plantumlImageURL(code, isDark) {
    let plantumlContent = code.dataset.originalContent || code.innerText;
    const skinparams = window.ThemeConfig?.getPlantUMLSkinparams(isDark) || '';

    // Strip existing skinparam directives before injecting the themed preset
    plantumlContent = plantumlContent.replace(/skinparam\s+[^\n]*/g, '');
    plantumlContent = skinparams + '\n' + plantumlContent;

    return 'https://www.plantuml.com/plantuml/svg/~1' + window.plantumlEncoder.encode(plantumlContent);
  },

  processPlantumlElement(code) {
    // A retheme still waiting on its image no longer applies to this block.
    code._plantumlRetheme = null;
    const existingImage = code.parentNode.querySelector('.plantuml-image');
    if (existingImage) existingImage.remove();

    const existingLoader = code.parentNode.querySelector('.diagram-loading');
    if (existingLoader) existingLoader.remove();

    const loader = this.createLoadingIndicator('PlantUML diagram');
    code.parentNode.insertBefore(loader, code);

    const image = document.createElement('img');
    image.className = 'plantuml-image';
    image.loading = 'lazy';

    const isDark = this.isDarkMode();
    image.src = this.plantumlImageURL(code, isDark);

    image.onload = () => {
      loader.remove();
      this.stylePlantumlImage(image, code, isDark);
    };

    image.onerror = () => {
      console.warn('PlantUML image failed to load, showing code block instead');
      this.showError(loader, 'Failed to load diagram');
      code.style.display = 'block';
      image.style.display = 'none';
    };

    code.parentNode.insertBefore(image, code);
    code.style.display = 'none';

    if (!code.dataset.originalContent) {
      code.dataset.originalContent = code.innerText;
    }

    code.dataset.processed = 'true';
  },

  stylePlantumlImage(image, code, isDark) {
    code.style.display = 'none';
    image.style.display = 'block';
    image.style.maxWidth = '100%';
    image.style.width = 'auto';
    image.style.height = 'auto';
    image.style.margin = '0 auto';

    if (image.parentNode) {
      image.parentNode.classList.add('plantuml-container');
    }
  },

  // Draws the diagrams already on the page again in the current theme:
  // Mermaid, PlantUML and Markmap bake their palette into what they draw.
  retheme() {
    document.querySelectorAll('.language-mermaid[data-mermaid-source]').forEach((element) => {
      element.textContent = element.dataset.mermaidSource;
      element.removeAttribute('data-processed');
      delete element.dataset.mermaidRendered;
      element.closest('pre')?.classList.remove('mermaid-source-fallback');
    });
    this.initializeMermaid();
    document.querySelectorAll('code.language-plantuml[data-processed="true"]').forEach((code) => {
      this.rethemePlantumlElement(code);
    });
    let markmapChanged = false;
    document.querySelectorAll('.language-markmap[data-markmap-source]').forEach((element) => {
      if (element.dataset.markmapRendered !== 'true') return;
      element.textContent = element.dataset.markmapSource;
      delete element.dataset.markmapRendered;
      markmapChanged = true;
    });
    if (markmapChanged) this.renderMarkmap();
  },

  // A diagram already on screen stays until its redrawn image has loaded,
  // and stays for good if that request fails (offline, server error), so a
  // theme switch never turns a drawn diagram back into source text. A block
  // with nothing drawn yet (still loading lazily, or failed before) is
  // processed as on first load.
  rethemePlantumlElement(code) {
    const shown = code.parentNode?.querySelector('.plantuml-image');
    const isDrawn = shown && shown.complete && shown.naturalWidth > 0 && shown.style.display !== 'none';
    if (!isDrawn) {
      this.processPlantumlElement(code);
      return;
    }
    const isDark = this.isDarkMode();
    const replacement = document.createElement('img');
    replacement.className = 'plantuml-image';
    code._plantumlRetheme = replacement;
    replacement.onload = () => {
      if (code._plantumlRetheme !== replacement || !shown.isConnected) return;
      code._plantumlRetheme = null;
      shown.replaceWith(replacement);
      this.stylePlantumlImage(replacement, code, isDark);
    };
    replacement.onerror = () => {
      if (code._plantumlRetheme === replacement) code._plantumlRetheme = null;
      console.warn('PlantUML image failed to load in the new theme, keeping the current one');
    };
    replacement.src = this.plantumlImageURL(code, isDark);
  },

  initializeMarkmap() {
    const markMapElements = document.querySelectorAll('.language-markmap');
    if (!markMapElements || markMapElements.length === 0) return;

    markMapElements.forEach((element) => {
      this.processMarkmapElement(element);
    });

    // Add delay to ensure DOM is fully ready
    setTimeout(() => {
      this.renderMarkmap();
    }, 100);
  },

  processMarkmapElement(element) {
    if (!element.dataset.markmapSource) element.dataset.markmapSource = element.textContent;

    element.style.visibility = 'hidden';
    element.style.overflow = 'visible';
    element.style.minHeight = 'var(--markmap-height)';
    element.style.height = 'var(--markmap-height)';
    element.style.maxHeight = 'none';
    element.style.pointerEvents = 'none';
    element.style.textAlign = 'center';
    element.style.lineHeight = '1';
    element.style.boxSizing = 'border-box';
  },

  renderMarkmap() {
    if (!window.markmap?.autoLoader || typeof window.markmap.autoLoader.render !== 'function') {
      setTimeout(() => this.renderMarkmap(), 100);
      return;
    }

    const autoLoader = window.markmap.autoLoader;
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        const markMapElements = document.querySelectorAll('.language-markmap');
        markMapElements.forEach((element) => {
          if (element.dataset.markmapRendered === 'true' || element.querySelector('svg')) {
            return;
          }

          const loader = this.createLoadingIndicator('Markmap');
          element.parentNode.insertBefore(loader, element);

          try {
            autoLoader.render(element);
            element.dataset.markmapRendered = 'true';
            loader.remove();

            // Set SVG height after rendering
            setTimeout(() => {
              const svg = element.querySelector('svg');
              if (svg) {
                const containerHeight = parseInt(element.style.height) || 450;
                const svgHeight = Math.max(containerHeight - 16, 400);
                svg.style.height = svgHeight + 'px';
                svg.style.width = '100%';
                svg.style.overflow = 'visible';

                if (element.markmap && typeof element.markmap.fit === 'function') {
                  element.markmap.fit();
                }

                element.classList.add('markmap');
                element.style.visibility = 'visible';
              }
            }, 150);
          } catch (error) {
            console.error('Failed to render markmap block', error);
            this.showError(loader, 'Failed to render Markmap');
          }
        });
      });
    });
  },

  updateContainerStyles() {
    document.querySelectorAll('pre').forEach(pre => {
      if (pre.querySelector('.plantuml-image')) pre.classList.add('plantuml-image-container');
      if (pre.querySelector('.language-mermaid')) pre.classList.add('mermaid-image-container');
      if (pre.querySelector('.language-markmap')) pre.classList.add('markmap-image-container');
    });
  },

  initializeMarkmapForPPT() {
    let markMapList = document.querySelectorAll('.language-markmap');

    // Fallback: inspect generic code blocks for ```markmap fences
    if (markMapList.length === 0) {
      const codeBlocks = document.querySelectorAll('pre code');
      codeBlocks.forEach(block => {
        const text = block.textContent || '';
        if (text.trim().startsWith('markmap') || text.includes('```markmap')) {
          block.classList.add('language-markmap');
        }
      });
      markMapList = document.querySelectorAll('.language-markmap');
    }

    markMapList.forEach((item, i) => {
      this.processMarkmapForPPT(item, i);
    });
  },

  processMarkmapForPPT(item, index) {
    const markMapName = 'markmap-' + index;
    const markMapChildClass = '.' + markMapName + ' .markmap';

    let heightAttr = item.textContent.match(/\<\!\-\-markmap-height\=(\S*)\-\-\>/);

    const content = item.textContent || '';
    const lines = content.split('\n').filter(line => line.trim());
    const maxDepth = Math.max(0, ...lines.map(line => {
      const match = line.match(/^(\s*)([-*+]|\d+\.)/);
      return match ? Math.floor(match[1].length / 2) : 0;
    }));

    let autoHeight = Math.min(400, Math.max(250, 250 + maxDepth * 30 + lines.length * 15));
    let height = autoHeight + 'px';

    if (heightAttr && heightAttr.length > 0 && !isNaN(heightAttr[1])) {
      height = heightAttr[1] + 'px';
    }

    item.classList.add('markmap');
    item.classList.add(markMapName);

    setTimeout(() => {
      const markMapItem = document.querySelector('.' + markMapName);
      if (markMapItem) {
        markMapItem.style.maxHeight = height;
        markMapItem.style.height = height;

        setTimeout(() => {
          const markMapItemChild = document.querySelector(markMapChildClass);
          if (markMapItemChild) {
            markMapItemChild.style.height = height;

            if (window.markmap && markMapItemChild.markmap) {
              markMapItemChild.markmap.fit();
            }
          }
        }, 50);
      }
    }, 10);
  },

  isDarkMode() {
    // Delegate to ThemeConfig for consistent dark mode detection
    return window.ThemeConfig?.isDarkMode?.() || 'CUSTOM_CSS' === 'darkmode';
  }
};

window.DiagramHandler = DiagramHandler;
