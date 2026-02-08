// models converter - file upload, format conversion, 3d preview, roblox upload

(function () {
  let converterFile = null;
  let viewerScene, viewerCamera, viewerRenderer, viewerControls;
  let viewerInitialized = false;

  document.addEventListener('DOMContentLoaded', () => {
    initConverter();
    renderHistory();
  });

  function initConverter() {
    const uploadArea = document.getElementById('converterUploadArea');
    const fileInput = document.getElementById('converterFileInput');
    const clearBtn = document.getElementById('converterClearFile');
    const convertBtn = document.getElementById('converterConvertBtn');
    const robloxBtn = document.getElementById('converterUploadRobloxBtn');
    const clearHistoryBtn = document.getElementById('converterClearHistory');
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
    if (robloxBtn) robloxBtn.addEventListener('click', handleUploadRoblox);
    if (clearHistoryBtn) clearHistoryBtn.addEventListener('click', clearHistory);
  }

  // -- file selection --

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

    // load 3d preview for glb/gltf files
    if (ext === '.glb' || ext === '.gltf') {
      loadPreview(file);
    } else {
      showPreviewMessage(`preview not available for ${ext.toUpperCase()} files`);
    }
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
    clearPreview();
  }

  // -- convert and download --

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

      await addHistoryEntry(converterFile.name, targetFormat, converterFile.size);
      statusEl.innerHTML = `converted and downloading ${baseName}.${targetFormat}`;
      statusEl.className = 'converter-status';
    } catch (err) {
      statusEl.innerHTML = `conversion failed: ${err.message}`;
      statusEl.className = 'converter-status error';
    }
    convertBtn.disabled = false;
  }

  // -- convert and upload to roblox --

  async function handleUploadRoblox() {
    if (!converterFile) return;

    const statusEl = document.getElementById('converterStatus');
    const robloxBtn = document.getElementById('converterUploadRobloxBtn');

    robloxBtn.disabled = true;
    statusEl.innerHTML = '<div class="spinner"></div> converting and uploading to roblox...';
    statusEl.className = 'converter-status';

    try {
      const formData = new FormData();
      formData.append('model', converterFile);
      formData.append('name', converterFile.name.substring(0, converterFile.name.lastIndexOf('.')).slice(0, 50));

      const res = await fetch('/api/models/convert-upload-roblox', { method: 'POST', body: formData });

      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: 'upload failed' }));
        throw new Error(err.error || 'upload failed');
      }

      const data = await res.json();
      await addHistoryEntry(converterFile.name, 'roblox', converterFile.size);
      statusEl.innerHTML = `uploaded to roblox (operation: ${data.data.path || 'pending'})`;
      statusEl.className = 'converter-status';
    } catch (err) {
      statusEl.innerHTML = `roblox upload failed: ${err.message}`;
      statusEl.className = 'converter-status error';
    }
    robloxBtn.disabled = false;
  }

  // -- 3d preview (glb/gltf only) --

  function initViewer() {
    if (viewerInitialized) return;
    const container = document.getElementById('converterViewerCanvas');
    if (!container || typeof window.THREE === 'undefined') return;

    const THREE = window.THREE;
    viewerScene = new THREE.Scene();
    viewerScene.background = new THREE.Color(0xffffff);

    viewerCamera = new THREE.PerspectiveCamera(50, container.clientWidth / container.clientHeight, 0.1, 1000);
    viewerCamera.position.set(3, 2, 3);

    viewerRenderer = new THREE.WebGLRenderer({ antialias: true });
    viewerRenderer.setSize(container.clientWidth, container.clientHeight);
    viewerRenderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    viewerRenderer.outputEncoding = THREE.sRGBEncoding;
    container.appendChild(viewerRenderer.domElement);

    if (THREE.OrbitControls) {
      viewerControls = new THREE.OrbitControls(viewerCamera, viewerRenderer.domElement);
      viewerControls.enableDamping = true;
      viewerControls.dampingFactor = 0.05;
    }

    viewerScene.add(new THREE.AmbientLight(0xffffff, 0.6));
    const dirLight = new THREE.DirectionalLight(0xffffff, 1.2);
    dirLight.position.set(5, 10, 7);
    viewerScene.add(dirLight);
    viewerScene.add(new THREE.GridHelper(10, 10, 0xcccccc, 0xe0e0e0));

    const resizeObserver = new ResizeObserver(() => {
      if (!container.clientWidth) return;
      viewerCamera.aspect = container.clientWidth / container.clientHeight;
      viewerCamera.updateProjectionMatrix();
      viewerRenderer.setSize(container.clientWidth, container.clientHeight);
    });
    resizeObserver.observe(container);

    function animate() {
      requestAnimationFrame(animate);
      if (viewerControls) viewerControls.update();
      viewerRenderer.render(viewerScene, viewerCamera);
    }
    animate();
    viewerInitialized = true;
  }

  function loadPreview(file) {
    if (typeof window.THREE === 'undefined' || !window.THREE.GLTFLoader) {
      showPreviewMessage('3d preview unavailable');
      return;
    }

    initViewer();

    const emptyEl = document.getElementById('converterPreviewEmpty');
    if (emptyEl) emptyEl.style.display = 'none';

    const THREE = window.THREE;
    const oldModel = viewerScene.getObjectByName('converterModel');
    if (oldModel) viewerScene.remove(oldModel);

    const url = URL.createObjectURL(file);
    const loader = new THREE.GLTFLoader();
    loader.load(url, (gltf) => {
      URL.revokeObjectURL(url);
      const model = gltf.scene;
      model.name = 'converterModel';

      const box = new THREE.Box3().setFromObject(model);
      const center = box.getCenter(new THREE.Vector3());
      const size = box.getSize(new THREE.Vector3());
      const scale = 2 / Math.max(size.x, size.y, size.z);

      model.position.sub(center);
      model.scale.setScalar(scale);
      viewerScene.add(model);

      viewerCamera.position.set(3, 2, 3);
      viewerCamera.lookAt(0, 0, 0);
      if (viewerControls) viewerControls.target.set(0, 0, 0);
    }, null, () => {
      URL.revokeObjectURL(url);
      showPreviewMessage('failed to load model preview');
    });
  }

  function showPreviewMessage(msg) {
    const emptyEl = document.getElementById('converterPreviewEmpty');
    if (emptyEl) {
      emptyEl.style.display = 'flex';
      const p = emptyEl.querySelector('p');
      if (p) p.textContent = msg;
    }
  }

  function clearPreview() {
    if (viewerScene) {
      const oldModel = viewerScene.getObjectByName('converterModel');
      if (oldModel) viewerScene.remove(oldModel);
    }
    showPreviewMessage('upload a glb/gltf file to preview');
  }

  // -- conversion history (mongodb) --

  async function addHistoryEntry(filename, targetFormat, fileSize) {
    const ext = filename.substring(filename.lastIndexOf('.') + 1).toUpperCase();
    try {
      await api.postJSON('/api/models/converter/history', {
        name: filename,
        from_format: ext,
        to_format: targetFormat.toUpperCase(),
        file_size: fileSize || 0,
      });
    } catch (err) {
      console.warn('failed to save conversion history:', err.message);
    }
    renderHistory();
  }

  async function renderHistory() {
    const list = document.getElementById('converterHistoryList');
    if (!list) return;

    try {
      const res = await api.getJSON('/api/models/converter/history');
      if (!res.success || !res.data.length) {
        list.innerHTML = '<div class="converter-history-empty">no conversions yet</div>';
        return;
      }

      list.innerHTML = res.data.map((item) => {
        const time = new Date(item.created_at);
        const timeStr = time.toLocaleDateString() + ' ' + time.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        return `
          <div class="converter-history-item">
            <span class="converter-history-item-name">${escapeHtml(item.name)}</span>
            <span class="converter-history-item-format">${item.from_format}</span>
            <span class="converter-history-item-arrow">&rarr;</span>
            <span class="converter-history-item-format">${item.to_format}</span>
            <span class="converter-history-item-time">${timeStr}</span>
          </div>`;
      }).join('');
    } catch {
      list.innerHTML = '<div class="converter-history-empty">history unavailable</div>';
    }
  }

  async function clearHistory() {
    try {
      await api.deleteJSON('/api/models/converter/history');
    } catch (err) {
      console.warn('failed to clear history:', err.message);
    }
    renderHistory();
  }

  function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }
})();
