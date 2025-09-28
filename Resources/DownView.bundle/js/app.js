/**
 * MiaoYan Preview App - Additional functionality
 */

class MiaoYanApp {
  constructor() {
    this.isDarkMode = this.detectDarkMode();
    this.initCheckboxes();
  }

  detectDarkMode() {
    return 'CUSTOM_CSS' === 'darkmode';
  }

  initCheckboxes() {
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

    // Enable checkboxes with event handlers
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
  }

  handleCheckboxClick(element) {
    if (element.parentNode.nodeName === 'LI') {
      element.parentNode.classList.remove('strike');
    }

    const id = element.dataset.checkbox;
    if (window.webkit && window.webkit.messageHandlers.checkbox) {
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
    input.addEventListener('click', (event) => {
      this.handleCheckboxClick(input);
    });
  }
}

// Initialize app when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => {
    new MiaoYanApp();
  });
} else {
  new MiaoYanApp();
}

// Export for external use
window.MiaoYanApp = MiaoYanApp;