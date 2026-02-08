// docs tab - markdown viewer/editor with table of contents

(function () {
  const HIDDEN_DOC_FILES = ['CLAUDE.md'];
  let projects = [];
  let currentProject = 0;
  let currentFile = '';
  let rawContent = '';
  let originalContent = '';
  let mode = 'view'; // view, edit, split

  document.addEventListener('DOMContentLoaded', () => {
    initDocs();
  });

  function initDocs() {
    const projectSelect = document.getElementById('docsProjectSelect');
    const fileSelect = document.getElementById('docsFileSelect');
    const viewBtn = document.getElementById('docsModeView');
    const editBtn = document.getElementById('docsModeEdit');
    const splitBtn = document.getElementById('docsModeSplit');
    const saveBtn = document.getElementById('docsSaveBtn');

    if (!projectSelect) return;

    projectSelect.addEventListener('change', () => {
      currentProject = parseInt(projectSelect.value, 10);
      updateFileOptions();
      loadFile();
    });

    fileSelect.addEventListener('change', () => {
      currentFile = fileSelect.value;
      loadFile();
    });

    viewBtn.addEventListener('click', () => setMode('view'));
    editBtn.addEventListener('click', () => setMode('edit'));
    splitBtn.addEventListener('click', () => setMode('split'));
    saveBtn.addEventListener('click', saveFile);

    loadProjects();
  }

  async function loadProjects() {
    try {
      const res = await api.getJSON('/api/docs/projects');
      projects = (res.data || []).map((project) => ({
        ...project,
        files: (project.files || []).filter((file) => !HIDDEN_DOC_FILES.includes(file)),
      }));

      const select = document.getElementById('docsProjectSelect');
      select.innerHTML = '';

      projects.forEach((p) => {
        const opt = document.createElement('option');
        opt.value = p.index;
        opt.textContent = p.name;
        select.appendChild(opt);
      });

      if (projects.length > 0) {
        currentProject = 0;
        updateFileOptions();
        loadFile();
      }
    } catch (err) {
      console.error('failed to load projects:', err);
    }
  }

  function updateFileOptions() {
    const fileSelect = document.getElementById('docsFileSelect');
    const project = projects[currentProject];
    if (!project) return;

    fileSelect.innerHTML = '';
    project.files.forEach((f) => {
      const opt = document.createElement('option');
      opt.value = f;
      opt.textContent = f;
      fileSelect.appendChild(opt);
    });

    // default to PLAN.md if available, else first file
    const defaultFile = project.files.includes('PLAN.md') ? 'PLAN.md' : project.files[0];
    if (defaultFile) {
      fileSelect.value = defaultFile;
      currentFile = defaultFile;
      return;
    }

    currentFile = '';
  }

  async function loadFile() {
    if (!currentFile) {
      const contentArea = document.getElementById('docsContentArea');
      const tocList = document.getElementById('docsTocList');
      if (contentArea) {
        contentArea.innerHTML = `<div class="docs-empty"><p>No docs available for this project.</p></div>`;
      }
      if (tocList) {
        tocList.innerHTML = '';
      }
      return;
    }

    const contentArea = document.getElementById('docsContentArea');
    contentArea.innerHTML = '<div class="docs-loading"><div class="spinner"></div></div>';

    try {
      const res = await api.getJSON(
        `/api/docs/read?project=${currentProject}&file=${encodeURIComponent(currentFile)}`
      );
      rawContent = res.data.content;
      originalContent = rawContent;
      renderContent();
      updateSaveBtn();
    } catch (err) {
      contentArea.innerHTML = `<div class="docs-empty">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="10"/>
          <line x1="12" y1="8" x2="12" y2="12"/>
          <line x1="12" y1="16" x2="12.01" y2="16"/>
        </svg>
        <p>${escapeHtml(err.message)}</p>
      </div>`;
    }
  }

  function setMode(newMode) {
    mode = newMode;

    document.getElementById('docsModeView').classList.toggle('active', mode === 'view');
    document.getElementById('docsModeEdit').classList.toggle('active', mode === 'edit');
    document.getElementById('docsModeSplit').classList.toggle('active', mode === 'split');

    renderContent();
  }

  function renderContent() {
    const contentArea = document.getElementById('docsContentArea');
    const tocList = document.getElementById('docsTocList');

    if (mode === 'view') {
      const html = renderMarkdown(rawContent);
      contentArea.innerHTML = `<div class="docs-rendered">${html}</div>`;
      buildToc(contentArea, tocList);
      bindCheckboxes(contentArea);
    } else if (mode === 'edit') {
      contentArea.innerHTML = `<textarea class="docs-editor" id="docsEditorTextarea">${escapeHtml(rawContent)}</textarea>`;
      const textarea = document.getElementById('docsEditorTextarea');
      textarea.addEventListener('input', () => {
        rawContent = textarea.value;
        updateSaveBtn();
      });
      // handle tab key for indentation
      textarea.addEventListener('keydown', (e) => {
        if (e.key === 'Tab') {
          e.preventDefault();
          const start = textarea.selectionStart;
          const end = textarea.selectionEnd;
          textarea.value = textarea.value.substring(0, start) + '  ' + textarea.value.substring(end);
          textarea.selectionStart = textarea.selectionEnd = start + 2;
          rawContent = textarea.value;
          updateSaveBtn();
        }
      });
      tocList.innerHTML = '';
    } else if (mode === 'split') {
      const html = renderMarkdown(rawContent);
      contentArea.innerHTML = `<div class="docs-split">
        <textarea class="docs-editor" id="docsEditorTextarea">${escapeHtml(rawContent)}</textarea>
        <div class="docs-preview docs-rendered">${html}</div>
      </div>`;
      const textarea = document.getElementById('docsEditorTextarea');
      const preview = contentArea.querySelector('.docs-preview');
      textarea.addEventListener('input', () => {
        rawContent = textarea.value;
        preview.innerHTML = renderMarkdown(rawContent);
        bindCheckboxes(preview);
        updateSaveBtn();
      });
      textarea.addEventListener('keydown', (e) => {
        if (e.key === 'Tab') {
          e.preventDefault();
          const start = textarea.selectionStart;
          const end = textarea.selectionEnd;
          textarea.value = textarea.value.substring(0, start) + '  ' + textarea.value.substring(end);
          textarea.selectionStart = textarea.selectionEnd = start + 2;
          rawContent = textarea.value;
          preview.innerHTML = renderMarkdown(rawContent);
          bindCheckboxes(preview);
          updateSaveBtn();
        }
      });
      buildToc(preview, tocList);
      bindCheckboxes(preview);
    }
  }

  function renderMarkdown(text) {
    if (typeof marked === 'undefined') return escapeHtml(text);

    marked.setOptions({
      gfm: true,
      breaks: false,
      pedantic: false,
      highlight: function (code, lang) {
        if (typeof hljs !== 'undefined' && lang && hljs.getLanguage(lang)) {
          try {
            return hljs.highlight(code, { language: lang }).value;
          } catch {
            // fall through
          }
        }
        if (typeof hljs !== 'undefined') {
          try {
            return hljs.highlightAuto(code).value;
          } catch {
            // fall through
          }
        }
        return code;
      },
    });

    return marked.parse(text);
  }

  function buildToc(container, tocList) {
    if (!tocList) return;
    tocList.innerHTML = '';

    const headings = container.querySelectorAll('h1, h2, h3');
    if (headings.length === 0) return;

    headings.forEach((heading, i) => {
      const id = 'doc-heading-' + i;
      heading.id = id;

      const li = document.createElement('li');
      const a = document.createElement('a');
      a.href = '#' + id;
      a.textContent = heading.textContent;
      a.className = 'toc-' + heading.tagName.toLowerCase();
      a.addEventListener('click', (e) => {
        e.preventDefault();
        heading.scrollIntoView({ behavior: 'smooth', block: 'start' });
        // update active state
        tocList.querySelectorAll('a').forEach((link) => link.classList.remove('active'));
        a.classList.add('active');
      });
      li.appendChild(a);
      tocList.appendChild(li);
    });
  }

  function bindCheckboxes(container) {
    const checkboxes = container.querySelectorAll('.task-list-item input[type="checkbox"]');
    checkboxes.forEach((cb) => {
      cb.addEventListener('change', () => {
        toggleCheckbox(cb);
      });
    });
  }

  function toggleCheckbox(checkbox) {
    // find the checkbox's text content to locate it in raw markdown
    const listItem = checkbox.closest('li');
    if (!listItem) return;

    const text = listItem.textContent.trim();
    const isChecked = checkbox.checked;

    // toggle the matching line in raw content
    const lines = rawContent.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const stripped = line.replace(/^\s*[-*]\s*\[[ x]\]\s*/, '').trim();
      if (stripped && text.startsWith(stripped.substring(0, 30))) {
        if (isChecked) {
          lines[i] = line.replace('[ ]', '[x]');
        } else {
          lines[i] = line.replace('[x]', '[ ]');
        }
        break;
      }
    }

    rawContent = lines.join('\n');
    updateSaveBtn();
    saveFile();
  }

  async function saveFile() {
    if (rawContent === originalContent) return;

    const saveBtn = document.getElementById('docsSaveBtn');
    saveBtn.textContent = 'saving...';
    saveBtn.disabled = true;

    try {
      await api.putJSON('/api/docs/write', {
        project: currentProject,
        file: currentFile,
        content: rawContent,
      });
      originalContent = rawContent;
      updateSaveBtn();
      showToast('saved ' + currentFile);
    } catch (err) {
      showToast('save failed: ' + err.message);
    } finally {
      saveBtn.disabled = false;
    }
  }

  function updateSaveBtn() {
    const saveBtn = document.getElementById('docsSaveBtn');
    const hasChanges = rawContent !== originalContent;
    saveBtn.classList.toggle('has-changes', hasChanges);
    saveBtn.textContent = hasChanges ? 'save changes' : 'saved';
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
