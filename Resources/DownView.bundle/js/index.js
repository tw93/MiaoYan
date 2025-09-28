/**
 * MiaoYan Common Utilities
 * Shared helpers to avoid duplicating logic across scripts.
 */

const MiaoYanCommon = {
  /**
   * Check whether dark mode is enabled.
   */
  isDarkMode() {
    return 'CUSTOM_CSS' === 'darkmode';
  },

  /**
   * Wire up text selection handling.
   */
  setupTextSelection() {
    function getSelectionAndSendMessage() {
      const txt = document.getSelection().toString();
      window.webkit?.messageHandlers.newSelectionDetected?.postMessage(txt);
    }

    document.onmouseup = getSelectionAndSendMessage;
    document.onkeyup = getSelectionAndSendMessage;
    document.oncontextmenu = getSelectionAndSendMessage;
  },

  /**
   * Apply baseline checkbox behaviour.
   */
  setupCheckboxes() {
    const inputList = document.getElementsByTagName('input');

    for (let i = 0; i < inputList.length; i++) {
      inputList[i].disabled = true;

      if (
        inputList[i].parentNode.tagName === 'P' &&
        inputList[i].parentNode.parentNode.tagName === 'LI'
      ) {
        inputList[i].parentNode.parentNode.parentNode.classList.add('cb');
        continue;
      }

      if (inputList[i].parentNode.tagName !== 'LI') {
        continue;
      }

      inputList[i].parentNode.parentNode.classList.add('cb');
    }
  },

  /**
   * Enhance checkboxes with click interactions.
   */
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

  /**
   * Handle checkbox click events.
   */
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

  /**
   * Optimise image loading attributes.
   */
  optimizeImages() {
    const allImages = document.querySelectorAll('img');
    allImages.forEach((img, index) => {
      img.setAttribute('loading', index < 3 ? 'eager' : 'lazy');
      img.style.maxWidth = '100%';
      img.style.height = 'auto';
    });
  },

  /**
   * Enable image zoom-on-click support.
   */
  setupImageZoom() {
    const zoomImgs = document.querySelectorAll('#write>img, #write>p>img, #write>table img');
    if (zoomImgs.length > 0 && window.Lightense) {
      window.Lightense(zoomImgs, {
        background: this.isDarkMode() ? 'rgba(33, 38, 43, .8)' : 'rgba(255, 255, 255, .8)',
      });
    }
  },

  /**
   * Attach anchors to headings for in-page navigation.
   */
  setupHeaderAnchors() {
    document.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach((h) => (h.id = h.innerText));
    document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
      anchor.addEventListener('click', function (e) {
        e.preventDefault();
        document.querySelector(decodeURIComponent(this.getAttribute('href')))?.scrollIntoView({
          behavior: 'smooth',
        });
      });
    });
  },

  /**
   * Initialise core behaviours needed on load.
   */
  initializeCore() {
    // Initialise Heti for typography adjustments
    if (window.Heti) {
      const heti = new window.Heti('.heti');
      heti.autoSpacing();
    }

    // Initialise syntax highlighting
    if (window.hljs) {
      hljs.configure({ cssSelector: 'pre code' });
      hljs.highlightAll();
    }

    // Initialise emoji conversion
    if (window.EmojiConvertor) {
      const html = document.getElementById('write').innerHTML;
      const emoji = new EmojiConvertor();
      if (/:[^:\s]*(?:::[^:\s]*)*:/.test(html)) {
        document.getElementById('write').innerHTML = emoji.replace_colons(html);
      }
    }
  },

  /**
   * Execute when the DOM is ready.
   */
  onDOMReady(callback) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', callback);
    } else {
      callback();
    }
  }
};

// Export for external usage
window.MiaoYanCommon = MiaoYanCommon;

/* ============================================================================
 * THEME CONFIG MODULE
 * ============================================================================ */

/**
 * MiaoYan Theme Configuration
 * Centralises color and style settings for light and dark themes.
 */

