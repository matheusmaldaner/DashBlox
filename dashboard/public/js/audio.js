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

  async function handleGenerate() {
    const promptInput = document.getElementById('sfxPrompt');
    const prompt = promptInput.value.trim();
    if (!prompt) {
      promptInput.focus();
      return;
    }

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
            text: prompt,
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
      const btn = document.querySelector(`#audioCard${currentlyPlaying.index} .play-btn`);
      if (btn) {
        btn.innerHTML = playIcon;
        btn.classList.remove('playing');
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
      // encode first successful audio blob as base64 for server persistence
      let audioBase64 = null;
      for (let i = 0; i < audioData.length; i++) {
        if (audioData[i] && audioData[i].blob) {
          const arrayBuffer = await audioData[i].blob.arrayBuffer();
          const bytes = new Uint8Array(arrayBuffer);
          let binary = '';
          for (let j = 0; j < bytes.length; j++) {
            binary += String.fromCharCode(bytes[j]);
          }
          audioBase64 = btoa(binary);
          break;
        }
      }

      await api.postJSON('/api/audio/sfx/save', {
        prompt,
        duration_seconds: duration,
        prompt_influence: influence,
        variation_count: variationCount,
        audio_data: audioBase64,
      });
      loadHistory();
    } catch (err) {
      // history save is non-critical, just log
      console.warn('failed to save to history:', err.message);
    }
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
        <div class="history-item ${item.file_path ? 'clickable' : ''}" data-file-path="${escapeHtml(item.file_path || '')}">
          <div class="history-item-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/></svg>
          </div>
          <div class="history-item-info">
            <div class="history-item-prompt">${escapeHtml(item.prompt || item.name)}</div>
            <div class="history-item-meta">
              <span>${item.type}</span>
              <span>${formatDate(item.created_at)}</span>
            </div>
          </div>
          ${item.file_path ? '<div class="history-item-play">' + playIcon + '</div>' : ''}
        </div>
      `
        )
        .join('');

      // attach click handlers for playable history items
      list.querySelectorAll('.history-item.clickable').forEach((el) => {
        el.addEventListener('click', () => {
          const filePath = el.dataset.filePath;
          if (filePath) playHistoryItem(filePath, el);
        });
      });
    } catch {
      // history load is non-critical
      list.innerHTML = '<div class="history-empty">history unavailable</div>';
    }
  }

  function playHistoryItem(filePath, element) {
    // stop any currently playing audio first
    stopAllAudio();

    const audio = new Audio(filePath);
    audio.play();

    const playBtn = element.querySelector('.history-item-play');
    if (playBtn) {
      playBtn.innerHTML = pauseIcon;
      element.classList.add('playing');
    }

    currentlyPlaying = { audio, index: -1 };

    audio.addEventListener('ended', () => {
      if (playBtn) {
        playBtn.innerHTML = playIcon;
        element.classList.remove('playing');
      }
      currentlyPlaying = null;
    });

    // clicking again stops playback
    element.addEventListener('click', function stopHandler() {
      if (currentlyPlaying && currentlyPlaying.audio === audio) {
        stopAllAudio();
        if (playBtn) {
          playBtn.innerHTML = playIcon;
          element.classList.remove('playing');
        }
        element.removeEventListener('click', stopHandler);
      }
    }, { once: true });
  }

  function sleep(ms) {
    return new Promise((r) => setTimeout(r, ms));
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
