// shows a banner when the backend api is unreachable (static preview mode)

(function () {
  document.addEventListener('DOMContentLoaded', async () => {
    let offline = false;
    try {
      const res = await fetch('/api/health', { cache: 'no-store' });
      if (!res.ok) offline = true;
      else {
        const type = res.headers.get('content-type') || '';
        if (!type.includes('application/json')) offline = true;
      }
    } catch {
      offline = true;
    }
    if (!offline) return;

    const banner = document.createElement('div');
    banner.setAttribute('role', 'status');
    banner.style.cssText = [
      'position: fixed',
      'left: 50%',
      'bottom: 24px',
      'transform: translateX(-50%)',
      'z-index: 1000',
      'display: flex',
      'align-items: center',
      'gap: 12px',
      'max-width: min(92vw, 560px)',
      'padding: 12px 18px',
      'border-radius: 14px',
      'font-size: 13px',
      'line-height: 1.5',
      'color: var(--text-primary, #e5e7eb)',
      'background: var(--glass-bg, rgba(30, 30, 40, 0.7))',
      'border: 1px solid var(--glass-border, rgba(255, 255, 255, 0.12))',
      'backdrop-filter: blur(16px)',
      '-webkit-backdrop-filter: blur(16px)',
      'box-shadow: 0 8px 32px rgba(0, 0, 0, 0.25)',
    ].join(';');

    const text = document.createElement('span');
    text.innerHTML =
      'static preview: the DashBlox backend is offline, so generation and data features are disabled. ' +
      'source on <a href="https://github.com/matheusmaldaner/DashBlox" target="_blank" rel="noopener noreferrer" style="color: var(--accent, #8b5cf6); text-decoration: underline;">GitHub</a>.';

    const close = document.createElement('button');
    close.textContent = '×';
    close.setAttribute('aria-label', 'dismiss');
    close.style.cssText =
      'background: none; border: none; color: inherit; font-size: 18px; cursor: pointer; padding: 0 2px; line-height: 1;';
    close.addEventListener('click', () => banner.remove());

    banner.appendChild(text);
    banner.appendChild(close);
    document.body.appendChild(banner);
  });
})();