const ThemeConfig = {
  // Base theme palettes
  colors: {
    dark: {
      background: '#21262B',
      diagramBg: '#282e33',
      primaryColor: '#2f353d',
      primaryBorderColor: '#49515a',
      primaryTextColor: '#E7E9EA',
      secondaryColor: '#252b31',
      tertiaryColor: '#30363d',
      lineColor: '#54C59F',
      codeBg: '#454545',
      textColor: '#E7E9EA',
      mainBkg: '#2c3238',
      secondBkg: '#252b31',
      tertiaryTextColor: '#E7E9EA',
      nodeBorder: '#49515a',
      clusterBkg: '#252b31',
      clusterBorder: '#49515a',
      edgeLabelBackground: '#2f353d'
    },

    light: {
      background: '#FFFFFF',
      diagramBg: '#f7f7f7',
      primaryColor: '#FFFFFF',
      primaryBorderColor: '#d0d7e2',
      primaryTextColor: '#1f2933',
      secondaryColor: '#f0f3f6',
      tertiaryColor: '#ffffff',
      lineColor: '#1C5D33',
      codeBg: '#f6f8fa',
      textColor: '#333333',
      mainBkg: '#ffffff',
      secondBkg: '#f0f3f6',
      tertiaryTextColor: '#333333',
      nodeBorder: '#d0d7e2',
      clusterBkg: '#f0f3f6',
      clusterBorder: '#d0d7e2',
      edgeLabelBackground: '#ffffff'
    }
  },

  /**
   * Resolve the theme colors for the current appearance.
   */
  getThemeColors(isDark = false) {
    const base = isDark ? this.colors.dark : this.colors.light;
    const palette = { ...base };
    palette.diagramBg = palette.diagramBg || palette.background;
    palette.codeBg = palette.codeBg || palette.diagramBg;
    palette.lineColor = palette.lineColor || (isDark ? '#54C59F' : '#1C5D33');
    palette.blockquoteBorderColor = palette.codeBg;
    return palette;
  },

  /**
   * Determine whether dark mode is active.
   */
  isDarkMode() {
    return document.documentElement.classList.contains('darkmode') || 'CUSTOM_CSS' === 'darkmode';
  },

  /**
   * Build the Mermaid configuration with theme-aware colors.
   */
  getMermaidConfig(isDark = false) {
    const themeColors = this.getThemeColors(isDark);

    const diagramBg = themeColors.diagramBg;
    const nodeBackground = themeColors.primaryColor;
    const clusterBackground = themeColors.secondaryColor;
    const borderColor = isDark ? '#E7E9EA' : '#262626';
    const textColor = themeColors.textColor;
    const lineColor = themeColors.lineColor;
    const accentColor = lineColor;

    const extendedColors = {
      ...themeColors,
      background: diagramBg,
      primaryColor: nodeBackground,
      secondaryColor: clusterBackground,
      tertiaryColor: nodeBackground,
      primaryTextColor: textColor,
      textColor,
      nodeBorder: borderColor,
      nodeBkg: nodeBackground,
      clusterBkg: clusterBackground,
      clusterBorder: borderColor,
      edgeLabelBackground: nodeBackground,
      edgeLabelTextColor: textColor,
      actorBkg: nodeBackground,
      actorBorder: borderColor,
      actorTextColor: textColor,
      signalColor: accentColor,
      signalTextColor: textColor,
      noteBkgColor: clusterBackground,
      noteBorderColor: borderColor,
      noteTextColor: textColor,
      arrowheadColor: lineColor,
      relationColor: lineColor,
      lineColor
    };

    this.applyCSSVariables(isDark, {
      diagramBg,
      textColor,
      nodeBackground,
      clusterBackground,
      borderColor,
      lineColor
    });

    return {
      startOnLoad: true,
      theme: isDark ? 'dark' : 'neutral',
      fontFamily: 'Helvetica, Arial, sans-serif',
      flowchart: {
        useMaxWidth: false,
        htmlLabels: true,
      },
      sequence: {
        useMaxWidth: false,
      },
      themeVariables: extendedColors,
      // Force dark-mode aware color overrides
      darkMode: isDark
    };
  },

  applyCSSVariables(isDark = false, overrides = {}) {
    if (typeof document === 'undefined') {
      return;
    }

    const root = document.documentElement;
    if (!root) {
      return;
    }

    const themeColors = this.getThemeColors(isDark);
    const diagramBg = overrides.diagramBg ?? themeColors.diagramBg ?? themeColors.background;
    const textColor = overrides.textColor ?? themeColors.textColor;
    const nodeBackground = overrides.nodeBackground ?? themeColors.primaryColor;
    const clusterBackground = overrides.clusterBackground ?? themeColors.secondaryColor;
    const borderColor = overrides.borderColor ?? (isDark ? '#E7E9EA' : '#262626');
    const lineColor = overrides.lineColor ?? themeColors.lineColor;
    const edgeLabelBackground = overrides.edgeLabelBg ?? nodeBackground;

    const setVar = (name, value) => {
      if (value === undefined || value === null) {
        root.style.removeProperty(name);
      } else {
        root.style.setProperty(name, value);
      }
    };

    setVar('--mermaid-diagram-bg', diagramBg);
    setVar('--mermaid-text-color', textColor);
    setVar('--mermaid-node-bg', nodeBackground);
    setVar('--mermaid-cluster-bg', clusterBackground);
    setVar('--mermaid-border-color', borderColor);
    setVar('--mermaid-line-color', lineColor);
    setVar('--mermaid-edge-label-bg', edgeLabelBackground);
  },

  /**
   * Build the PlantUML skin parameters for the active theme.
   */
  getPlantUMLSkinparams(isDark = false) {
    const colors = this.getThemeColors(isDark);
    const backgroundColor = colors.diagramBg || colors.background;

    const baseParams = [
      `skinparam backgroundColor ${backgroundColor}`,
      `skinparam defaultTextColor ${colors.textColor}`,
      `skinparam defaultFontColor ${colors.textColor}`,
      'skinparam defaultFontName "Helvetica"',
      'skinparam defaultFontSize 12',
      `skinparam actorBackgroundColor ${colors.primaryColor}`,
      `skinparam actorFontColor ${colors.textColor}`,
      `skinparam participantBackgroundColor ${colors.primaryColor}`,
      `skinparam participantFontColor ${colors.textColor}`,
      `skinparam classBackgroundColor ${colors.primaryColor}`,
      `skinparam classFontColor ${colors.textColor}`,
      `skinparam classAttributeFontColor ${colors.textColor}`,
      `skinparam sequenceActorBackgroundColor ${colors.primaryColor}`,
      `skinparam sequenceActorFontColor ${colors.textColor}`,
      `skinparam sequenceGroupBackgroundColor ${colors.primaryColor}`,
      `skinparam sequenceGroupHeaderFontColor ${colors.textColor}`,
      'skinparam sequenceMessageTextAlignment center'
    ].join('\n');

    const arrowParams = `
skinparam arrowColor ${colors.lineColor}
skinparam sequenceArrowColor ${colors.lineColor}
skinparam usecaseArrowColor ${colors.lineColor}
skinparam classArrowColor ${colors.lineColor}
skinparam componentArrowColor ${colors.lineColor}
skinparam stateArrowColor ${colors.lineColor}
skinparam activityArrowColor ${colors.lineColor}`;

    const componentParams = `
skinparam note {
  BackgroundColor ${colors.primaryColor}
  FontColor ${colors.textColor}
}
skinparam activity {
  BackgroundColor ${colors.primaryColor}
  FontColor ${colors.textColor}
  ArrowColor ${colors.lineColor}
}
skinparam state {
  BackgroundColor ${colors.primaryColor}
  FontColor ${colors.textColor}
  ArrowColor ${colors.lineColor}
}`;

    const additionalParams = `
skinparam usecase {
  BackgroundColor ${colors.primaryColor}
  FontColor ${colors.textColor}
  ArrowColor ${colors.lineColor}
}
skinparam component {
  BackgroundColor ${colors.primaryColor}
  FontColor ${colors.textColor}
  ArrowColor ${colors.lineColor}
}`;

    return baseParams + arrowParams + componentParams + additionalParams;
  },

  /**
   * Provide Markmap colors adjusted for the active theme.
   */
  getMarkmapColors(isDark = false) {
    const palette = this.getThemeColors(isDark);
    const accentColors = isDark
      ? [palette.lineColor, '#E7E9EA', '#F7CC8F', '#8FFCCD', '#ED716C', '#C084FC', '#60A5FA']
      : [palette.lineColor, '#1f2933', '#059669', '#F97316', '#EF4444', '#7C3AED', '#0EA5E9'];

    return {
      colorFreezeLevel: 6,
      color: accentColors,
      backgroundColor: palette.diagramBg,
      nodeBackgroundColor: palette.primaryColor,
      nodeBorderColor: 'transparent',
      linkColor: palette.lineColor
    };
  },

  /**
   * Apply themed styles to rendered diagram containers.
   */
  applyDiagramStyles(isDark = false) {
    const themeColors = this.getThemeColors(isDark);
    this.applyCSSVariables(isDark);
    const backgroundColor = themeColors.diagramBg || themeColors.background;
    const textColor = themeColors.textColor;
    const lineColor = themeColors.lineColor;
    const nodeBackground = themeColors.primaryColor;
    const clusterBackground = themeColors.secondaryColor;
    const blockquoteColor = themeColors.blockquoteBorderColor;
    const borderColor = isDark ? '#E7E9EA' : '#262626';

    const updateStyles = () => {
      document.querySelectorAll('.mermaid-image-container, .markmap-image-container, .plantuml-image-container, .plantuml-container').forEach(container => {
        container.style.backgroundColor = backgroundColor;
      });

      document.querySelectorAll('.mermaid, .mermaid svg').forEach(element => {
        element.style.backgroundColor = backgroundColor;
      });

      document.querySelectorAll('.mermaid .node rect, .mermaid .node circle, .mermaid .node polygon').forEach(element => {
        element.setAttribute('fill', nodeBackground);
        element.setAttribute('stroke', borderColor);
      });

      document.querySelectorAll('.mermaid .cluster rect').forEach(element => {
        element.setAttribute('fill', clusterBackground);
        element.setAttribute('stroke', borderColor);
      });

      document.querySelectorAll('.mermaid svg text').forEach(element => {
        element.style.fill = textColor;
        element.style.color = textColor;
      });

      document.querySelectorAll('.mermaid svg path, .mermaid svg line, .mermaid svg polyline').forEach(element => {
        if (element.getAttribute('stroke')) {
          element.setAttribute('stroke', lineColor);
        }
      });

      document.querySelectorAll('.mermaid svg .arrowheadPath').forEach(element => {
        element.setAttribute('fill', lineColor);
      });

      document.querySelectorAll('.mermaid .edgeLabel').forEach(element => {
        element.style.backgroundColor = nodeBackground;
        element.style.color = textColor;
        element.style.borderRadius = '4px';
        element.style.padding = '2px 6px';
      });

      document.querySelectorAll('.mermaid .edgeLabel rect').forEach(element => {
        element.setAttribute('fill', nodeBackground);
        element.setAttribute('stroke', borderColor);
      });

      document.querySelectorAll('.markmap').forEach(element => {
        element.style.backgroundColor = backgroundColor;
        element.style.color = textColor;
        const svgElement = element.querySelector('svg');
        if (svgElement) {
          svgElement.style.backgroundColor = backgroundColor;
        }
      });

      document.querySelectorAll('.plantuml-container').forEach(container => {
        container.style.backgroundColor = backgroundColor;
        container.style.color = textColor;
      });

      document.querySelectorAll('.plantuml-image').forEach(element => {
        element.style.backgroundColor = backgroundColor;
      });

      document.querySelectorAll('.heti blockquote').forEach(element => {
        element.style.borderLeftColor = blockquoteColor;
      });
    };

    requestAnimationFrame(updateStyles);
    setTimeout(updateStyles, 120);
  },

  /**
   * Apply runtime dark-mode styles.
   */
  applyDarkModeStyles() {
    // Ensure the root elements receive the dark-mode class
    document.documentElement.classList.add('darkmode');
    document.body.classList.add('darkmode');

    const markdownRoot = document.querySelector('.markdown-body');
    if (markdownRoot) {
      markdownRoot.classList.add('darkmode');
    }

    // Provide additional compatibility styles for dark mode
    const darkTheme = this.getThemeColors(true);
    const darkBackground = darkTheme.background;
    const diagramBackground = darkTheme.diagramBg || darkTheme.background;
    const darkText = darkTheme.textColor;
    const linkColor = this.colors.dark?.lineColor || '#1D9BF0';
    const codeBackground = darkTheme.codeBg || diagramBackground;

    const darkModeStyles = `
html.darkmode, body.darkmode {
  background: ${darkBackground} !important;
  color: ${darkText} !important;
}
.darkmode * {
  color: ${darkText};
}
.darkmode .heti p > code,
.darkmode .heti li > code,
.darkmode code {
  background: ${codeBackground} !important;
}
.darkmode a,
.darkmode .heti a heti-spacing {
  color: ${linkColor} !important;
}
.darkmode table td,
.darkmode table th {
  color: ${darkText} !important;
}
.darkmode input[type='checkbox'] {
  border: 1px solid ${darkText} !important;
}
.darkmode .mermaid-image-container,
.darkmode .markmap-image-container,
.darkmode .plantuml-image-container,
.darkmode .plantuml-container {
  background-color: ${diagramBackground} !important;
}
.darkmode .plantuml-image {
  background-color: ${diagramBackground} !important;
}
.darkmode .heti blockquote {
  border-left-color: ${darkTheme.blockquoteBorderColor} !important;
}
.darkmode .mermaid,
.darkmode .mermaid svg,
.darkmode .markmap,
.darkmode .markmap svg {
  background-color: ${diagramBackground} !important;
}`;

    const node = document.createElement('style');
    node.id = 'darkModeStyles';
    node.innerHTML = darkModeStyles;
    document.getElementsByTagName('head')[0].appendChild(node);

    this.applyDiagramStyles(true);
  }
};

