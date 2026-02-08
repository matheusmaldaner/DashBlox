// audio routes - sfx generation, tts, voice cloning

const express = require('express');
const router = express.Router();
const multer = require('multer');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { generateSFX, generateTTS, listVoices, cloneVoice } = require('../services/elevenlabs');
const { enhancePrompt } = require('../services/openrouter');
const AssetAudio = require('../models/AssetAudio');

// ensure audio uploads directory exists
const audioDir = path.join(__dirname, '..', '..', 'uploads', 'audio');
if (!fs.existsSync(audioDir)) {
  fs.mkdirSync(audioDir, { recursive: true });
}

// multer for voice clone file uploads (memory storage)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 25 * 1024 * 1024 }, // 25mb per file
  fileFilter: (_req, file, cb) => {
    if (file.mimetype.startsWith('audio/')) {
      cb(null, true);
    } else {
      cb(new Error('only audio files are allowed'));
    }
  },
});

// POST /api/audio/enhance-prompt - enhance sfx prompt via openrouter/gemini
router.post('/enhance-prompt', async (req, res, next) => {
  try {
    const { prompt } = req.body;
    const result = await enhancePrompt({ prompt, type: 'audio' });
    res.json({ success: true, data: result });
  } catch (err) {
    next(err);
  }
});

// POST /api/audio/sfx - generate sound effect via elevenlabs
router.post('/sfx', async (req, res, next) => {
  try {
    const { text, duration_seconds, prompt_influence } = req.body;

    const { buffer, contentType } = await generateSFX({
      text,
      durationSeconds: duration_seconds,
      promptInfluence: prompt_influence,
    });

    res.setHeader('Content-Type', contentType);
    res.send(buffer);
  } catch (err) {
    next(err);
  }
});

// POST /api/audio/sfx/save - save sfx metadata + audio file to mongodb
router.post('/sfx/save', async (req, res, next) => {
  try {
    const { prompt, duration_seconds, prompt_influence, variation_count, audio_data, variation_data } = req.body;

    if (!prompt) {
      return res.status(400).json({ success: false, error: 'prompt is required' });
    }

    // persist all variation audio files to disk
    const variationFiles = [];
    const audioArray = variation_data || (audio_data ? [audio_data] : []);
    for (const b64 of audioArray) {
      if (!b64) {
        variationFiles.push('');
        continue;
      }
      const buffer = Buffer.from(b64, 'base64');
      const fileName = `sfx-${crypto.randomUUID()}.mp3`;
      fs.writeFileSync(path.join(audioDir, fileName), buffer);
      variationFiles.push(`/uploads/audio/${fileName}`);
    }

    // first valid file is the primary file_path (backwards compat)
    const filePath = variationFiles.find((f) => f) || '';

    const asset = await AssetAudio.create({
      name: prompt.slice(0, 60),
      type: 'sfx',
      prompt,
      model: 'elevenlabs-sfx',
      duration_seconds: duration_seconds || 0,
      file_path: filePath,
      variation_files: variationFiles,
      tags: [`influence:${prompt_influence || 0.3}`, `variations:${variation_count || 10}`],
      params: {
        duration: duration_seconds || 0,
        influence: prompt_influence || 0.3,
        variations: variation_count || 4,
      },
    });

    res.json({ success: true, data: asset });
  } catch (err) {
    next(err);
  }
});

// POST /api/audio/tts - generate text-to-speech via elevenlabs
router.post('/tts', async (req, res, next) => {
  try {
    const { text, voice_id, model_id, stability, similarity_boost, speed } = req.body;

    const { buffer, contentType } = await generateTTS({
      text,
      voiceId: voice_id,
      modelId: model_id,
      stability,
      similarityBoost: similarity_boost,
      speed,
    });

    res.setHeader('Content-Type', contentType);
    res.send(buffer);
  } catch (err) {
    next(err);
  }
});

// POST /api/audio/tts/save - save tts metadata + audio file to mongodb
router.post('/tts/save', async (req, res, next) => {
  try {
    const { text, voice_id, voice_name, model_id, stability, similarity, speed, audio_data } = req.body;

    if (!text) {
      return res.status(400).json({ success: false, error: 'text is required' });
    }

    // persist audio file to disk if provided
    let filePath = '';
    if (audio_data) {
      const buffer = Buffer.from(audio_data, 'base64');
      const fileName = `tts-${crypto.randomUUID()}.mp3`;
      fs.writeFileSync(path.join(audioDir, fileName), buffer);
      filePath = `/uploads/audio/${fileName}`;
    }

    const asset = await AssetAudio.create({
      name: text.slice(0, 60),
      type: 'tts',
      prompt: text,
      voice_id,
      voice_name: voice_name || 'unknown',
      model: model_id || 'eleven_flash_v2_5',
      file_path: filePath,
      params: {
        voice_id,
        voice_name: voice_name || 'unknown',
        model_id: model_id || 'eleven_flash_v2_5',
        stability: stability ?? 0.5,
        similarity: similarity ?? 0.75,
        speed: speed ?? 1.0,
      },
    });

    res.json({ success: true, data: asset });
  } catch (err) {
    next(err);
  }
});

// POST /api/audio/voice-clone - create voice clone from audio samples
router.post('/voice-clone', upload.array('files', 10), async (req, res, next) => {
  try {
    const { name, description } = req.body;

    const result = await cloneVoice({
      name,
      description,
      fileBuffers: req.files,
    });

    res.json({ success: true, data: result });
  } catch (err) {
    next(err);
  }
});

// GET /api/audio/voices - list available voices from elevenlabs
router.get('/voices', async (req, res, next) => {
  try {
    const { search, page_size } = req.query;
    const result = await listVoices({
      search,
      pageSize: page_size ? parseInt(page_size, 10) : undefined,
    });

    res.json({ success: true, data: result });
  } catch (err) {
    next(err);
  }
});

// GET /api/audio/history/:id/download - download a specific generation's audio file
router.get('/history/:id/download', async (req, res, next) => {
  try {
    const asset = await AssetAudio.findById(req.params.id).lean();
    if (!asset || !asset.file_path) {
      return res.status(404).json({ success: false, error: 'audio not found' });
    }

    const filePath = path.join(__dirname, '..', '..', asset.file_path);
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, error: 'audio file missing from disk' });
    }

    const filename = `${asset.name.replace(/[^a-zA-Z0-9_-]/g, '-').slice(0, 40)}.mp3`;
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Content-Type', 'audio/mpeg');
    fs.createReadStream(filePath).pipe(res);
  } catch (err) {
    next(err);
  }
});

// GET /api/audio/history - list previous audio generations
router.get('/history', async (_req, res, next) => {
  try {
    const assets = await AssetAudio.find()
      .sort({ created_at: -1 })
      .limit(50)
      .lean();

    res.json({ success: true, data: assets });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
