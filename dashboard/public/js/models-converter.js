// models converter - standalone file upload and format conversion

(function () {
  let converterFile = null;

  document.addEventListener('DOMContentLoaded', () => {
    initConverter();
  });

  function initConverter() {
    const uploadArea = document.getElementById('converterUploadArea');
    const fileInput = document.getElementById('converterFileInput');
    const clearBtn = document.getElementById('converterClearFile');
    const convertBtn = document.getElementById('converterConvertBtn');
    if (!uploadArea || !fileInput) return;

    uploadArea.addEventListener('dragover', (e) => {
      e.preventDefault();
      uploadArea.classList.add('dragover');
    });
    uploadArea.addEventListener('dragleave', () => {
      uploadArea.classList.remove('dragover');
    });
    uploadArea.addEventListener('drop', (e) => {
      e.preventDefault();
      uploadArea.classList.remove('dragover');
      if (e.dataTransfer.files.length > 0) handleFileSelect(e.dataTransfer.files[0]);
    });

    fileInput.addEventListener('change', () => {
      if (fileInput.files.length > 0) handleFileSelect(fileInput.files[0]);
    });

    if (clearBtn) clearBtn.addEventListener('click', clearFile);
    if (convertBtn) convertBtn.addEventListener('click', handleConvert);
  }

  function handleFileSelect(file) {
    const allowed = ['.glb', '.gltf', '.fbx', '.obj'];
    const ext = file.name.substring(file.name.lastIndexOf('.')).toLowerCase();
    const statusEl = document.getElementById('converterStatus');

    if (!allowed.includes(ext)) {
      statusEl.innerHTML = 'unsupported file type. use glb, gltf, fbx, or obj';
      statusEl.className = 'converter-status error';
      return;
    }

    converterFile = file;
    document.getElementById('converterUploadArea').style.display = 'none';
    document.getElementById('converterFileInfo').style.display = 'flex';
    document.getElementById('converterFileName').textContent = `${file.name} (${(file.size / 1024 / 1024).toFixed(1)} MB)`;
    document.getElementById('converterActions').style.display = 'flex';
    statusEl.innerHTML = '';
    statusEl.className = 'converter-status';
  }

  function clearFile() {
    converterFile = null;
    document.getElementById('converterUploadArea').style.display = '';
    document.getElementById('converterFileInfo').style.display = 'none';
    document.getElementById('converterActions').style.display = 'none';
    document.getElementById('converterFileInput').value = '';
    const statusEl = document.getElementById('converterStatus');
    statusEl.innerHTML = '';
    statusEl.className = 'converter-status';
  }

  async function handleConvert() {
    if (!converterFile) return;

    const targetFormat = document.getElementById('converterTargetFormat').value;
    const statusEl = document.getElementById('converterStatus');
    const convertBtn = document.getElementById('converterConvertBtn');

    convertBtn.disabled = true;
    statusEl.innerHTML = `<div class="spinner"></div> converting to ${targetFormat.toUpperCase()}...`;
    statusEl.className = 'converter-status';

    try {
      const formData = new FormData();
      formData.append('model', converterFile);
      formData.append('target_format', targetFormat);

      const res = await fetch('/api/models/convert', { method: 'POST', body: formData });

      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: 'conversion failed' }));
        throw new Error(err.error || 'conversion failed');
      }

      const blob = await res.blob();
      const baseName = converterFile.name.substring(0, converterFile.name.lastIndexOf('.'));
      const blobUrl = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = blobUrl;
      a.download = `${baseName}.${targetFormat}`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(blobUrl);

      statusEl.innerHTML = `converted and downloading ${baseName}.${targetFormat}`;
      statusEl.className = 'converter-status';
    } catch (err) {
      statusEl.innerHTML = `conversion failed: ${err.message}`;
      statusEl.className = 'converter-status error';
    }
    convertBtn.disabled = false;
  }
})();
