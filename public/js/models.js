// models tab - 3d generation with provider toggle and three.js viewer

(function () {
  // state
  let selectedProvider = 'meshy';
  let currentTask = null; // { taskId, provider, assetId, subscriptionKey }
  let pollInterval = null;
  let scene, camera, renderer, controls;
  let viewerInitialized = false;

  document.addEventListener('DOMContentLoaded', () => {
    initModelsTab();
    loadModelHistory();
  });

  function initModelsTab() {
    // provider toggle
    const providerBtns = document.querySelectorAll('.provider-toggle button');
    providerBtns.forEach((btn) => {
      btn.addEventListener('click', () => {
        providerBtns.forEach((b) => b.classList.remove('active'));
        btn.classList.add('active');
        selectedProvider = btn.dataset.provider;
      });
    });

    // enhance button
    const enhanceBtn = document.getElementById('modelEnhanceBtn');
    if (enhanceBtn) {
      enhanceBtn.addEventListener('click', handleEnhance);
    }

    // generate button
    const generateBtn = document.getElementById('modelGenerateBtn');
    if (generateBtn) {
      generateBtn.addEventListener('click', handleGenerate);
    }

    // download buttons
    document.querySelectorAll('.model-download-row button').forEach((btn) => {
      btn.addEventListener('click', () => handleDownload(btn.dataset.format));
    });
  }

  async function handleEnhance() {
    const promptInput = document.getElementById('modelPrompt');
    const prompt = promptInput.value.trim();
    if (!prompt) {
      promptInput.focus();
      return;
    }

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
    const promptInput = document.getElementById('modelPrompt');
    const prompt = promptInput.value.trim();
    if (!prompt) {
      promptInput.focus();
      return;
    }

    const enhancedText = document.getElementById('enhancedPromptText');
    const enhancedPrompt = enhancedText.textContent.trim() || null;
    const generateBtn = document.getElementById('modelGenerateBtn');
    const statusEl = document.getElementById('modelStatus');
    const progressEl = document.getElementById('modelProgress');
    const progressBar = document.getElementById('modelProgressBar');
    const viewerContainer = document.getElementById('modelViewer');
    const downloadRow = document.getElementById('modelDownloadRow');

    generateBtn.disabled = true;
    stopPolling();

    // reset ui
    progressEl.classList.add('visible');
    progressBar.style.width = '0%';
    downloadRow.classList.remove('visible');
    viewerContainer.classList.add('visible');

    statusEl.innerHTML = `<div class="spinner"></div> submitting to ${selectedProvider}...`;
    statusEl.className = 'model-status';

    try {
      const res = await api.postJSON('/api/models/generate', {
        prompt,
        provider: selectedProvider,
        enhanced_prompt: enhancedPrompt,
      });

      currentTask = {
        taskId: res.data.taskId,
        provider: selectedProvider,
        assetId: res.data.assetId,
        subscriptionKey: res.data.subscriptionKey,
      };

      statusEl.innerHTML = `<div class="spinner"></div> generating... (task: ${currentTask.taskId.slice(0, 8)}...)`;

      // start polling
      startPolling();
    } catch (err) {
      statusEl.innerHTML = `generation failed: ${err.message}`;
      statusEl.className = 'model-status error';
      progressEl.classList.remove('visible');
      generateBtn.disabled = false;
    }
  }

  function startPolling() {
    if (pollInterval) clearInterval(pollInterval);

    pollInterval = setInterval(async () => {
      if (!currentTask) return;

      try {
        const params = new URLSearchParams({
          provider: currentTask.provider,
        });
        if (currentTask.subscriptionKey) {
          params.set('subscription_key', currentTask.subscriptionKey);
        }

        const res = await api.getJSON(`/api/models/status/${currentTask.taskId}?${params}`);
        const data = res.data;
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

          // load model into three.js viewer
          if (data.modelUrls?.glb) {
            loadModelPreview(data.modelUrls.glb);
          }

          loadModelHistory();
        } else if (data.status === 'error') {
          stopPolling();
          statusEl.innerHTML = 'generation failed';
          statusEl.className = 'model-status error';
          document.getElementById('modelGenerateBtn').disabled = false;
          document.getElementById('modelProgress').classList.remove('visible');
        }
      } catch (err) {
        console.error('poll error:', err.message);
      }
    }, 5000); // poll every 5 seconds
  }

  function stopPolling() {
    if (pollInterval) {
      clearInterval(pollInterval);
      pollInterval = null;
    }
  }

  // three.js viewer
  function initViewer() {
    if (viewerInitialized) return;

    const container = document.getElementById('modelViewerCanvas');
    if (!container || typeof window.THREE === 'undefined') return;

    const THREE = window.THREE;

    // scene
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x1a1a2e);

    // camera
    camera = new THREE.PerspectiveCamera(50, container.clientWidth / container.clientHeight, 0.1, 1000);
    camera.position.set(3, 2, 3);

    // renderer
    renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(container.clientWidth, container.clientHeight);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.shadowMap.enabled = true;
    container.appendChild(renderer.domElement);

    // orbit controls
    if (window.THREE.OrbitControls) {
      controls = new THREE.OrbitControls(camera, renderer.domElement);
      controls.enableDamping = true;
      controls.dampingFactor = 0.05;
    }

    // lighting
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.5);
    scene.add(ambientLight);

    const directionalLight = new THREE.DirectionalLight(0xffffff, 1);
    directionalLight.position.set(5, 10, 7);
    directionalLight.castShadow = true;
    scene.add(directionalLight);

    const fillLight = new THREE.DirectionalLight(0x4488ff, 0.3);
    fillLight.position.set(-5, 3, -5);
    scene.add(fillLight);

    // grid floor
    const gridHelper = new THREE.GridHelper(10, 10, 0x444444, 0x222222);
    scene.add(gridHelper);

    // resize handler
    const resizeObserver = new ResizeObserver(() => {
      camera.aspect = container.clientWidth / container.clientHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(container.clientWidth, container.clientHeight);
    });
    resizeObserver.observe(container);

    // animation loop
    function animate() {
      requestAnimationFrame(animate);
      if (controls) controls.update();
      renderer.render(scene, camera);
    }
    animate();

    viewerInitialized = true;
  }

  function loadModelPreview(url) {
    if (typeof window.THREE === 'undefined') {
      console.warn('three.js not loaded, skipping preview');
      return;
    }

    initViewer();

    const THREE = window.THREE;

    // remove old model
    const oldModel = scene.getObjectByName('loadedModel');
    if (oldModel) scene.remove(oldModel);

    // hide empty state
    const emptyState = document.getElementById('modelViewerEmpty');
    if (emptyState) emptyState.style.display = 'none';

    // load glb
    if (window.THREE.GLTFLoader) {
      const loader = new THREE.GLTFLoader();
      loader.load(
        url,
        (gltf) => {
          const model = gltf.scene;
          model.name = 'loadedModel';

          // center and scale model
          const box = new THREE.Box3().setFromObject(model);
          const center = box.getCenter(new THREE.Vector3());
          const size = box.getSize(new THREE.Vector3());
          const maxDim = Math.max(size.x, size.y, size.z);
          const scale = 2 / maxDim;

          model.position.sub(center);
          model.scale.setScalar(scale);

          scene.add(model);

          // reset camera
          camera.position.set(3, 2, 3);
          camera.lookAt(0, 0, 0);
          if (controls) controls.target.set(0, 0, 0);
        },
        undefined,
        (err) => {
          console.error('failed to load model:', err);
        }
      );
    }
  }

  async function handleDownload(format) {
    if (!currentTask) return;

    const params = new URLSearchParams({
      provider: currentTask.provider,
      format: format || 'glb',
    });
    if (currentTask.subscriptionKey) {
      params.set('subscription_key', currentTask.subscriptionKey);
    }

    const url = `/api/models/download/${currentTask.taskId}?${params}`;

    // open download in new tab
    const a = document.createElement('a');
    a.href = url;
    a.download = `model.${format || 'glb'}`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
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

      grid.innerHTML = res.data
        .map(
          (item) => `
        <div class="model-history-item">
          <div class="model-history-item-name">${escapeHtml(item.name || item.prompt)}</div>
          <div class="model-history-item-meta">
            <span>${item.provider || 'unknown'}</span>
            <span>${item.status || ''}</span>
            <span>${formatDate(item.created_at)}</span>
          </div>
        </div>
      `
        )
        .join('');
    } catch {
      grid.innerHTML = '<div class="model-history-empty">history unavailable</div>';
    }
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
