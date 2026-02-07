// tests for voice generation api routes

const request = require('supertest');
const express = require('express');

// mock elevenlabs service
jest.mock('../server/services/elevenlabs', () => ({
  generateSFX: jest.fn(),
  generateTTS: jest.fn(),
  listVoices: jest.fn(),
  cloneVoice: jest.fn(),
}));

// mock AssetAudio model
jest.mock('../server/models/AssetAudio', () => ({
  create: jest.fn(),
  find: jest.fn(() => ({
    sort: jest.fn(() => ({
      limit: jest.fn(() => ({
        lean: jest.fn().mockResolvedValue([]),
      })),
    })),
  })),
}));

const { generateTTS, listVoices, cloneVoice } = require('../server/services/elevenlabs');
const AssetAudio = require('../server/models/AssetAudio');
const audioRouter = require('../server/routes/audio');

function createApp() {
  const app = express();
  app.use(express.json());
  app.use('/api/audio', audioRouter);
  app.use((err, _req, res, _next) => {
    res.status(err.status || 500).json({ success: false, error: err.message });
  });
  return app;
}

describe('POST /api/audio/tts', () => {
  const app = createApp();

  test('returns audio buffer on success', async () => {
    const fakeBuffer = Buffer.from('fake-tts-audio');
    generateTTS.mockResolvedValue({
      buffer: fakeBuffer,
      contentType: 'audio/mpeg',
    });

    const res = await request(app)
      .post('/api/audio/tts')
      .send({
        text: 'hello world',
        voice_id: 'voice123',
        model_id: 'eleven_flash_v2_5',
        stability: 0.5,
        similarity_boost: 0.75,
        speed: 1.0,
      });

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/audio\/mpeg/);
    expect(generateTTS).toHaveBeenCalledWith({
      text: 'hello world',
      voiceId: 'voice123',
      modelId: 'eleven_flash_v2_5',
      stability: 0.5,
      similarityBoost: 0.75,
      speed: 1.0,
    });
  });

  test('passes error when voice_id is missing', async () => {
    generateTTS.mockRejectedValue(
      Object.assign(new Error('voice_id is required'), { status: 400 })
    );

    const res = await request(app)
      .post('/api/audio/tts')
      .send({ text: 'hello' });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe('voice_id is required');
  });

  test('passes error when api key is missing', async () => {
    generateTTS.mockRejectedValue(
      Object.assign(new Error('ELEVENLABS_API_KEY not configured'), { status: 503 })
    );

    const res = await request(app)
      .post('/api/audio/tts')
      .send({ text: 'hello', voice_id: 'v1' });

    expect(res.status).toBe(503);
    expect(res.body.error).toBe('ELEVENLABS_API_KEY not configured');
  });
});

describe('POST /api/audio/tts/save', () => {
  const app = createApp();

  test('saves tts metadata and returns asset', async () => {
    const fakeAsset = {
      _id: 'tts123',
      name: 'hello world',
      type: 'tts',
      prompt: 'hello world',
      voice_name: 'Rachel',
    };
    AssetAudio.create.mockResolvedValue(fakeAsset);

    const res = await request(app)
      .post('/api/audio/tts/save')
      .send({
        text: 'hello world',
        voice_id: 'voice123',
        voice_name: 'Rachel',
        model_id: 'eleven_flash_v2_5',
      });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toEqual(fakeAsset);
    expect(AssetAudio.create).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'hello world',
        type: 'tts',
        prompt: 'hello world',
        voice_name: 'Rachel',
      })
    );
  });

  test('returns 400 when text is missing', async () => {
    const res = await request(app)
      .post('/api/audio/tts/save')
      .send({ voice_id: 'v1' });

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toBe('text is required');
  });
});

describe('GET /api/audio/voices', () => {
  const app = createApp();

  test('returns list of voices', async () => {
    const fakeVoices = {
      voices: [
        { voice_id: 'v1', name: 'Rachel', category: 'premade' },
        { voice_id: 'v2', name: 'Adam', category: 'premade' },
      ],
      has_more: false,
      total_count: 2,
    };
    listVoices.mockResolvedValue(fakeVoices);

    const res = await request(app).get('/api/audio/voices');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.voices).toHaveLength(2);
    expect(listVoices).toHaveBeenCalledWith({
      search: undefined,
      pageSize: undefined,
    });
  });

  test('passes search and page_size params', async () => {
    listVoices.mockResolvedValue({ voices: [], has_more: false, total_count: 0 });

    const res = await request(app).get('/api/audio/voices?search=rachel&page_size=10');

    expect(res.status).toBe(200);
    expect(listVoices).toHaveBeenCalledWith({
      search: 'rachel',
      pageSize: 10,
    });
  });

  test('passes error when api key is missing', async () => {
    listVoices.mockRejectedValue(
      Object.assign(new Error('ELEVENLABS_API_KEY not configured'), { status: 503 })
    );

    const res = await request(app).get('/api/audio/voices');

    expect(res.status).toBe(503);
    expect(res.body.error).toBe('ELEVENLABS_API_KEY not configured');
  });
});

describe('POST /api/audio/voice-clone', () => {
  const app = createApp();

  test('clones voice with uploaded files', async () => {
    cloneVoice.mockResolvedValue({
      voice_id: 'cloned_v1',
      requires_verification: false,
    });

    const res = await request(app)
      .post('/api/audio/voice-clone')
      .field('name', 'test-character')
      .field('description', 'a test voice')
      .attach('files', Buffer.from('fake-audio'), {
        filename: 'sample.mp3',
        contentType: 'audio/mpeg',
      });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.voice_id).toBe('cloned_v1');
    expect(cloneVoice).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'test-character',
        description: 'a test voice',
      })
    );
  });

  test('passes error when service rejects', async () => {
    cloneVoice.mockRejectedValue(
      Object.assign(new Error('voice name is required'), { status: 400 })
    );

    const res = await request(app)
      .post('/api/audio/voice-clone')
      .field('name', '')
      .attach('files', Buffer.from('fake-audio'), {
        filename: 'sample.mp3',
        contentType: 'audio/mpeg',
      });

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toBe('voice name is required');
  });
});
