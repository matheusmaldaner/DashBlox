// audio tab - sfx generation with 10 parallel variations

(function () {
  const VARIATION_COUNT = 10;
  const STAGGER_DELAY = 600;

  // audio data storage
  const audioData = new Array(VARIATION_COUNT).fill(null);
  let currentDownloadIndex = -1;
  let currentlyPlaying = null;

  // svg icons
  const playIcon =
    '<svg viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>';
  const pauseIcon =
    '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg>';

  document.addEventListener('DOMContentLoaded', () => {
    initAudioTab();
    loadHistory();
  });

  function initAudioTab() {
    // slider value displays
    const durationSlider = document.getElementById('sfxDuration');
    const durationValue = document.getElementById('sfxDurationValue');
    const influenceSlider = document.getElementById('sfxInfluence');
    const influenceValue = document.getElementById('sfxInfluenceValue');

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
    const generateBtn = document.getElementById('sfxGenerateBtn');
    const statusEl = document.getElementById('sfxStatus');

    // reset state
    generateBtn.disabled = true;
    audioData.fill(null);
    stopAllAudio();

    // reset all cards
    for (let i = 0; i < VARIATION_COUNT; i++) {
      setCardStatus(i, 'waiting');
      setCardButtons(i, false);
    }

    let completedCount = 0;
    let successCount = 0;

    statusEl.innerHTML = '<div class="spinner"></div> generating... 0/' + VARIATION_COUNT;
    statusEl.className = 'audio-status';

    const promises = [];

    for (let i = 0; i < VARIATION_COUNT; i++) {
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
          completedCount < VARIATION_COUNT
            ? `<div class="spinner"></div> generating... ${completedCount}/${VARIATION_COUNT} (${successCount} ready)`
            : `done - ${successCount}/${VARIATION_COUNT} generated`;
        statusEl.className = 'audio-status' + (successCount === 0 && completedCount === VARIATION_COUNT ? ' error' : '');
      })();
      promises.push(delayedRequest);
    }

    await Promise.all(promises);
    generateBtn.disabled = false;

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
      await api.postJSON('/api/audio/sfx/save', {
        prompt,
        duration_seconds: duration,
        prompt_influence: influence,
        variation_count: variationCount,
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
        <div class="history-item">
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
        </div>
      `
        )
        .join('');
    } catch {
      // history load is non-critical
      list.innerHTML = '<div class="history-empty">history unavailable</div>';
    }
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
