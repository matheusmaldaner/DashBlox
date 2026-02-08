// tests for model generation api routes

const request = require('supertest');
const express = require('express');

// mock services
jest.mock('../server/services/openrouter', () => ({
  enhancePrompt: jest.fn(),
}));

jest.mock('../server/services/meshy', () => ({
  createTask: jest.fn(),
  getStatus: jest.fn(),
}));

jest.mock('../server/services/tripo', () => ({
  createTask: jest.fn(),
  getStatus: jest.fn(),
}));

jest.mock('../server/services/rodin', () => ({
  createTask: jest.fn(),
  getStatus: jest.fn(),
  downloadResults: jest.fn(),
}));

jest.mock('../server/services/replicate', () => ({
  createTask: jest.fn(),
  getStatus: jest.fn(),
}));

jest.mock('../server/services/converter', () => ({
  convertBuffer: jest.fn().mockResolvedValue(Buffer.from('converted-model-data')),
  isConversionNeeded: jest.fn().mockReturnValue(false),
  checkAssimpInstalled: jest.fn().mockResolvedValue(true),
}));

jest.mock('../server/models/Asset3D', () => ({
  create: jest.fn(),
  find: jest.fn(() => ({
    sort: jest.fn(() => ({
      limit: jest.fn(() => ({
        lean: jest.fn().mockResolvedValue([]),
      })),
    })),
  })),
  findOneAndUpdate: jest.fn(),
}));

const { enhancePrompt } = require('../server/services/openrouter');
const meshy = require('../server/services/meshy');
const tripo = require('../server/services/tripo');
const rodin = require('../server/services/rodin');
const Asset3D = require('../server/models/Asset3D');
const converter = require('../server/services/converter');
const modelsRouter = require('../server/routes/models');

function createApp() {
  const app = express();
  app.use(express.json());
  app.use('/api/models', modelsRouter);
  app.use((err, _req, res, _next) => {
    res.status(err.status || 500).json({ success: false, error: err.message });
  });
  return app;
}

describe('POST /api/models/enhance-prompt', () => {
  const app = createApp();

  test('returns enhanced prompt', async () => {
    enhancePrompt.mockResolvedValue({
      enhanced: 'a detailed medieval chair with oak finish',
      model: 'google/gemini-2.5-pro',
      usage: { prompt_tokens: 50, completion_tokens: 30 },
    });

    const res = await request(app)
      .post('/api/models/enhance-prompt')
      .send({ prompt: 'medieval chair', provider: 'meshy' });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.enhanced).toBe('a detailed medieval chair with oak finish');
    expect(enhancePrompt).toHaveBeenCalledWith({
      prompt: 'medieval chair',
      provider: 'meshy',
    });
  });

  test('passes error when api key missing', async () => {
    enhancePrompt.mockRejectedValue(
      Object.assign(new Error('OPENROUTER_API_KEY not configured'), { status: 503 })
    );

    const res = await request(app)
      .post('/api/models/enhance-prompt')
      .send({ prompt: 'chair' });

    expect(res.status).toBe(503);
  });
});

describe('POST /api/models/generate', () => {
  const app = createApp();

  test('generates with meshy provider', async () => {
    meshy.createTask.mockResolvedValue({ taskId: 'meshy-task-1', provider: 'meshy' });
    Asset3D.create.mockResolvedValue({ _id: 'asset-1' });

    const res = await request(app)
      .post('/api/models/generate')
      .send({ prompt: 'a robot', provider: 'meshy' });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.taskId).toBe('meshy-task-1');
    expect(res.body.data.assetId).toBe('asset-1');
    expect(meshy.createTask).toHaveBeenCalledWith(expect.objectContaining({ prompt: 'a robot' }));
  });

  test('generates with tripo provider', async () => {
    tripo.createTask.mockResolvedValue({ taskId: 'tripo-task-1', provider: 'tripo' });
    Asset3D.create.mockResolvedValue({ _id: 'asset-2' });

    const res = await request(app)
      .post('/api/models/generate')
      .send({ prompt: 'a tree', provider: 'tripo' });

    expect(res.status).toBe(200);
    expect(res.body.data.taskId).toBe('tripo-task-1');
  });

  test('generates with rodin provider', async () => {
    rodin.createTask.mockResolvedValue({
      taskId: 'rodin-task-1',
      subscriptionKey: 'sub-key-1',
      provider: 'rodin',
    });
    Asset3D.create.mockResolvedValue({ _id: 'asset-3' });

    const res = await request(app)
      .post('/api/models/generate')
      .send({ prompt: 'a sword', provider: 'rodin' });

    expect(res.status).toBe(200);
    expect(res.body.data.taskId).toBe('rodin-task-1');
    expect(res.body.data.subscriptionKey).toBe('sub-key-1');
  });

  test('returns 400 for missing prompt', async () => {
    const res = await request(app)
      .post('/api/models/generate')
      .send({ provider: 'meshy' });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe('prompt is required');
  });

  test('returns 400 for unknown provider', async () => {
    const res = await request(app)
      .post('/api/models/generate')
      .send({ prompt: 'a robot', provider: 'unknown' });

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/unknown provider/);
  });
});