// Export for use by other scripts
window.ThemeConfig = ThemeConfig;

/* ============================================================================
 * DIAGRAM HANDLER MODULE
 * ============================================================================ */

/**
 * MiaoYan Diagram Handler
 * Provides unified rendering helpers for Mermaid, PlantUML, and Markmap diagrams.
 */

const DiagramHandler = {
  /**
   * Initialise every supported diagram type.
   */
  initializeAll() {
    const isDark = this.isDarkMode();

    window.ThemeConfig?.applyCSSVariables?.(isDark);

    this.initializeMermaid();
    this.initializePlantUML();
    this.initializeMarkmap();
    this.updateContainerStyles();

    window.ThemeConfig?.applyDiagramStyles?.(isDark);
  },

  /**
   * Initialise Mermaid diagrams.
   */
  initializeMermaid() {
    if (!window.mermaid) return;

    const isDark = this.isDarkMode();
    const config = window.ThemeConfig?.getMermaidConfig(isDark) || {};

    mermaid.initialize(config);
    window.mermaid.init(undefined, document.querySelectorAll('.language-mermaid'));
    window.ThemeConfig?.applyDiagramStyles?.(isDark);
  },

  /**
   * Initialise PlantUML diagrams.
   */
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

  /**
   * Process a single PlantUML code block.
   */
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

  /**
   * Style the rendered PlantUML image element.
   */
  stylePlantumlImage(image, code, isDark) {
    const themeColors = window.ThemeConfig?.getThemeColors?.(isDark);
    const bgColor = themeColors?.diagramBg || themeColors?.background || (isDark ? '#282e33' : '#f7f7f7');

    code.style.display = 'none';
    image.style.display = 'block';
    image.style.backgroundColor = bgColor;
    image.style.maxWidth = '100%';
    image.style.width = 'auto';
    image.style.height = 'auto';
    image.style.margin = '0 auto';
    image.style.borderRadius = '6px';

    if (image.parentNode) {
      image.parentNode.style.backgroundColor = bgColor;
      image.parentNode.style.padding = '12px';
      image.parentNode.style.borderRadius = '6px';
      image.parentNode.style.boxShadow = 'none';
      image.parentNode.style.textAlign = 'center';
      image.parentNode.style.color = themeColors?.textColor || '';
      image.parentNode.classList.add('plantuml-container');
    }

    window.ThemeConfig?.applyDiagramStyles?.(isDark);
  },

  /**
   * Initialise Markmap diagrams.
   */
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

  /**
   * Prepare a Markmap code block for rendering.
   */
  processMarkmapElement(element) {
    element.classList.add('markmap');

    const isDark = this.isDarkMode();
    const colorOptions = window.ThemeConfig?.getMarkmapColors(isDark) || {};
    const themeColors = window.ThemeConfig?.getThemeColors?.(isDark);
    const bgColor = themeColors?.diagramBg || themeColors?.background || (isDark ? '#282e33' : '#f7f7f7');

    element.style.backgroundColor = bgColor;
    element.style.borderRadius = '6px';
    element.style.padding = '8px';
    element.style.overflow = 'visible';
    element.style.minHeight = '450px';
    element.style.height = '450px';
    element.style.maxHeight = 'none';
    element.style.pointerEvents = 'none';
    element.style.textAlign = 'center';
    element.style.display = 'block';
    element.style.lineHeight = '1';
    element.style.color = themeColors?.textColor || '';
    element.style.boxSizing = 'border-box';

    element.dataset.markmapColors = JSON.stringify(colorOptions);
  },

  /**
   * Render Markmap diagrams using the auto loader.
   */
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
              }
            }, 150);

            window.ThemeConfig?.applyDiagramStyles?.(this.isDarkMode());
          } catch (error) {
            console.error('Failed to render markmap block', error);
          }
        });
      });
    });
  },

  /**
   * Update container classes after diagrams render.
   */
  updateContainerStyles() {
    const preList = document.getElementsByTagName('pre');

    for (let i = 0; i < preList.length; i++) {
      if (preList[i].querySelector('.plantuml-image')) {
        preList[i].classList.add('plantuml-image-container');
      }
      if (preList[i].querySelector('.language-mermaid')) {
        preList[i].classList.add('mermaid-image-container');
      }
      if (preList[i].querySelector('.language-markmap')) {
        preList[i].classList.add('markmap-image-container');
      }
    }
  },

  /**
   * Prepare Markmap diagrams for PPT mode.
   */
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

  /**
   * Configure a single Markmap block inside PPT mode.
   */
  processMarkmapForPPT(item, index) {
    const markMapName = 'markmap-' + index;
    const markMapChildClass = '.' + markMapName + ' .markmap';

    let heightAttr = item.textContent.match(/\<\!\-\-markmap-height\=(\S*)\-\-\>/);

    // Estimate an automatic height based on content depth
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

    const isDark = this.isDarkMode();
    const themeColors = window.ThemeConfig?.getThemeColors?.(isDark);
    const backgroundColor = themeColors?.diagramBg || themeColors?.background || (isDark ? '#282e33' : '#f7f7f7');

    console.log('🔧 [Markmap Debug] PPT Mode - Processing markmap', markMapName, 'with estimated height:', height, 'autoHeight:', autoHeight, 'content lines:', lines.length, 'maxDepth:', maxDepth);
    setTimeout(() => {
      const markMapItem = document.querySelector('.' + markMapName);
      if (markMapItem) {
        console.log('🔧 [Markmap Debug] PPT Mode - Setting markMapItem styles for', markMapName);
        markMapItem.style.maxHeight = height;
        markMapItem.style.height = height;
        markMapItem.style.backgroundColor = backgroundColor;
        markMapItem.style.borderRadius = '12px';
        markMapItem.style.overflow = 'hidden';
        markMapItem.style.padding = '8px';
        markMapItem.style.boxSizing = 'border-box';
        console.log('🔧 [Markmap Debug] PPT Mode - markMapItem final height:', markMapItem.style.height);

        setTimeout(() => {
          const markMapItemChild = document.querySelector(markMapChildClass);
          if (markMapItemChild) {
            console.log('🔧 [Markmap Debug] PPT Mode - Setting markMapItemChild styles');
            markMapItemChild.style.height = height;
            markMapItemChild.style.backgroundColor = backgroundColor;
            console.log('🔧 [Markmap Debug] PPT Mode - markMapItemChild final height:', markMapItemChild.style.height);

            if (window.markmap && markMapItemChild.markmap) {
              console.log('🔧 [Markmap Debug] PPT Mode - Calling markMapItemChild.markmap.fit()');
              markMapItemChild.markmap.fit();
            } else {
              console.log('🔧 [Markmap Debug] PPT Mode - markMapItemChild.markmap not available:', markMapItemChild.markmap);
            }
          } else {
            console.log('🔧 [Markmap Debug] PPT Mode - markMapItemChild not found for selector:', markMapChildClass);
          }
        }, 50);
      } else {
        console.log('🔧 [Markmap Debug] PPT Mode - markMapItem not found for selector:', '.' + markMapName);
      }
    }, 10);
  },

  /**
   * Determine whether dark mode should be applied.
   */
  isDarkMode() {
    if (typeof window.ThemeConfig?.isDarkMode === 'function') {
      return window.ThemeConfig.isDarkMode();
    }
    return 'CUSTOM_CSS' === 'darkmode';
  }
};

// Export for external usage
window.DiagramHandler = DiagramHandler;

/* ============================================================================
 * PREVIEW APP MODULE
 * ============================================================================ */

/**
 * MiaoYan Preview App - Simplified version using common modules
 */

class MiaoYanApp {
  constructor() {
    this.initialize();
  }

  initialize() {
    // Use common module for interactive checkboxes
    if (window.MiaoYanCommon) {
      MiaoYanCommon.setupInteractiveCheckboxes();
    }
  }
}

// Initialize app when DOM is ready
MiaoYanCommon.onDOMReady(() => {
  new MiaoYanApp();
});

// Export for external use
window.MiaoYanApp = MiaoYanApp;