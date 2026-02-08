// reusable dialog system - replaces native prompt() and confirm()
// exposes window.dialog.prompt() and window.dialog.confirm()

(function () {
  'use strict';

  const overlay = document.getElementById('dialogModal');
  const panel = overlay.querySelector('.dialog-panel');
  const titleEl = document.getElementById('dialogTitle');
  const messageEl = document.getElementById('dialogMessage');
  const inputGroup = document.getElementById('dialogInputGroup');
  const inputEl = document.getElementById('dialogInput');
  const okBtn = document.getElementById('dialogOkBtn');
  const cancelBtn = document.getElementById('dialogCancelBtn');
  const closeBtn = document.getElementById('dialogCloseBtn');

  let resolveCallback = null;

  function open() {
    overlay.classList.add('active');
    // focus input if visible, otherwise focus ok button
    requestAnimationFrame(() => {
      if (inputGroup.style.display !== 'none') {
        inputEl.focus();
        inputEl.select();
      } else {
        okBtn.focus();
      }
    });
  }

  function close(value) {
    overlay.classList.remove('active');
    inputEl.value = '';
    if (resolveCallback) {
      resolveCallback(value);
      resolveCallback = null;
    }
  }

  // prompt: shows input field, resolves with string or null
  function showPrompt(title, opts) {
    opts = opts || {};
    titleEl.textContent = title || 'input';
    messageEl.textContent = opts.message || '';
    messageEl.style.display = opts.message ? '' : 'none';
    inputGroup.style.display = '';
    inputEl.value = opts.defaultValue || '';
    inputEl.placeholder = opts.placeholder || '';
    okBtn.textContent = opts.okText || 'ok';
    cancelBtn.textContent = opts.cancelText || 'cancel';
    okBtn.className = 'btn btn-primary';

    return new Promise((resolve) => {
      resolveCallback = resolve;
      open();
    });
  }

  // confirm: hides input, resolves with true/false
  function showConfirm(title, opts) {
    opts = opts || {};
    titleEl.textContent = title || 'confirm';
    messageEl.textContent = opts.message || '';
    messageEl.style.display = opts.message ? '' : 'none';
    inputGroup.style.display = 'none';
    okBtn.textContent = opts.okText || 'ok';
    cancelBtn.textContent = opts.cancelText || 'cancel';

    // destructive actions get a danger-styled ok button
    if (opts.danger) {
      okBtn.className = 'btn btn-danger';
    } else {
      okBtn.className = 'btn btn-primary';
    }

    return new Promise((resolve) => {
      resolveCallback = resolve;
      open();
    });
  }

  // ok handler
  okBtn.addEventListener('click', () => {
    if (inputGroup.style.display !== 'none') {
      const val = inputEl.value.trim();
      close(val || null);
    } else {
      close(true);
    }
  });

  // cancel / close handlers
  cancelBtn.addEventListener('click', () => {
    close(inputGroup.style.display !== 'none' ? null : false);
  });

  closeBtn.addEventListener('click', () => {
    close(inputGroup.style.display !== 'none' ? null : false);
  });

  // click outside to cancel
  overlay.addEventListener('click', (e) => {
    if (e.target === overlay) {
      close(inputGroup.style.display !== 'none' ? null : false);
    }
  });

  // enter to confirm, escape to cancel
  overlay.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      okBtn.click();
    } else if (e.key === 'Escape') {
      e.preventDefault();
      cancelBtn.click();
    }
  });

  // expose globally
  window.dialog = {
    prompt: showPrompt,
    confirm: showConfirm,
  };
})();
