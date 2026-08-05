// dark/light theme management with localstorage persistence

(function () {
  const THEME_KEY = 'roblox-dashboard-theme';

  // load saved theme or default to dark
  function getStoredTheme() {
    return localStorage.getItem(THEME_KEY) || 'light';
  }

  function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme === 'light' ? 'light' : 'dark');
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
