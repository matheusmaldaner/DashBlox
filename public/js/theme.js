// dark/light theme management with localstorage persistence

(function () {
  const THEME_KEY = 'roblox-dashboard-theme';

  // load saved theme or default to dark
  function getStoredTheme() {
    return localStorage.getItem(THEME_KEY) || 'dark';
  }

  function setTheme(theme) {
    if (theme === 'light') {
      document.documentElement.setAttribute('data-theme', 'light');
    } else {
      document.documentElement.removeAttribute('data-theme');
    }
    localStorage.setItem(THEME_KEY, theme);
  }

  // apply theme immediately (before dom ready to prevent flash)
  setTheme(getStoredTheme());

  // toggle handler
  document.addEventListener('DOMContentLoaded', () => {
    const toggle = document.getElementById('themeToggle');
    if (!toggle) return;

    toggle.addEventListener('click', () => {
      const current = getStoredTheme();
      const next = current === 'dark' ? 'light' : 'dark';
      setTheme(next);
    });
  });
})();
