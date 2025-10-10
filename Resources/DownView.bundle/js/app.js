/**
 * MiaoYan App Main Entry
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

MiaoYanCommon.onDOMReady(() => {
  new MiaoYanApp();
});

window.MiaoYanApp = MiaoYanApp;
