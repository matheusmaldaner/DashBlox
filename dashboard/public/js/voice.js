// voice generation - tts, batch dialogue, voice cloning

(function () {
  // svg icons
  const playIcon =
    '<svg viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>';
  const pauseIcon =
    '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg>';
  const downloadIcon =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>';

  // state
  const voiceResults = []; // { text, blob, url, status }
  let currentlyPlaying = null;
  let cloneFiles = [];

  document.addEventListener('DOMContentLoaded', () => {
    initVoiceTab();
    loadVoices();
  });

  function initVoiceTab() {
    // slider value displays
    const stabilitySlider = document.getElementById('voiceStability');
    const stabilityValue = document.getElementById('voiceStabilityValue');
    const similaritySlider = document.getElementById('voiceSimilarity');
    const similarityValue = document.getElementById('voiceSimilarityValue');
    const speedSlider = document.getElementById('voiceSpeed');
    const speedValue = document.getElementById('voiceSpeedValue');

    if (stabilitySlider) {
      stabilitySlider.addEventListener('input', () => {
        stabilityValue.textContent = stabilitySlider.value;
      });
    }

    if (similaritySlider) {
      similaritySlider.addEventListener('input', () => {
        similarityValue.textContent = similaritySlider.value;
      });
    }

    if (speedSlider) {
      speedSlider.addEventListener('input', () => {
        speedValue.textContent = speedSlider.value;
      });
    }

    // generate button
    const generateBtn = document.getElementById('voiceGenerateBtn');
    if (generateBtn) {
      generateBtn.addEventListener('click', handleVoiceGenerate);
    }

    // clone file upload
    const uploadArea = document.getElementById('cloneUploadArea');
    const fileInput = document.getElementById('cloneFileInput');
    if (uploadArea && fileInput) {
      uploadArea.addEventListener('click', () => fileInput.click());
      fileInput.addEventListener('change', handleCloneFileSelect);
    }

    // clone button
    const cloneBtn = document.getElementById('cloneVoiceBtn');
    if (cloneBtn) {
      cloneBtn.addEventListener('click', handleVoiceClone);
    }
  }

  async function loadVoices() {
    const select = document.getElementById('voiceSelect');
    if (!select) return;

    try {
      const res = await api.getJSON('/api/audio/voices');
      if (!res.success || !res.data.voices || res.data.voices.length === 0) {
        select.innerHTML = '<option value="">no voices available</option>';
        return;
      }

      select.innerHTML = res.data.voices
        .map((v) => `<option value="${v.voice_id}">${escapeHtml(v.name)}${v.category ? ` (${v.category})` : ''}</option>`)
        .join('');
    } catch {
      select.innerHTML = '<option value="">failed to load voices</option>';
    }
  }

  async function handleVoiceGenerate() {
    const textArea = document.getElementById('voiceText');
    const text = textArea.value.trim();
    if (!text) {
      textArea.focus();
      return;
    }

    const voiceId = document.getElementById('voiceSelect').value;
    if (!voiceId) return;

    const modelId = document.getElementById('voiceModel').value;
    const stability = parseFloat(document.getElementById('voiceStability').value);
    const similarity = parseFloat(document.getElementById('voiceSimilarity').value);
    const speed = parseFloat(document.getElementById('voiceSpeed').value);
    const generateBtn = document.getElementById('voiceGenerateBtn');
    const statusEl = document.getElementById('voiceStatus');
    const resultsEl = document.getElementById('voiceResults');

    // split text into lines for batch generation
    const lines = text.split('\n').map((l) => l.trim()).filter((l) => l.length > 0);
    if (lines.length === 0) return;

    generateBtn.disabled = true;
    stopAllVoiceAudio();

    // reset results
    voiceResults.length = 0;
    resultsEl.innerHTML = '';

    // initialize result items
    for (let i = 0; i < lines.length; i++) {
      voiceResults.push({ text: lines[i], blob: null, url: null, status: 'generating' });
      resultsEl.appendChild(createResultItem(i, lines[i], 'generating'));
    }

    let completedCount = 0;
    let successCount = 0;

    statusEl.innerHTML = `<div class="spinner"></div> generating... 0/${lines.length}`;
    statusEl.className = 'voice-status';

    const voiceName = document.getElementById('voiceSelect').selectedOptions[0]?.textContent || 'unknown';

    // generate each line
    const promises = lines.map(async (line, i) => {
      try {
        const blob = await api.postBlob('/api/audio/tts', {
          text: line,
          voice_id: voiceId,
          model_id: modelId,
          stability,
          similarity_boost: similarity,
          speed,
        });

        const url = URL.createObjectURL(blob);
        voiceResults[i] = { text: line, blob, url, status: 'ready' };
        updateResultItem(i, 'ready');
        successCount++;
      } catch (err) {
        console.error(`voice line ${i + 1} failed:`, err.message);
        voiceResults[i].status = 'error';
        updateResultItem(i, 'error');
      }

      completedCount++;
      statusEl.innerHTML =
        completedCount < lines.length
          ? `<div class="spinner"></div> generating... ${completedCount}/${lines.length} (${successCount} ready)`
          : `done - ${successCount}/${lines.length} generated`;
      statusEl.className = 'voice-status' + (successCount === 0 && completedCount === lines.length ? ' error' : '');
    });

    await Promise.all(promises);
    generateBtn.disabled = false;

    // save metadata + first audio blob for successful generations
    if (successCount > 0) {
      try {
        // encode first successful voice result as base64
        let audioBase64 = null;
        for (const result of voiceResults) {
          if (result.blob) {
            const arrayBuffer = await result.blob.arrayBuffer();
            const bytes = new Uint8Array(arrayBuffer);
            let binary = '';
            for (let j = 0; j < bytes.length; j++) {
              binary += String.fromCharCode(bytes[j]);
            }
            audioBase64 = btoa(binary);
            break;
          }
        }

        await api.postJSON('/api/audio/tts/save', {
          text: lines.join(' | '),
          voice_id: voiceId,
          voice_name: voiceName,
          model_id: modelId,
          audio_data: audioBase64,
        });
      } catch {
        // save is non-critical
      }
    }
  }

  function createResultItem(index, text, status) {
    const div = document.createElement('div');
    div.className = 'voice-result-item';
    div.id = `voiceResult${index}`;
    div.innerHTML = `
      <span class="voice-result-text">${escapeHtml(text)}</span>
      <span class="voice-result-badge ${status}">
        ${status === 'generating' ? '<div class="badge-spinner"></div> ' : ''}${status}
      </span>
      <div class="voice-result-actions">
        <button class="play-btn" disabled>${playIcon}</button>
        <button class="download-btn" disabled>${downloadIcon}</button>
      </div>
    `;
    return div;
  }

  function updateResultItem(index, status) {
    const item = document.getElementById(`voiceResult${index}`);
    if (!item) return;

    const badge = item.querySelector('.voice-result-badge');
    badge.className = `voice-result-badge ${status}`;
    badge.innerHTML = status === 'generating' ? '<div class="badge-spinner"></div> generating' : status;

    if (status === 'ready') {
      const playBtn = item.querySelector('.play-btn');
      const dlBtn = item.querySelector('.download-btn');
      playBtn.disabled = false;
      dlBtn.disabled = false;

      playBtn.onclick = () => toggleVoicePlay(index);
      dlBtn.onclick = () => downloadVoiceResult(index);
    }
  }

  function toggleVoicePlay(index) {
    const data = voiceResults[index];
    if (!data || !data.url) return;

    const item = document.getElementById(`voiceResult${index}`);
    const playBtn = item.querySelector('.play-btn');

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
    stopAllVoiceAudio();

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

  function stopAllVoiceAudio() {
    if (currentlyPlaying) {
      currentlyPlaying.audio.pause();
      currentlyPlaying.audio.currentTime = 0;
      const item = document.getElementById(`voiceResult${currentlyPlaying.index}`);
      if (item) {
        const btn = item.querySelector('.play-btn');
        if (btn) {
          btn.innerHTML = playIcon;
          btn.classList.remove('playing');
        }
      }
      currentlyPlaying = null;
    }
  }

  function downloadVoiceResult(index) {
    const data = voiceResults[index];
    if (!data || !data.url) return;

    const sanitized = data.text.replace(/[^a-zA-Z0-9_-]/g, '-').slice(0, 40);
    const filename = `${sanitized}.mp3`;

    const a = document.createElement('a');
    a.href = data.url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  }

  // voice clone handlers
  function handleCloneFileSelect() {
    const fileInput = document.getElementById('cloneFileInput');
    const cloneBtn = document.getElementById('cloneVoiceBtn');

    // add new files to the list
    for (const file of fileInput.files) {
      cloneFiles.push(file);
    }

    // render file chips
    renderCloneFiles();

    // enable clone button if we have files and a name
    cloneBtn.disabled = cloneFiles.length === 0;

    // reset input so same file can be re-selected
    fileInput.value = '';
  }

  function renderCloneFiles() {
    const fileList = document.getElementById('cloneFileList');
    fileList.innerHTML = cloneFiles
      .map(
        (f, i) => `
      <span class="file-upload-chip">
        ${escapeHtml(f.name)}
        <button onclick="window._removeCloneFile(${i})">&times;</button>
      </span>
    `
      )
      .join('');
  }

  // expose remove function globally for inline onclick
  window._removeCloneFile = function (index) {
    cloneFiles.splice(index, 1);
    renderCloneFiles();
    document.getElementById('cloneVoiceBtn').disabled = cloneFiles.length === 0;
  };

  async function handleVoiceClone() {
    const name = document.getElementById('cloneVoiceName').value.trim();
    if (!name) {
      document.getElementById('cloneVoiceName').focus();
      return;
    }

    if (cloneFiles.length === 0) return;

    const description = document.getElementById('cloneVoiceDesc').value.trim();
    const cloneBtn = document.getElementById('cloneVoiceBtn');
    const statusEl = document.getElementById('cloneStatus');

    cloneBtn.disabled = true;
    statusEl.innerHTML = '<div class="spinner"></div> cloning voice...';
    statusEl.className = 'voice-status';

    try {
      const formData = new FormData();
      formData.append('name', name);
      if (description) formData.append('description', description);
      for (const file of cloneFiles) {
        formData.append('files', file);
      }

      const res = await fetch('/api/audio/voice-clone', {
        method: 'POST',
        body: formData,
      });

      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: res.statusText }));
        throw new Error(err.error || `request failed: ${res.status}`);
      }

      const data = await res.json();

      statusEl.innerHTML = `voice "${escapeHtml(name)}" cloned successfully (id: ${data.data.voice_id})`;
      statusEl.className = 'voice-status';

      // reset form
      document.getElementById('cloneVoiceName').value = '';
      document.getElementById('cloneVoiceDesc').value = '';
      cloneFiles = [];
      renderCloneFiles();

      // reload voices to include the new clone
      await loadVoices();
    } catch (err) {
      statusEl.innerHTML = `clone failed: ${escapeHtml(err.message)}`;
      statusEl.className = 'voice-status error';
    }

    cloneBtn.disabled = cloneFiles.length === 0;
  }

  function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }
})();
