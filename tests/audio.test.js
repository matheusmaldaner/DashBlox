// tests for audio api routes

const request = require('supertest');
const express = require('express');

// mock elevenlabs service before requiring routes
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
        lean: jest.fn(),
      })),
    })),
  })),
}));

const { generateSFX } = require('../server/services/elevenlabs');
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

describe('POST /api/audio/sfx', () => {
  const app = createApp();

  test('returns audio buffer on success', async () => {
    const fakeBuffer = Buffer.from('fake-audio-data');
    generateSFX.mockResolvedValue({
      buffer: fakeBuffer,
      contentType: 'audio/mpeg',
    });

    const res = await request(app)
      .post('/api/audio/sfx')
      .send({ text: 'explosion', duration_seconds: 2, prompt_influence: 0.5 });

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/audio\/mpeg/);
    expect(generateSFX).toHaveBeenCalledWith({
      text: 'explosion',
      durationSeconds: 2,
      promptInfluence: 0.5,
    });
  });

  test('passes error to handler when service fails', async () => {
    generateSFX.mockRejectedValue(
      Object.assign(new Error('ELEVENLABS_API_KEY not configured'), { status: 503 })
    );

    const res = await request(app)
      .post('/api/audio/sfx')
      .send({ text: 'explosion' });

    expect(res.status).toBe(503);
    expect(res.body.error).toBe('ELEVENLABS_API_KEY not configured');
  });
});

describe('POST /api/audio/sfx/save', () => {
  const app = createApp();

  test('saves metadata and returns asset', async () => {
    const fakeAsset = {
      _id: 'abc123',
      name: 'explosion',
      type: 'sfx',
      prompt: 'explosion',
    };
    AssetAudio.create.mockResolvedValue(fakeAsset);

    const res = await request(app)
      .post('/api/audio/sfx/save')
      .send({
        prompt: 'explosion',
        duration_seconds: 2,
        prompt_influence: 0.5,
        variation_count: 10,
      });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toEqual(fakeAsset);
    expect(AssetAudio.create).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'explosion',
        type: 'sfx',
        prompt: 'explosion',
        model: 'elevenlabs-sfx',
      })
    );
  });

  test('returns 400 when prompt is missing', async () => {
    const res = await request(app)
      .post('/api/audio/sfx/save')
      .send({ duration_seconds: 2 });

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toBe('prompt is required');
  });
});

describe('GET /api/audio/history', () => {
  const app = createApp();

  test('returns list of assets', async () => {
    const fakeAssets = [
      { _id: '1', name: 'explosion', type: 'sfx', created_at: '2026-02-07' },
      { _id: '2', name: 'footsteps', type: 'sfx', created_at: '2026-02-06' },
    ];

    // rebuild the chain mock for this test
    const leanMock = jest.fn().mockResolvedValue(fakeAssets);
    const limitMock = jest.fn(() => ({ lean: leanMock }));
    const sortMock = jest.fn(() => ({ limit: limitMock }));
    AssetAudio.find.mockReturnValue({ sort: sortMock });

    const res = await request(app).get('/api/audio/history');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toHaveLength(2);
    expect(sortMock).toHaveBeenCalledWith({ created_at: -1 });
    expect(limitMock).toHaveBeenCalledWith(50);
  });

  test('returns empty state when no assets exist', async () => {
    const leanMock = jest.fn().mockResolvedValue([]);
    const limitMock = jest.fn(() => ({ lean: leanMock }));
    const sortMock = jest.fn(() => ({ limit: limitMock }));
    AssetAudio.find.mockReturnValue({ sort: sortMock });

    const res = await request(app).get('/api/audio/history');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toHaveLength(0);
  });
});

