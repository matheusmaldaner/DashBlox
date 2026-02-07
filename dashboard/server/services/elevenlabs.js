// elevenlabs api client - sfx generation, tts, voice cloning

const config = require('../config');

const BASE_URL = 'https://api.elevenlabs.io/v1';

// generate sound effect and return audio buffer
async function generateSFX({ text, durationSeconds, promptInfluence }) {
  const apiKey = config.elevenlabsApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('ELEVENLABS_API_KEY not configured'), { status: 503 });
  }

  if (!text || text.trim().length === 0) {
    throw Object.assign(new Error('text prompt is required'), { status: 400 });
  }

  const body = {
    text: text.trim(),
    prompt_influence: promptInfluence ?? 0.3,
  };

  // only include duration if explicitly set (0 = auto)
  if (durationSeconds && durationSeconds > 0) {
    body.duration_seconds = durationSeconds;
  }

  const response = await fetch(`${BASE_URL}/sound-generation`, {
    method: 'POST',
    headers: {
      'xi-api-key': apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`elevenlabs api error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  const arrayBuffer = await response.arrayBuffer();
  const contentType = response.headers.get('content-type') || 'audio/mpeg';

  return { buffer: Buffer.from(arrayBuffer), contentType };
}

// generate text-to-speech and return audio buffer
async function generateTTS({ text, voiceId, modelId, stability, similarityBoost, speed }) {
  const apiKey = config.elevenlabsApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('ELEVENLABS_API_KEY not configured'), { status: 503 });
  }

  if (!text || text.trim().length === 0) {
    throw Object.assign(new Error('text is required'), { status: 400 });
  }

  if (!voiceId) {
    throw Object.assign(new Error('voice_id is required'), { status: 400 });
  }

  const body = {
    text: text.trim(),
    model_id: modelId || 'eleven_flash_v2_5',
    voice_settings: {
      stability: stability ?? 0.5,
      similarity_boost: similarityBoost ?? 0.75,
      speed: speed ?? 1.0,
    },
  };

  const response = await fetch(`${BASE_URL}/text-to-speech/${voiceId}`, {
    method: 'POST',
    headers: {
      'xi-api-key': apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`elevenlabs tts error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  const arrayBuffer = await response.arrayBuffer();
  const contentType = response.headers.get('content-type') || 'audio/mpeg';

  return { buffer: Buffer.from(arrayBuffer), contentType };
}

// list available voices
async function listVoices({ search, pageSize } = {}) {
  const apiKey = config.elevenlabsApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('ELEVENLABS_API_KEY not configured'), { status: 503 });
  }

  const params = new URLSearchParams();
  if (search) params.set('search', search);
  params.set('page_size', String(pageSize || 100));
  params.set('sort', 'name');
  params.set('sort_direction', 'asc');
  params.set('include_total_count', 'true');

  const response = await fetch(`https://api.elevenlabs.io/v2/voices?${params}`, {
    headers: { 'xi-api-key': apiKey },
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`elevenlabs voices error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  return response.json();
}

// clone a voice from audio samples
async function cloneVoice({ name, description, fileBuffers }) {
  const apiKey = config.elevenlabsApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('ELEVENLABS_API_KEY not configured'), { status: 503 });
  }

  if (!name) {
    throw Object.assign(new Error('voice name is required'), { status: 400 });
  }

  if (!fileBuffers || fileBuffers.length === 0) {
    throw Object.assign(new Error('at least one audio sample is required'), { status: 400 });
  }

  // build multipart form data manually
  const boundary = `----ElevenLabsBoundary${Date.now()}`;
  const parts = [];

  // name field
  parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="name"\r\n\r\n${name}`);

  // description field
  if (description) {
    parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="description"\r\n\r\n${description}`);
  }

  // remove background noise
  parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="remove_background_noise"\r\n\r\ntrue`);

  // file parts
  for (let i = 0; i < fileBuffers.length; i++) {
    const file = fileBuffers[i];
    const fileHeader = `--${boundary}\r\nContent-Disposition: form-data; name="files"; filename="${file.originalname || `sample-${i}.mp3`}"\r\nContent-Type: ${file.mimetype || 'audio/mpeg'}\r\n\r\n`;
    parts.push(fileHeader);
    parts.push(file.buffer);
    parts.push('\r\n');
  }

  parts.push(`--${boundary}--\r\n`);

  // combine parts into a single buffer
  const bodyParts = parts.map((p) => (typeof p === 'string' ? Buffer.from(p) : p));
  const bodyBuffer = Buffer.concat(bodyParts);

  const response = await fetch(`${BASE_URL}/voices/add`, {
    method: 'POST',
    headers: {
      'xi-api-key': apiKey,
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
    },
    body: bodyBuffer,
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`elevenlabs voice clone error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  return response.json();
}

module.exports = { generateSFX, generateTTS, listVoices, cloneVoice };
