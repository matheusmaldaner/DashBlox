// tests for docs routes

const request = require('supertest');
const express = require('express');
const path = require('path');

// mock fs.promises
jest.mock('fs', () => ({
  promises: {
    access: jest.fn(),
    readFile: jest.fn(),
    writeFile: jest.fn(),
  },
}));

// mock config
jest.mock('../server/config', () => ({
  projectPaths: ['/home/user/project1', '/home/user/project2'],
}));

const fs = require('fs').promises;
const docsRoutes = require('../server/routes/docs');

function createApp() {
  const app = express();
  app.use(express.json());
  app.use('/api/docs', docsRoutes);
  app.use((err, _req, res, _next) => {
    res.status(err.status || 500).json({ success: false, error: err.message });
  });
  return app;
}

describe('GET /api/docs/projects', () => {
  it('should list projects with their available files', async () => {
    // project1 has CLAUDE.md and PLAN.md, project2 has PROGRESS.md
    fs.access.mockImplementation((filePath) => {
      const allowed = [
        path.join('/home/user/project1', 'CLAUDE.md'),
        path.join('/home/user/project1', 'PLAN.md'),
        path.join('/home/user/project2', 'PROGRESS.md'),
      ];
      if (allowed.includes(filePath)) return Promise.resolve();
      return Promise.reject(new Error('ENOENT'));
    });

    const app = createApp();
    const res = await request(app).get('/api/docs/projects');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toHaveLength(2);
    expect(res.body.data[0].name).toBe('project1');
    expect(res.body.data[0].files).toEqual(['CLAUDE.md', 'PLAN.md']);
    expect(res.body.data[1].name).toBe('project2');
    expect(res.body.data[1].files).toEqual(['PROGRESS.md']);
  });
});

describe('GET /api/docs/read', () => {
  it('should read a markdown file', async () => {
    fs.readFile.mockResolvedValue('# hello world\n\nsome content');

    const app = createApp();
    const res = await request(app).get('/api/docs/read?project=0&file=PLAN.md');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.file).toBe('PLAN.md');
    expect(res.body.data.content).toBe('# hello world\n\nsome content');
    expect(fs.readFile).toHaveBeenCalledWith(
      path.resolve('/home/user/project1', 'PLAN.md'),
      'utf-8'
    );
  });

  it('should return 400 if project or file missing', async () => {
    const app = createApp();
    const res = await request(app).get('/api/docs/read?project=0');

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toMatch(/project and file/);
  });

  it('should return 400 for disallowed file names', async () => {
    const app = createApp();
    const res = await request(app).get('/api/docs/read?project=0&file=../../etc/passwd');

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toMatch(/file not allowed/);
  });

  it('should return 400 for invalid project index', async () => {
    const app = createApp();
    const res = await request(app).get('/api/docs/read?project=99&file=PLAN.md');

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toMatch(/invalid project index/);
  });

  it('should return 404 if file does not exist', async () => {
    fs.readFile.mockRejectedValue(Object.assign(new Error('no such file'), { code: 'ENOENT' }));

    const app = createApp();
    const res = await request(app).get('/api/docs/read?project=0&file=PROGRESS.md');

    expect(res.status).toBe(404);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toBe('file not found');
  });
});

describe('PUT /api/docs/write', () => {
  it('should write content to a markdown file', async () => {
    fs.writeFile.mockResolvedValue();

    const app = createApp();
    const res = await request(app)
      .put('/api/docs/write')
      .send({ project: 0, file: 'PLAN.md', content: '# updated plan' });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.file).toBe('PLAN.md');
    expect(res.body.data.saved).toBe(true);
    expect(fs.writeFile).toHaveBeenCalledWith(
      path.resolve('/home/user/project1', 'PLAN.md'),
      '# updated plan',
      'utf-8'
    );
  });

  it('should return 400 if required fields missing', async () => {
    const app = createApp();
    const res = await request(app).put('/api/docs/write').send({ project: 0, file: 'PLAN.md' });

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toMatch(/project, file, and content/);
  });

  it('should return 400 for disallowed file names on write', async () => {
    const app = createApp();
    const res = await request(app)
      .put('/api/docs/write')
      .send({ project: 0, file: 'package.json', content: '{}' });

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toMatch(/file not allowed/);
  });

  it('should allow writing empty content', async () => {
    fs.writeFile.mockResolvedValue();

    const app = createApp();
    const res = await request(app)
      .put('/api/docs/write')
      .send({ project: 1, file: 'PROGRESS.md', content: '' });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });
});