describe('GET /api/models/status/:taskId', () => {
  const app = createApp();

  test('returns meshy task status', async () => {
    meshy.getStatus.mockResolvedValue({
      taskId: 'meshy-task-1',
      status: 'generating',
      progress: 50,
      modelUrls: null,
      thumbnailUrl: null,
    });
    Asset3D.findOneAndUpdate.mockResolvedValue(null);

    const res = await request(app)
      .get('/api/models/status/meshy-task-1?provider=meshy');

    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('generating');
    expect(res.body.data.progress).toBe(50);
  });

  test('returns 400 without provider param', async () => {
    const res = await request(app)
      .get('/api/models/status/task-1');

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/provider/);
  });
});

describe('GET /api/models/history', () => {
  const app = createApp();

  test('returns list of assets', async () => {
    const fakeAssets = [
      { _id: '1', name: 'robot', provider: 'meshy', status: 'completed' },
    ];
    const leanMock = jest.fn().mockResolvedValue(fakeAssets);
    const limitMock = jest.fn(() => ({ lean: leanMock }));
    const sortMock = jest.fn(() => ({ limit: limitMock }));
    Asset3D.find.mockReturnValue({ sort: sortMock });

    const res = await request(app).get('/api/models/history');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toHaveLength(1);
  });

  test('returns empty when no assets', async () => {
    const leanMock = jest.fn().mockResolvedValue([]);
    const limitMock = jest.fn(() => ({ lean: leanMock }));
    const sortMock = jest.fn(() => ({ limit: limitMock }));
    Asset3D.find.mockReturnValue({ sort: sortMock });

    const res = await request(app).get('/api/models/history');

    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(0);
  });
});

describe('POST /api/models/upload-roblox', () => {
  const app = createApp();

  test('returns 400 when model_url is missing', async () => {
    const res = await request(app)
      .post('/api/models/upload-roblox')
      .send({});

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toBe('model_url is required');
  });
});

describe('POST /api/models/generate-image', () => {
  const app = createApp();

  test('returns 400 when no image is uploaded', async () => {
    const res = await request(app)
      .post('/api/models/generate-image')
      .field('provider', 'meshy');

    expect(res.status).toBe(400);
    expect(res.body.error).toBe('image file is required');
  });

  test('returns 400 for unknown provider', async () => {
    const imgBuffer = Buffer.from('fake image data');
    const res = await request(app)
      .post('/api/models/generate-image')
      .attach('image', imgBuffer, { filename: 'test.jpg', contentType: 'image/jpeg' })
      .field('provider', 'unknown');

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/unknown provider/);
  });

  test('generates image-to-3d with meshy provider', async () => {
    meshy.createImageTask = jest.fn().mockResolvedValue({ taskId: 'meshy-img-1', provider: 'meshy' });
    Asset3D.create.mockResolvedValue({ _id: 'asset-img-1' });

    const imgBuffer = Buffer.from('fake image data');
    const res = await request(app)
      .post('/api/models/generate-image')
      .attach('image', imgBuffer, { filename: 'test.jpg', contentType: 'image/jpeg' })
      .field('provider', 'meshy');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.taskId).toBe('meshy-img-1');
    expect(res.body.data.assetId).toBe('asset-img-1');
  });
});

