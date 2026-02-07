// tab switching and initialization

(function () {
  document.addEventListener('DOMContentLoaded', () => {
    initTabs();
  });

  function initTabs() {
    const tabButtons = document.querySelectorAll('.tab-btn');
    const tabContents = document.querySelectorAll('.tab-content');

    tabButtons.forEach((btn) => {
      btn.addEventListener('click', () => {
        const targetTab = btn.dataset.tab;

        // deactivate all
        tabButtons.forEach((b) => b.classList.remove('active'));
        tabContents.forEach((c) => c.classList.remove('active'));

        // activate selected
        btn.classList.add('active');
        const target = document.getElementById(`tab-${targetTab}`);
        if (target) {
          target.classList.add('active');
        }
      });
    });
  }
})();
