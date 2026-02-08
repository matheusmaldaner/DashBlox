// audio tab - sfx generation with configurable parallel variations

(function () {
  const DEFAULT_VARIATIONS = 4;
  const MAX_VARIATIONS = 10;
  const STAGGER_DELAY = 600;

  // audio data storage
  let audioData = new Array(DEFAULT_VARIATIONS).fill(null);
  let currentVariationCount = DEFAULT_VARIATIONS;
  let currentDownloadIndex = -1;
  let currentlyPlaying = null;

  // svg icons
  const playIcon =
    '<svg viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>';
  const pauseIcon =
    '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg>';
  const downloadIcon =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>';
  const reloadIcon =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/></svg>';
  const sfxIcon =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/></svg>';
  const ttsIcon =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>';

  document.addEventListener('DOMContentLoaded', () => {
    initAudioTab();
    loadHistory();
  });

  function buildAudioCards(count) {
    const grid = document.getElementById('audioGrid');
    if (!grid) return;

    stopAllAudio();
    audioData = new Array(count).fill(null);
    currentVariationCount = count;

    grid.innerHTML = '';
    for (let i = 0; i < count; i++) {
      const card = document.createElement('div');
      card.className = 'audio-card';
      card.id = `audioCard${i}`;
      card.innerHTML = `
        <div class="audio-card-header">
          <span class="audio-card-number">#${i + 1}</span>
          <span class="status-badge waiting">waiting</span>
        </div>
        <div class="audio-card-actions">
          <button class="play-btn" disabled>${playIcon}</button>
          <button class="download-btn" disabled>${downloadIcon}</button>
        </div>
      `;
      grid.appendChild(card);
    }
  }

  function initAudioTab() {
    // slider value displays
    const durationSlider = document.getElementById('sfxDuration');
    const durationValue = document.getElementById('sfxDurationValue');
    const influenceSlider = document.getElementById('sfxInfluence');
    const influenceValue = document.getElementById('sfxInfluenceValue');
    const variationsSlider = document.getElementById('sfxVariations');
    const variationsValue = document.getElementById('sfxVariationsValue');

    if (durationSlider) {
      durationSlider.addEventListener('input', () => {
        const val = parseFloat(durationSlider.value);
        durationValue.textContent = val === 0 ? 'Auto' : `${val}s`;
      });
    }

    if (influenceSlider) {
      influenceSlider.addEventListener('input', () => {
        influenceValue.textContent = influenceSlider.value;
      });
    }

    if (variationsSlider) {
      variationsSlider.addEventListener('input', () => {
        const count = parseInt(variationsSlider.value, 10);
        variationsValue.textContent = count;
        buildAudioCards(count);
      });
    }

    // build initial cards
    buildAudioCards(DEFAULT_VARIATIONS);

    // enhance button
    const enhanceBtn = document.getElementById('sfxEnhanceBtn');
    if (enhanceBtn) enhanceBtn.addEventListener('click', handleEnhance);

    // generate button
    const generateBtn = document.getElementById('sfxGenerateBtn');
    if (generateBtn) {
      generateBtn.addEventListener('click', handleGenerate);
    }

    // download modal
    const cancelBtn = document.getElementById('downloadCancelBtn');
    const confirmBtn = document.getElementById('downloadConfirmBtn');
    if (cancelBtn) cancelBtn.addEventListener('click', closeDownloadModal);
    if (confirmBtn) confirmBtn.addEventListener('click', handleDownload);
  }

  async function handleEnhance() {
    const promptInput = document.getElementById('sfxPrompt');
    const prompt = promptInput.value.trim();
    if (!prompt) {
      promptInput.focus();
      return;
    }

    const enhanceBtn = document.getElementById('sfxEnhanceBtn');
    const statusEl = document.getElementById('sfxStatus');
    const enhancedEl = document.getElementById('sfxEnhancedPrompt');
    const enhancedText = document.getElementById('sfxEnhancedPromptText');

    enhanceBtn.disabled = true;
    statusEl.innerHTML = '<div class="spinner"></div> enhancing prompt...';
    statusEl.className = 'audio-status';

    try {
      const res = await api.postJSON('/api/audio/enhance-prompt', { prompt });
      enhancedText.textContent = res.data.enhanced;
      enhancedEl.classList.add('visible');
      statusEl.innerHTML = 'prompt enhanced';
    } catch (err) {
      statusEl.innerHTML = `enhance failed: ${err.message}`;
      statusEl.className = 'audio-status error';
    }

    enhanceBtn.disabled = false;
  }

  async function handleGenerate() {
    const promptInput = document.getElementById('sfxPrompt');
    const prompt = promptInput.value.trim();
    if (!prompt) {
      promptInput.focus();
      return;
    }

    // use enhanced prompt if available
    const enhancedText = document.getElementById('sfxEnhancedPromptText');
    const enhancedPrompt = enhancedText ? enhancedText.textContent.trim() : '';
    const textToGenerate = enhancedPrompt || prompt;

    const duration = parseFloat(document.getElementById('sfxDuration').value);
    const influence = parseFloat(document.getElementById('sfxInfluence').value);
    const variationCount = currentVariationCount;
    const generateBtn = document.getElementById('sfxGenerateBtn');
    const variationsSlider = document.getElementById('sfxVariations');
    const statusEl = document.getElementById('sfxStatus');

    // reset state
    generateBtn.disabled = true;
    if (variationsSlider) variationsSlider.disabled = true;
    audioData = new Array(variationCount).fill(null);
    stopAllAudio();

    // reset all cards
    for (let i = 0; i < variationCount; i++) {
      setCardStatus(i, 'waiting');
      setCardButtons(i, false);
    }

    let completedCount = 0;
    let successCount = 0;

    statusEl.innerHTML = '<div class="spinner"></div> generating... 0/' + variationCount;
    statusEl.className = 'audio-status';

    const promises = [];

    for (let i = 0; i < variationCount; i++) {
      const delayedRequest = (async () => {
        await sleep(i * STAGGER_DELAY);
        setCardStatus(i, 'generating');

        try {
          const blob = await api.postBlob('/api/audio/sfx', {
            text: textToGenerate,
            duration_seconds: duration,
            prompt_influence: influence,
          });

          const url = URL.createObjectURL(blob);
          audioData[i] = { blob, url };
          setCardStatus(i, 'ready');
          setCardButtons(i, true);
          successCount++;
        } catch (err) {
          console.error(`variation ${i + 1} failed:`, err.message);
          setCardStatus(i, 'error');
        }

        completedCount++;
        statusEl.innerHTML =
          completedCount < variationCount
            ? `<div class="spinner"></div> generating... ${completedCount}/${variationCount} (${successCount} ready)`
            : `done - ${successCount}/${variationCount} generated`;
        statusEl.className = 'audio-status' + (successCount === 0 && completedCount === variationCount ? ' error' : '');
      })();
      promises.push(delayedRequest);
    }

    await Promise.all(promises);
    generateBtn.disabled = false;
    if (variationsSlider) variationsSlider.disabled = false;

    // save generation metadata to history
    if (successCount > 0) {
      saveToHistory(prompt, duration, influence, successCount);
    }
  }

  function setCardStatus(index, status) {
    const badge = document.querySelector(`#audioCard${index} .status-badge`);
    if (!badge) return;

    const labels = {
      waiting: 'waiting',
      generating: '<div class="badge-spinner"></div> generating',
      ready: 'ready',
      error: 'error',
    };

    badge.className = `status-badge ${status}`;
    badge.innerHTML = labels[status] || status;
  }

  function setCardButtons(index, enabled) {
    const card = document.getElementById(`audioCard${index}`);
    if (!card) return;

    const playBtn = card.querySelector('.play-btn');
    const dlBtn = card.querySelector('.download-btn');
    if (playBtn) playBtn.disabled = !enabled;
    if (dlBtn) dlBtn.disabled = !enabled;

    if (enabled) {
      playBtn.onclick = () => togglePlay(index);
      dlBtn.onclick = () => openDownloadModal(index);
    }
  }

  function togglePlay(index) {
    const data = audioData[index];
    if (!data) return;

    const playBtn = document.querySelector(`#audioCard${index} .play-btn`);

    // if this one is currently playing, stop it
    if (currentlyPlaying && currentlyPlaying.index === index) {
      currentlyPlaying.audio.pause();
      currentlyPlaying.audio.currentTime = 0;
      playBtn.innerHTML = playIcon;
      playBtn.classList.remove('playing');
      currentlyPlaying = null;
      return;
    }

    // stop any other playing audio
    stopAllAudio();

    // play this one
    const audio = new Audio(data.url);
    audio.play();
    playBtn.innerHTML = pauseIcon;
    playBtn.classList.add('playing');
    currentlyPlaying = { audio, index };

    audio.onended = () => {
      playBtn.innerHTML = playIcon;
      playBtn.classList.remove('playing');
      currentlyPlaying = null;
    };
  }

  function stopAllAudio() {
    if (currentlyPlaying) {
      currentlyPlaying.audio.pause();
      currentlyPlaying.audio.currentTime = 0;

      // handle audio card playback
      if (currentlyPlaying.index >= 0) {
        const btn = document.querySelector(`#audioCard${currentlyPlaying.index} .play-btn`);
        if (btn) {
          btn.innerHTML = playIcon;
          btn.classList.remove('playing');
        }
      }

      // handle history item playback
      if (currentlyPlaying.element) {
        const histBtn = currentlyPlaying.element.querySelector('.history-play-btn');
        if (histBtn) {
          histBtn.innerHTML = playIcon;
          histBtn.classList.remove('playing');
        }
        currentlyPlaying.element.classList.remove('playing');
      }

      currentlyPlaying = null;
    }
  }

  function openDownloadModal(index) {
    currentDownloadIndex = index;
    const prompt = document.getElementById('sfxPrompt').value.trim();
    const sanitized = prompt.replace(/[^a-zA-Z0-9_-]/g, '-').slice(0, 40);
    const filename = `${sanitized}-${index + 1}`;

    document.getElementById('downloadFilename').value = filename;
    document.getElementById('downloadModal').classList.add('active');
  }

  function closeDownloadModal() {
    document.getElementById('downloadModal').classList.remove('active');
    currentDownloadIndex = -1;
  }

  function handleDownload() {
    if (currentDownloadIndex < 0) return;
    const data = audioData[currentDownloadIndex];
    if (!data) return;

    let filename = document.getElementById('downloadFilename').value.trim() || 'sound-effect';
    filename = filename.replace(/[^a-zA-Z0-9_-]/g, '-');
    if (!filename.endsWith('.mp3')) filename += '.mp3';

    const a = document.createElement('a');
    a.href = data.url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);

    closeDownloadModal();
  }

  async function saveToHistory(prompt, duration, influence, variationCount) {
    try {
      // encode all variation blobs as base64 (null for failed ones)
      const variationData = [];
      for (let i = 0; i < audioData.length; i++) {
        if (audioData[i] && audioData[i].blob) {
          try {
            const b64 = await blobToBase64(audioData[i].blob);
            variationData.push(b64);
          } catch (encErr) {
            console.warn('base64 encoding failed for variation', i, encErr);
            variationData.push(null);
          }
        } else {
          variationData.push(null);
        }
      }

      const hasAny = variationData.some((d) => d !== null);
      if (!hasAny) {
        console.warn('no audio data to persist, saving metadata only');
      }

      await api.postJSON('/api/audio/sfx/save', {
        prompt,
        duration_seconds: duration,
        prompt_influence: influence,
        variation_count: variationCount,
        variation_data: variationData,
      });
      loadHistory();
    } catch (err) {
      console.warn('failed to save to history:', err.message);
    }
  }

  // reliable blob to base64 using FileReader (avoids btoa stack issues with large data)
  function blobToBase64(blob) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => {
        // result is "data:audio/mpeg;base64,XXXX", strip the prefix
        const base64 = reader.result.split(',')[1];
        if (base64) {
          resolve(base64);
        } else {
          reject(new Error('empty base64 result'));
        }
      };
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(blob);
    });
  }

  async function loadHistory() {
    const list = document.getElementById('historyList');
    if (!list) return;

    try {
      const res = await api.getJSON('/api/audio/history');
      if (!res.success || !res.data.length) {
        list.innerHTML = '<div class="history-empty">no previous generations</div>';
        return;
      }

      list.innerHTML = res.data
        .map(
          (item) => `
        <div class="history-item" data-id="${item._id}" data-file-path="${escapeHtml(item.file_path || '')}" data-type="${item.type}" data-params="${escapeAttr(JSON.stringify(item.params || {}))}" data-prompt="${escapeAttr(item.prompt || item.name)}" data-variation-files="${escapeAttr(JSON.stringify(item.variation_files || []))}">
          <div class="history-item-icon ${item.type}">
            ${item.type === 'tts' ? ttsIcon : sfxIcon}
          </div>
          <div class="history-item-info">
            <div class="history-item-prompt">${escapeHtml(item.prompt || item.name)}</div>
            <div class="history-item-meta">
              <span class="history-type-badge">${item.type}</span>
              ${item.variation_files && item.variation_files.filter(Boolean).length > 1 ? `<span>${item.variation_files.filter(Boolean).length} variations</span>` : ''}
              <span>${formatDate(item.created_at)}</span>
            </div>
          </div>
          <div class="history-item-actions">
            ${item.file_path ? `<button class="history-action-btn history-play-btn" title="play">${playIcon}</button>` : '<span class="history-no-audio">no audio</span>'}
            ${item.file_path ? `<button class="history-action-btn history-download-btn" title="download">${downloadIcon}</button>` : ''}
            <button class="history-action-btn history-reload-btn" title="reload settings">${reloadIcon}</button>
          </div>
        </div>
      `
        )
        .join('');

      // attach button handlers
      list.querySelectorAll('.history-item').forEach((el) => {
        const filePath = el.dataset.filePath;
        const playBtn = el.querySelector('.history-play-btn');
        const dlBtn = el.querySelector('.history-download-btn');
        const reloadBtn = el.querySelector('.history-reload-btn');

        // clicking the row itself triggers reload
        el.addEventListener('click', () => reloadGeneration(el));
        el.style.cursor = 'pointer';

        if (playBtn && filePath) {
          playBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            playHistoryItem(filePath, el);
          });
        }

        if (dlBtn && filePath) {
          dlBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            downloadHistoryItem(el.dataset.id, el.dataset.prompt);
          });
        }

        if (reloadBtn) {
          reloadBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            reloadGeneration(el);
          });
        }
      });
    } catch (err) {
      console.error('loadHistory failed:', err);
      list.innerHTML = '<div class="history-empty">history unavailable</div>';
    }
  }

  function playHistoryItem(filePath, element) {
    const playBtn = element.querySelector('.history-play-btn');

    // if this element is currently playing, stop it
    if (currentlyPlaying && currentlyPlaying.element === element) {
      currentlyPlaying.audio.pause();
      currentlyPlaying.audio.currentTime = 0;
      if (playBtn) {
        playBtn.innerHTML = playIcon;
        playBtn.classList.remove('playing');
      }
      element.classList.remove('playing');
      currentlyPlaying = null;
      return;
    }

    // stop any currently playing audio first
    stopAllAudio();

    const audio = new Audio(filePath);
    audio.play();

    if (playBtn) {
      playBtn.innerHTML = pauseIcon;
      playBtn.classList.add('playing');
    }
    element.classList.add('playing');

    currentlyPlaying = { audio, index: -1, element };

    audio.addEventListener('ended', () => {
      if (playBtn) {
        playBtn.innerHTML = playIcon;
        playBtn.classList.remove('playing');
      }
      element.classList.remove('playing');
      currentlyPlaying = null;
    });
  }

  function downloadHistoryItem(id, name) {
    const a = document.createElement('a');
    a.href = `/api/audio/history/${id}/download`;
    a.download = `${(name || 'audio').replace(/[^a-zA-Z0-9_-]/g, '-').slice(0, 40)}.mp3`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  }

  function reloadGeneration(element) {
    const type = element.dataset.type;
    const prompt = element.dataset.prompt;
    const filePath = element.dataset.filePath;
    let params = {};
    let variationFiles = [];
    try { params = JSON.parse(element.dataset.params); } catch { /* ignore */ }
    try { variationFiles = JSON.parse(element.dataset.variationFiles || '[]'); } catch { /* ignore */ }

    if (type === 'sfx') {
      reloadSfxGeneration(prompt, params, filePath, variationFiles);
    } else if (type === 'tts') {
      reloadTtsGeneration(prompt, params);
    }
  }

  async function reloadSfxGeneration(prompt, params, filePath, variationFiles) {
    const promptInput = document.getElementById('sfxPrompt');
    const durationSlider = document.getElementById('sfxDuration');
    const durationValue = document.getElementById('sfxDurationValue');
    const influenceSlider = document.getElementById('sfxInfluence');
    const influenceValue = document.getElementById('sfxInfluenceValue');
    const variationsSlider = document.getElementById('sfxVariations');
    const variationsValue = document.getElementById('sfxVariationsValue');

    if (promptInput) promptInput.value = prompt;

    if (durationSlider && params.duration !== undefined) {
      durationSlider.value = params.duration;
      if (durationValue) durationValue.textContent = params.duration === 0 ? 'Auto' : `${params.duration}s`;
    }

    if (influenceSlider && params.influence !== undefined) {
      influenceSlider.value = params.influence;
      if (influenceValue) influenceValue.textContent = params.influence;
    }

    // determine card count from variation files or params
    const cardCount = variationFiles.length || params.variations || currentVariationCount;
    if (variationsSlider) {
      variationsSlider.value = cardCount;
      if (variationsValue) variationsValue.textContent = cardCount;
    }
    buildAudioCards(cardCount);

    // scroll to the sfx controls
    const controls = document.querySelector('.audio-controls');
    if (controls) controls.scrollIntoView({ behavior: 'smooth', block: 'start' });

    // load all saved variation files into cards
    const files = variationFiles.length ? variationFiles : (filePath ? [filePath] : []);
    if (files.length === 0) return;

    const fetchPromises = files.map(async (fp, i) => {
      if (!fp || i >= cardCount) return;
      try {
        setCardStatus(i, 'generating');
        const response = await fetch(fp);
        if (!response.ok) throw new Error('fetch failed');
        const blob = await response.blob();
        const url = URL.createObjectURL(blob);
        audioData[i] = { blob, url };
        setCardStatus(i, 'ready');
        setCardButtons(i, true);
      } catch (err) {
        console.warn(`failed to load variation ${i}:`, err);
        setCardStatus(i, 'error');
      }
    });

    await Promise.all(fetchPromises);
  }

  function reloadTtsGeneration(prompt, params) {
    const voiceSelect = document.getElementById('voiceSelect');
    const modelSelect = document.getElementById('voiceModel');
    const stabilitySlider = document.getElementById('voiceStability');
    const stabilityValue = document.getElementById('voiceStabilityValue');
    const similaritySlider = document.getElementById('voiceSimilarity');
    const similarityValue = document.getElementById('voiceSimilarityValue');
    const speedSlider = document.getElementById('voiceSpeed');
    const speedValue = document.getElementById('voiceSpeedValue');
    const textArea = document.getElementById('voiceText');

    if (textArea) textArea.value = prompt;

    if (voiceSelect && params.voice_id) {
      voiceSelect.value = params.voice_id;
    }

    if (modelSelect && params.model_id) {
      modelSelect.value = params.model_id;
    }

    if (stabilitySlider && params.stability !== undefined) {
      stabilitySlider.value = params.stability;
      if (stabilityValue) stabilityValue.textContent = params.stability;
    }

    if (similaritySlider && params.similarity !== undefined) {
      similaritySlider.value = params.similarity;
      if (similarityValue) similarityValue.textContent = params.similarity;
    }

    if (speedSlider && params.speed !== undefined) {
      speedSlider.value = params.speed;
      if (speedValue) speedValue.textContent = params.speed;
    }

    // scroll to the voice section
    const voiceSection = document.querySelector('.voice-section');
    if (voiceSection) voiceSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function sleep(ms) {
    return new Promise((r) => setTimeout(r, ms));
  }

  // expose loadHistory globally so voice.js can refresh history after tts save
  window._refreshAudioHistory = loadHistory;

  function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }

  // escape for use inside double-quoted html attributes (handles ", <, >, &)
  function escapeAttr(str) {
    return str.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function formatDate(dateStr) {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    return d.toLocaleDateString() + ' ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }
})();
