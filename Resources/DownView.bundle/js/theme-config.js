/**
 * Theme Configuration - Single Source of Truth
 *
 * All color definitions for light and dark themes.
 */

const THEME_COLORS = {
  light: {
    // Base Colors
    background: '#FFFFFF',
    textColor: '#262626',
    textSecondary: '#777',
    linkColor: '#0C6ADA',
    borderColor: '#e6e6e6',

    // Code & Diagrams
    codeBg: '#f6f8fa',
    diagramBg: '#f7f7f7',
    blockquoteBorderColor: '#d0d0d0',

    // Mermaid Specific
    primaryColor: '#FFFFFF',
    primaryBorderColor: '#d0d7e2',
    primaryTextColor: '#1f2933',
    secondaryColor: '#f0f3f6',
    tertiaryColor: '#ffffff',
    lineColor: '#1C5D33',

    // Diagram Elements
    mainBkg: '#ffffff',
    secondBkg: '#f0f3f6',
    tertiaryTextColor: '#333333',
    nodeBorder: '#d0d7e2',
    clusterBkg: '#f0f3f6',
    clusterBorder: '#d0d7e2',
    edgeLabelBackground: '#ffffff'
  },

  dark: {
    // Base Colors
    background: '#23282D',
    textColor: '#E7E9EA',
    textSecondary: '#ABB2BF',
    linkColor: '#1D9BF0',
    borderColor: '#454545',

    // Code & Diagrams
    codeBg: '#282e33',
    diagramBg: '#282e33',
    blockquoteBorderColor: '#545454',

    // Mermaid Specific
    primaryColor: '#2f353d',
    primaryBorderColor: '#49515a',
    primaryTextColor: '#E7E9EA',
    secondaryColor: '#252b31',
    tertiaryColor: '#30363d',
    lineColor: '#54C59F',

    // Diagram Elements
    mainBkg: '#2c3238',
    secondBkg: '#252b31',
    tertiaryTextColor: '#E7E9EA',
    nodeBorder: '#49515a',
    clusterBkg: '#252b31',
    clusterBorder: '#49515a',
    edgeLabelBackground: '#2f353d'
  }
};

/**
 * Get theme colors based on dark mode flag
 * @param {boolean} isDark - Whether dark mode is enabled
 * @returns {object} Color palette for the theme
 */
function getThemeColors(isDark = false) {
  const base = isDark ? THEME_COLORS.dark : THEME_COLORS.light;
  const palette = { ...base };

  // Ensure fallbacks
  palette.diagramBg = palette.diagramBg || palette.background;
  palette.codeBg = palette.codeBg || palette.diagramBg;
  palette.lineColor = palette.lineColor || (isDark ? '#54C59F' : '#1C5D33');
  palette.blockquoteBorderColor = palette.blockquoteBorderColor || (isDark ? '#545454' : '#d0d0d0');

  return palette;
}

/**
 * Get Mermaid diagram configuration
 * @param {boolean} isDark - Whether dark mode is enabled
 * @returns {object} Mermaid configuration object
 */
function getMermaidConfig(isDark = false) {
  const themeColors = getThemeColors(isDark);

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
    edgeLabelBackground: 'transparent',
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
  return {
    startOnLoad: true,
    theme: isDark ? 'dark' : 'neutral',
    themeVariables: extendedColors,
    darkMode: isDark,
    fontSize: 15,
    fontFamily: "'TsangerJinKai02-W04', -apple-system, BlinkMacSystemFont, 'Helvetica Neue', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei UI', 'Microsoft YaHei', Arial, sans-serif",
    flowchart: {
      useMaxWidth: true,
      htmlLabels: true,
      curve: 'basis',
      nodeSpacing: 80,
      rankSpacing: 80,
      padding: 30,
    },
    elk: {
      mergeEdges: true,
      padding: 40,
      nodeSpacing: 80,
      rankSpacing: 80,
    },
    sequence: {
      useMaxWidth: true,
    },
    gantt: {
      useMaxWidth: true,
    },
    journey: {
      useMaxWidth: true,
    },
    themeVariables: extendedColors,
    darkMode: isDark
  };
}

/**
 * Get PlantUML skinparams configuration
 * @param {boolean} isDark - Whether dark mode is enabled
 * @returns {string} PlantUML skinparams string
 */
function getPlantUMLSkinparams(isDark = false) {
  const colors = getThemeColors(isDark);
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
}

/**
 * Get Markmap color configuration
 * @param {boolean} isDark - Whether dark mode is enabled
 * @returns {object} Markmap color options
 */
function getMarkmapColors(isDark = false) {
  const palette = getThemeColors(isDark);
  const accentColors = isDark
    ? [palette.lineColor, '#E7E9EA', '#F7CC8F', '#8FFCCD', '#ED716C', '#C084FC', '#60A5FA']
    : [palette.lineColor, '#1f2933', '#059669', '#F97316', '#EF4444', '#7C3AED', '#0EA5E9'];

  return {
    colorFreezeLevel: 6,
    color: accentColors,
    backgroundColor: palette.diagramBg,
    nodeBackgroundColor: 'transparent',
    nodeBorderColor: 'transparent',
    linkColor: palette.lineColor
  };
}

// Export for use in other modules
window.ThemeColors = {
  THEME_COLORS,
  getThemeColors,
  getMermaidConfig,
  getPlantUMLSkinparams,
  getMarkmapColors
};