describe('model format conversion in download', () => {
  const app = createApp();

  beforeEach(() => {
    jest.clearAllMocks();
    // mock global fetch for download proxy
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      headers: { get: () => 'model/gltf-binary' },
      arrayBuffer: () => Promise.resolve(new ArrayBuffer(8)),
    });
  });

  afterEach(() => {
    delete global.fetch;
  });

  test('converts when meshy provider and fbx format requested', async () => {
    converter.isConversionNeeded.mockReturnValue(true);
    meshy.getStatus.mockResolvedValue({
      taskId: 'meshy-task-1',
      status: 'ready',
      modelUrls: { glb: 'https://example.com/model.glb' },
    });

    const res = await request(app)
      .get('/api/models/download/meshy-task-1?provider=meshy&format=fbx');

    expect(res.status).toBe(200);
    expect(converter.isConversionNeeded).toHaveBeenCalledWith('meshy', 'fbx');
    expect(converter.convertBuffer).toHaveBeenCalledWith(
      expect.any(Buffer), 'glb', 'fbx'
    );
  });

  test('skips conversion for rodin with fbx format', async () => {
    converter.isConversionNeeded.mockReturnValue(false);
    rodin.downloadResults.mockResolvedValue({
      fbx: 'https://example.com/model.fbx',
      glb: 'https://example.com/model.glb',
    });

    const res = await request(app)
      .get('/api/models/download/rodin-task-1?provider=rodin&format=fbx');

    expect(res.status).toBe(200);
    expect(converter.isConversionNeeded).toHaveBeenCalledWith('rodin', 'fbx');
    expect(converter.convertBuffer).not.toHaveBeenCalled();
  });

  test('skips conversion for meshy with glb format', async () => {
    converter.isConversionNeeded.mockReturnValue(false);
    meshy.getStatus.mockResolvedValue({
      taskId: 'meshy-task-1',
      status: 'ready',
      modelUrls: { glb: 'https://example.com/model.glb' },
    });

    const res = await request(app)
      .get('/api/models/download/meshy-task-1?provider=meshy&format=glb');

    expect(res.status).toBe(200);
    expect(converter.convertBuffer).not.toHaveBeenCalled();
  });
});

describe('POST /api/models/convert-upload-roblox', () => {
  const app = createApp();

  beforeEach(() => {
    jest.clearAllMocks();
    // mock global fetch for roblox api
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ path: 'assets/12345' }),
    });
    // set roblox api key in config
    const config = require('../server/config');
    config.robloxApiKey = 'test-roblox-key';
  });

  afterEach(() => {
    delete global.fetch;
  });

  test('returns 400 when no file is uploaded', async () => {
    const res = await request(app)
      .post('/api/models/convert-upload-roblox')
      .field('name', 'test');

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/model file is required/);
  });

  test('converts glb to fbx before uploading to roblox', async () => {
    converter.convertBuffer.mockResolvedValue(Buffer.from('converted-fbx'));

    const buf = Buffer.from('fake glb data');
    const res = await request(app)
      .post('/api/models/convert-upload-roblox')
      .attach('model', buf, { filename: 'zombie.glb' })
      .field('name', 'zombie');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(converter.convertBuffer).toHaveBeenCalledWith(expect.any(Buffer), 'glb', 'fbx');
    // verify roblox api was called
    expect(global.fetch).toHaveBeenCalledWith(
      'https://apis.roblox.com/assets/v1/assets',
      expect.objectContaining({ method: 'POST' })
    );
  });

  test('skips conversion for fbx files', async () => {
    const buf = Buffer.from('fake fbx data');
    const res = await request(app)
      .post('/api/models/convert-upload-roblox')
      .attach('model', buf, { filename: 'zombie.fbx' })
      .field('name', 'zombie');

    expect(res.status).toBe(200);
    expect(converter.convertBuffer).not.toHaveBeenCalled();
    expect(global.fetch).toHaveBeenCalled();
  });

  test('returns 503 when roblox api key not configured', async () => {
    const config = require('../server/config');
    config.robloxApiKey = '';

    const buf = Buffer.from('fake glb data');
    const res = await request(app)
      .post('/api/models/convert-upload-roblox')
      .attach('model', buf, { filename: 'zombie.glb' });

    expect(res.status).toBe(503);
    expect(res.body.error).toMatch(/ROBLOX_API_KEY/);
  });
});

describe('POST /api/models/convert', () => {
  const app = createApp();

  test('returns 400 when no file is uploaded', async () => {
    const res = await request(app)
      .post('/api/models/convert')
      .field('target_format', 'fbx');

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/model file is required/);
  });

  test('returns 400 for missing target_format', async () => {
    const buf = Buffer.from('fake model data');
    const res = await request(app)
      .post('/api/models/convert')
      .attach('model', buf, { filename: 'test.glb' });

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/target_format/);
  });

  test('returns 400 when source and target formats match', async () => {
    const buf = Buffer.from('fake model data');
    const res = await request(app)
      .post('/api/models/convert')
      .attach('model', buf, { filename: 'test.fbx' })
      .field('target_format', 'fbx');

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/already in fbx format/);
  });

  test('converts glb to fbx successfully', async () => {
    converter.convertBuffer.mockResolvedValue(Buffer.from('converted-fbx'));

    const buf = Buffer.from('fake glb data');
    const res = await request(app)
      .post('/api/models/convert')
      .attach('model', buf, { filename: 'zombie.glb' })
      .field('target_format', 'fbx');

    expect(res.status).toBe(200);
    expect(converter.convertBuffer).toHaveBeenCalledWith(expect.any(Buffer), 'glb', 'fbx');
    expect(res.headers['content-disposition']).toContain('zombie.fbx');
  });
});
