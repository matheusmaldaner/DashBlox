// settings modal - api key configuration

(function () {
  let currentSettings = {};

  document.addEventListener('DOMContentLoaded', () => {
    initSettings();
  });

  function initSettings() {
    const settingsBtn = document.getElementById('settingsBtn');
    const closeBtn = document.getElementById('settingsCloseBtn');
    const cancelBtn = document.getElementById('settingsCancelBtn');
    const saveBtn = document.getElementById('settingsSaveBtn');
    const modal = document.getElementById('settingsModal');

    if (settingsBtn) settingsBtn.addEventListener('click', openSettings);
    if (closeBtn) closeBtn.addEventListener('click', closeSettings);
    if (cancelBtn) cancelBtn.addEventListener('click', closeSettings);
    if (saveBtn) saveBtn.addEventListener('click', saveSettings);

    // close on overlay click
    if (modal) {
      modal.addEventListener('click', (e) => {
        if (e.target === modal) closeSettings();
      });
    }

    // close on escape
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && modal && modal.classList.contains('active')) {
        closeSettings();
      }
    });
  }

  async function openSettings() {
    const modal = document.getElementById('settingsModal');
    const keysContainer = document.getElementById('settingsKeys');
    if (!modal || !keysContainer) return;

    modal.classList.add('active');
    keysContainer.innerHTML = '<div class="spinner"></div>';

    try {
      const res = await api.getJSON('/api/settings');
      currentSettings = res.data;
      renderSettingsForm(keysContainer, currentSettings);
    } catch (err) {
      keysContainer.innerHTML = `<p class="settings-error">failed to load settings: ${escapeHtml(err.message)}</p>`;
    }
  }

  function closeSettings() {
    const modal = document.getElementById('settingsModal');
    if (modal) modal.classList.remove('active');
  }

  function renderSettingsForm(container, settings) {
    const keys = Object.keys(settings);
    container.innerHTML = keys.map((key) => {
      const setting = settings[key];
      const statusClass = setting.configured ? 'configured' : 'not-configured';
      const statusText = setting.configured ? 'configured' : 'not set';
      return `
        <div class="settings-key-group">
          <div class="settings-key-header">
            <label for="setting-${key}">${escapeHtml(setting.label)}</label>
            <span class="settings-key-status ${statusClass}">${statusText}</span>
          </div>
          <input type="password" class="input settings-key-input" id="setting-${key}"
            data-key="${key}"
            placeholder="${setting.configured ? setting.value : 'enter api key...'}"
            autocomplete="off">
        </div>`;
    }).join('');
  }

  async function saveSettings() {
    const inputs = document.querySelectorAll('.settings-key-input');
    const updates = {};
    let hasChanges = false;

    inputs.forEach((input) => {
      const key = input.dataset.key;
      const value = input.value.trim();
      if (value) {
        updates[key] = value;
        hasChanges = true;
      }
    });

    if (!hasChanges) {
      closeSettings();
      return;
    }

    const saveBtn = document.getElementById('settingsSaveBtn');
    saveBtn.disabled = true;
    saveBtn.textContent = 'saving...';

    try {
      const res = await api.putJSON('/api/settings', updates);
      currentSettings = res.data;
      closeSettings();
      showToast('settings saved');
    } catch (err) {
      showToast(`failed to save: ${err.message}`);
    }

    saveBtn.disabled = false;
    saveBtn.textContent = 'save';
  }

  function showToast(message) {
    const container = document.getElementById('toastContainer');
    if (!container) return;
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    container.appendChild(toast);
    setTimeout(() => toast.remove(), 3000);
  }

  function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }
})();
