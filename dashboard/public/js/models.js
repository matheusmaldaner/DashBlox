// models tab - 3d generation with provider toggle, image upload, roblox upload

(function () {
  // state
  let selectedProvider = 'meshy';
  let currentMode = 'text'; // 'text' or 'image'
  let currentTask = null; // { taskId, provider, assetId, subscriptionKey }
  let pollInterval = null;
  let selectedImageFile = null;
  let lastModelUrl = null;

  document.addEventListener('DOMContentLoaded', () => {
    initModelsTab();
    loadModelHistory();
  });

  function initModelsTab() {
    // mode toggle (text/image)
    const modeBtns = document.querySelectorAll('.model-mode-toggle button');
    modeBtns.forEach((btn) => {
      btn.addEventListener('click', () => {
        modeBtns.forEach((b) => b.classList.remove('active'));
        btn.classList.add('active');
        currentMode = btn.dataset.mode;
        toggleMode(currentMode);
      });
    });

    // provider dropdown
    const providerSelect = document.getElementById('modelProviderSelect');
    if (providerSelect) {
      providerSelect.addEventListener('change', () => {
        selectedProvider = providerSelect.value;
        updateQualityVisibility();
      });
    }

    // enhance button
    const enhanceBtn = document.getElementById('modelEnhanceBtn');
    if (enhanceBtn) enhanceBtn.addEventListener('click', handleEnhance);

    // generate button
    const generateBtn = document.getElementById('modelGenerateBtn');
    if (generateBtn) generateBtn.addEventListener('click', handleGenerate);

    // download buttons
    document.querySelectorAll('.model-download-row button[data-format]').forEach((btn) => {
      btn.addEventListener('click', () => handleDownload(btn.dataset.format));
    });

    // upload to roblox button
    const robloxBtn = document.getElementById('modelUploadRoblox');
    if (robloxBtn) robloxBtn.addEventListener('click', handleUploadRoblox);

    // image upload
    initImageUpload();

    // clear image
    const clearBtn = document.getElementById('modelClearImage');
    if (clearBtn) clearBtn.addEventListener('click', clearImageUpload);
  }

  function toggleMode(mode) {
    const textInput = document.getElementById('modelTextInput');
    const imageInput = document.getElementById('modelImageInput');
    if (mode === 'text') {
      textInput.style.display = '';
      imageInput.style.display = 'none';
    } else {
      textInput.style.display = 'none';
      imageInput.style.display = '';
    }
  }

  function updateQualityVisibility() {
    const qualitySelect = document.getElementById('modelQuality');
    if (qualitySelect) {
      qualitySelect.style.display = selectedProvider === 'rodin' ? '' : 'none';
    }
  }

  // image upload handlers
  function initImageUpload() {
    const uploadArea = document.getElementById('modelUploadArea');
    const fileInput = document.getElementById('modelImageFile');
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
      if (e.dataTransfer.files.length > 0) handleImageSelect(e.dataTransfer.files[0]);
    });

    fileInput.addEventListener('change', () => {
      if (fileInput.files.length > 0) handleImageSelect(fileInput.files[0]);
    });
  }

  function handleImageSelect(file) {
    const allowed = ['image/jpeg', 'image/png', 'image/webp'];
    if (!allowed.includes(file.type)) {
      const statusEl = document.getElementById('modelStatus');
      statusEl.innerHTML = 'unsupported image type. use jpg, png, or webp';
      statusEl.className = 'model-status error';
      return;
    }

    selectedImageFile = file;
    const uploadArea = document.getElementById('modelUploadArea');
    const preview = document.getElementById('modelUploadPreview');
    const previewImg = document.getElementById('modelPreviewImg');

    const reader = new FileReader();
    reader.onload = (e) => {
      previewImg.src = e.target.result;
      uploadArea.style.display = 'none';
      preview.style.display = 'flex';
    };
    reader.readAsDataURL(file);
  }

  function clearImageUpload() {
    selectedImageFile = null;
    const uploadArea = document.getElementById('modelUploadArea');
    const preview = document.getElementById('modelUploadPreview');
    const fileInput = document.getElementById('modelImageFile');
    uploadArea.style.display = '';
    preview.style.display = 'none';
    if (fileInput) fileInput.value = '';
  }

  async function handleEnhance() {
    const promptInput = document.getElementById('modelPrompt');
    const prompt = promptInput.value.trim();
    if (!prompt) { promptInput.focus(); return; }

    const enhanceBtn = document.getElementById('modelEnhanceBtn');
    const statusEl = document.getElementById('modelStatus');
    const enhancedEl = document.getElementById('enhancedPrompt');
    const enhancedText = document.getElementById('enhancedPromptText');

    enhanceBtn.disabled = true;
    statusEl.innerHTML = '<div class="spinner"></div> enhancing prompt...';
    statusEl.className = 'model-status';

    try {
      const res = await api.postJSON('/api/models/enhance-prompt', {
        prompt,
        provider: selectedProvider,
      });
      enhancedText.textContent = res.data.enhanced;
      enhancedEl.classList.add('visible');
      statusEl.innerHTML = 'prompt enhanced';
    } catch (err) {
      statusEl.innerHTML = `enhance failed: ${err.message}`;
      statusEl.className = 'model-status error';
    }
    enhanceBtn.disabled = false;
  }

  async function handleGenerate() {
    if (currentMode === 'image') return handleGenerateImage();

    // trellis only supports image-to-3d, auto-switch to image mode
    if (selectedProvider === 'replicate') {
      const imageBtn = document.getElementById('modelModeImage');
      if (imageBtn) {
        imageBtn.click();
        const statusEl = document.getElementById('modelStatus');
        statusEl.innerHTML = 'trellis only supports image-to-3d. switched to image mode - upload an image to continue.';
        statusEl.className = 'model-status';
      }
      return;
    }

    const promptInput = document.getElementById('modelPrompt');
    const prompt = promptInput.value.trim();
    if (!prompt) { promptInput.focus(); return; }

    const enhancedText = document.getElementById('enhancedPromptText');
    const enhancedPrompt = enhancedText.textContent.trim() || null;
    const negativePrompt = document.getElementById('modelNegativePrompt')?.value.trim() || null;

    prepareGenerationUI();

    const body = {
      prompt,
      provider: selectedProvider,
      enhanced_prompt: enhancedPrompt,
      negative_prompt: negativePrompt,
    };
    if (selectedProvider === 'rodin') {
      body.tier = document.getElementById('modelQuality')?.value || 'Regular';
    }

    try {
      const res = await api.postJSON('/api/models/generate', body);
      setCurrentTask(res.data);
      startPolling();
    } catch (err) {
      showGenerationError(err.message);
    }
  }

  async function handleGenerateImage() {
    if (!selectedImageFile) {
      const statusEl = document.getElementById('modelStatus');
      statusEl.innerHTML = 'please upload a reference image first';
      statusEl.className = 'model-status error';
      return;
    }

    prepareGenerationUI();

    const statusEl = document.getElementById('modelStatus');
    statusEl.innerHTML = `<div class="spinner"></div> uploading image to ${selectedProvider}...`;

    try {
      const formData = new FormData();
      formData.append('image', selectedImageFile);
      formData.append('provider', selectedProvider);
      if (selectedProvider === 'rodin') {
        formData.append('tier', document.getElementById('modelQuality')?.value || 'Regular');
      }

      const res = await api.postFormData('/api/models/generate-image', formData);
      setCurrentTask(res.data);
      startPolling();
    } catch (err) {
      showGenerationError(err.message);
    }
  }

  function prepareGenerationUI() {
    const generateBtn = document.getElementById('modelGenerateBtn');
    const statusEl = document.getElementById('modelStatus');
    const progressEl = document.getElementById('modelProgress');
    const progressBar = document.getElementById('modelProgressBar');
    const viewerContainer = document.getElementById('modelViewer');
    const downloadRow = document.getElementById('modelDownloadRow');

    generateBtn.disabled = true;
    stopPolling();

    progressEl.classList.add('visible');
    progressBar.style.width = '0%';
    downloadRow.classList.remove('visible');
    viewerContainer.classList.add('visible');

    statusEl.innerHTML = `<div class="spinner"></div> submitting to ${selectedProvider}...`;
    statusEl.className = 'model-status';
  }

  function setCurrentTask(data) {
    currentTask = {
      taskId: data.taskId,
      provider: selectedProvider,
      assetId: data.assetId,
      subscriptionKey: data.subscriptionKey,
    };
    const statusEl = document.getElementById('modelStatus');
    statusEl.innerHTML = `<div class="spinner"></div> generating... (task: ${currentTask.taskId.slice(0, 8)}...)`;
  }

  function showGenerationError(message) {
    const statusEl = document.getElementById('modelStatus');
    statusEl.innerHTML = `generation failed: ${message}`;
    statusEl.className = 'model-status error';
    document.getElementById('modelProgress').classList.remove('visible');
    document.getElementById('modelGenerateBtn').disabled = false;
  }

  function startPolling() {
    if (pollInterval) clearInterval(pollInterval);

    pollInterval = setInterval(async () => {
      if (!currentTask) return;
      try {
        const params = new URLSearchParams({ provider: currentTask.provider });
        if (currentTask.subscriptionKey) params.set('subscription_key', currentTask.subscriptionKey);

        const res = await api.getJSON(`/api/models/status/${currentTask.taskId}?${params}`);
        handlePollResult(res.data);
      } catch (err) {
        console.error('poll error:', err.message);
      }
    }, 5000);
  }

  function handlePollResult(data) {
    const statusEl = document.getElementById('modelStatus');
    const progressBar = document.getElementById('modelProgressBar');
    progressBar.style.width = `${data.progress}%`;

    if (data.status === 'generating') {
      statusEl.innerHTML = `<div class="spinner"></div> generating... ${data.progress}%`;
    } else if (data.status === 'ready') {
      stopPolling();
      statusEl.innerHTML = 'generation complete';
      statusEl.className = 'model-status';
      progressBar.style.width = '100%';
      document.getElementById('modelGenerateBtn').disabled = false;
      document.getElementById('modelDownloadRow').classList.add('visible');

      if (data.modelUrls?.glb) {
        lastModelUrl = data.modelUrls.glb;
        modelsViewer.loadModelPreview(data.modelUrls.glb);
      }
      loadModelHistory();
    } else if (data.status === 'error') {
      stopPolling();
      statusEl.innerHTML = 'generation failed';
      statusEl.className = 'model-status error';
      document.getElementById('modelGenerateBtn').disabled = false;
      document.getElementById('modelProgress').classList.remove('visible');
    }
  }

  function stopPolling() {
    if (pollInterval) { clearInterval(pollInterval); pollInterval = null; }
  }

  async function handleDownload(format) {
    if (!currentTask) return;
    const statusEl = document.getElementById('modelStatus');
    const requestedFormat = format || 'glb';
    const params = new URLSearchParams({ provider: currentTask.provider, format: requestedFormat });
    if (currentTask.subscriptionKey) params.set('subscription_key', currentTask.subscriptionKey);

    const url = `/api/models/download/${currentTask.taskId}?${params}`;

    // show converting status for non-glb formats on glb-only providers
    const needsConversion = requestedFormat !== 'glb' && currentTask.provider !== 'rodin';
    if (needsConversion) {
      statusEl.innerHTML = '<div class="spinner"></div> converting to ' + requestedFormat.toUpperCase() + '...';
      statusEl.className = 'model-status';
    }

    try {
      const res = await fetch(url);
      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: 'download failed' }));
        throw new Error(err.error || 'download failed');
      }
      const blob = await res.blob();
      const blobUrl = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = blobUrl;
      a.download = `model.${requestedFormat}`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(blobUrl);

      if (needsConversion) {
        statusEl.innerHTML = 'conversion complete - downloading ' + requestedFormat.toUpperCase();
        statusEl.className = 'model-status';
      }
    } catch (err) {
      statusEl.innerHTML = `download failed: ${err.message}`;
      statusEl.className = 'model-status error';
    }
  }

  async function handleUploadRoblox() {
    if (!lastModelUrl) {
      const statusEl = document.getElementById('modelStatus');
      statusEl.innerHTML = 'no model to upload - generate one first';
      statusEl.className = 'model-status error';
      return;
    }

    const statusEl = document.getElementById('modelStatus');
    const robloxBtn = document.getElementById('modelUploadRoblox');
    robloxBtn.disabled = true;
    statusEl.innerHTML = '<div class="spinner"></div> converting and uploading to roblox...';
    statusEl.className = 'model-status';

    try {
      const promptInput = document.getElementById('modelPrompt');
      const res = await api.postJSON('/api/models/upload-roblox', {
        model_url: lastModelUrl,
        name: promptInput?.value?.trim()?.slice(0, 50) || 'AI Generated Model',
      });
      statusEl.innerHTML = `uploaded to roblox (operation: ${res.data.path || 'pending'})`;
      statusEl.className = 'model-status';
    } catch (err) {
      statusEl.innerHTML = `roblox upload failed: ${err.message}`;
      statusEl.className = 'model-status error';
    }
    robloxBtn.disabled = false;
  }

  async function loadModelHistory() {
    const grid = document.getElementById('modelHistoryGrid');
    if (!grid) return;

    try {
      const res = await api.getJSON('/api/models/history');
      if (!res.success || !res.data.length) {
        grid.innerHTML = '<div class="model-history-empty">no previous generations</div>';
        return;
      }
      renderHistoryGrid(grid, res.data);
    } catch {
      grid.innerHTML = '<div class="model-history-empty">history unavailable</div>';
    }
  }

  function renderHistoryGrid(grid, items) {
    grid.innerHTML = items
      .map((item) => {
        const statusClass = item.status === 'completed' ? 'completed' : item.status === 'failed' ? 'failed' : 'processing';
        const thumbHtml = item.thumbnail_path
          ? `<img src="${escapeHtml(item.thumbnail_path)}" alt="thumbnail">`
          : `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/></svg>`;

        return `
        <div class="model-history-item clickable" data-file-path="${escapeHtml(item.file_path || '')}">
          <div class="model-history-item-thumb">${thumbHtml}</div>
          <div class="model-history-item-name">${escapeHtml(item.name || item.prompt)}</div>
          <div class="model-history-item-meta">
            <span>${item.provider || 'unknown'}</span>
            <span class="model-history-item-status ${statusClass}">${item.status || ''}</span>
            <span>${formatDate(item.created_at)}</span>
          </div>
        </div>`;
      })
      .join('');

    // click to load into viewer
    grid.querySelectorAll('.model-history-item.clickable').forEach((item) => {
      item.addEventListener('click', () => {
        const filePath = item.dataset.filePath;
        if (filePath) {
          document.getElementById('modelViewer').classList.add('visible');
          document.getElementById('modelDownloadRow').classList.add('visible');
          lastModelUrl = filePath;
          modelsViewer.loadModelPreview(filePath);
        }
      });
    });
  }

  function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }

  function formatDate(dateStr) {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    return d.toLocaleDateString() + ' ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }
})();
