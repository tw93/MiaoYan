/**
 * Diagram Handler (Mermaid, PlantUML, Markmap)
 */

const DiagramHandler = {
  initializeAll() {
    const isDark = this.isDarkMode();

    window.ThemeConfig?.applyCSSVariables?.(isDark);

    this.initializeMermaid();
    this.initializePlantUML();
    this.initializeMarkmap();
    this.updateContainerStyles();
  },

  initializeMermaid() {
    if (!window.mermaid) return;

    const isDark = this.isDarkMode();
    const config = window.ThemeConfig?.getMermaidConfig(isDark) || {};

    mermaid.initialize(config);
    window.mermaid.init(undefined, document.querySelectorAll('.language-mermaid'));
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

  processPlantumlElement(code) {
    const existingImage = code.parentNode.querySelector('.plantuml-image');
    if (existingImage) existingImage.remove();

    const image = document.createElement('img');
    image.className = 'plantuml-image';
    image.loading = 'lazy';

    let plantumlContent = code.innerText;
    const isDark = this.isDarkMode();
    const skinparams = window.ThemeConfig?.getPlantUMLSkinparams(isDark) || '';

    // Strip existing skinparam directives before injecting the themed preset
    plantumlContent = plantumlContent.replace(/skinparam\s+[^\n]*/g, '');
    plantumlContent = skinparams + '\n' + plantumlContent;

    image.src = 'https://www.plantuml.com/plantuml/svg/~1' + window.plantumlEncoder.encode(plantumlContent);

    image.onload = () => {
      this.stylePlantumlImage(image, code, isDark);
    };

    image.onerror = () => {
      console.warn('PlantUML image failed to load, showing code block instead');
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
    const isDark = this.isDarkMode();
    const colorOptions = window.ThemeConfig?.getMarkmapColors(isDark) || {};

    element.style.visibility = 'hidden';
    element.style.overflow = 'visible';
    element.style.minHeight = 'var(--markmap-height)';
    element.style.height = 'var(--markmap-height)';
    element.style.maxHeight = 'none';
    element.style.pointerEvents = 'none';
    element.style.textAlign = 'center';
    element.style.lineHeight = '1';
    element.style.boxSizing = 'border-box';

    element.dataset.markmapColors = JSON.stringify(colorOptions);
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

          try {
            autoLoader.render(element);
            element.dataset.markmapRendered = 'true';

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
