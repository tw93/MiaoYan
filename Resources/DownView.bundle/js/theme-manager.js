/**
 * Theme Manager
 */

const ThemeConfig = {
  // Use theme-config.js as single source of truth
  getThemeColors(isDark = false) {
    return window.ThemeColors.getThemeColors(isDark);
  },

  get colors() {
    return window.ThemeColors.THEME_COLORS;
  },

  isDarkMode() {
    return document.documentElement.classList.contains('darkmode') || 'CUSTOM_CSS' === 'darkmode';
  },

  getMermaidConfig(isDark = false) {
    const config = window.ThemeColors.getMermaidConfig(isDark);

    // Apply CSS variables for backward compatibility
    const themeColors = this.getThemeColors(isDark);
    this.applyCSSVariables(isDark, {
      diagramBg: themeColors.diagramBg,
      textColor: themeColors.textColor,
      nodeBackground: themeColors.primaryColor,
      clusterBackground: themeColors.secondaryColor,
      borderColor: isDark ? '#E7E9EA' : '#262626',
      lineColor: themeColors.lineColor
    });

    return config;
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

  getPlantUMLSkinparams(isDark = false) {
    return window.ThemeColors.getPlantUMLSkinparams(isDark);
  },

  getMarkmapColors(isDark = false) {
    return window.ThemeColors.getMarkmapColors(isDark);
  },

  applyDarkModeStyles() {
    // Ensure the root elements receive the dark-mode class
    document.documentElement.classList.add('darkmode');
    document.body.classList.add('darkmode');

    const markdownRoot = document.querySelector('.markdown-body');
    if (markdownRoot) {
      markdownRoot.classList.add('darkmode');
    }

    // Apply CSS variables
    const isDark = true;
    this.applyCSSVariables(isDark);
  }
};

window.ThemeConfig = ThemeConfig;
