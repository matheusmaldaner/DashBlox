// tests for board routes

const request = require('supertest');
const express = require('express');

// mock BoardColumn model
jest.mock('../server/models/BoardColumn', () => {
  const mockColumn = {
    _id: 'col1',
    title: 'To Do',
    position: 0,
    created_at: '2026-02-07T00:00:00Z',
  };
  return {
    find: jest.fn(() => ({
      sort: jest.fn(() => ({
        lean: jest.fn(() => Promise.resolve([mockColumn])),
      })),
    })),
    countDocuments: jest.fn(() => Promise.resolve(1)),
    create: jest.fn((data) => Promise.resolve({ _id: 'col-new', ...data })),
    findByIdAndUpdate: jest.fn((_id, update) =>
      Promise.resolve({ _id: 'col1', title: 'To Do', position: 0, ...update })
    ),
    findByIdAndDelete: jest.fn(() => Promise.resolve({ _id: 'col1', title: 'To Do' })),
  };
});

// mock BoardCard model
jest.mock('../server/models/BoardCard', () => {
  const mockCard = {
    _id: 'card1',
    column_id: 'col1',
    title: 'test card',
    description: 'test desc',
    priority: 'medium',
    labels: ['bug'],
    assignee: null,
    position: 0,
    created_at: '2026-02-07T00:00:00Z',
    updated_at: '2026-02-07T00:00:00Z',
  };
  return {
    find: jest.fn(() => ({
      sort: jest.fn(() => ({
        lean: jest.fn(() => Promise.resolve([mockCard])),
      })),
    })),
    countDocuments: jest.fn(() => Promise.resolve(1)),
    create: jest.fn((data) => Promise.resolve({ _id: 'card-new', ...data })),
    findByIdAndUpdate: jest.fn((_id, update) =>
      Promise.resolve({ _id: 'card1', column_id: 'col1', title: 'test card', ...update })
    ),
    findByIdAndDelete: jest.fn(() => Promise.resolve({ _id: 'card1', title: 'test card' })),
    deleteMany: jest.fn(() => Promise.resolve({ deletedCount: 2 })),
  };
});

const boardRoutes = require('../server/routes/board');
const BoardColumn = require('../server/models/BoardColumn');
const BoardCard = require('../server/models/BoardCard');

function createApp() {
  const app = express();
  app.use(express.json());
  app.use('/api/board', boardRoutes);
  app.use((err, _req, res, _next) => {
    res.status(err.status || 500).json({ success: false, error: err.message });
  });
  return app;
}

describe('GET /api/board/columns', () => {
  it('should list columns sorted by position', async () => {
    const app = createApp();
    const res = await request(app).get('/api/board/columns');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].title).toBe('To Do');
  });
});

describe('POST /api/board/columns', () => {
  it('should create a new column', async () => {
    const app = createApp();
    const res = await request(app).post('/api/board/columns').send({ title: 'In Progress' });

    expect(res.status).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.data.title).toBe('In Progress');
    expect(BoardColumn.create).toHaveBeenCalledWith({ title: 'In Progress', position: 1 });
  });

  it('should return 400 if title is missing', async () => {
    const app = createApp();
    const res = await request(app).post('/api/board/columns').send({});

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toMatch(/title is required/);
  });
});

describe('PUT /api/board/columns/:id', () => {
  it('should update column title', async () => {
    const app = createApp();
    const res = await request(app)
      .put('/api/board/columns/col1')
      .send({ title: 'Done' });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.title).toBe('Done');
  });

  it('should return 404 if column not found', async () => {
    BoardColumn.findByIdAndUpdate.mockResolvedValueOnce(null);
    const app = createApp();
    const res = await request(app)
      .put('/api/board/columns/nonexistent')
      .send({ title: 'test' });

    expect(res.status).toBe(404);
    expect(res.body.success).toBe(false);
  });
});

describe('DELETE /api/board/columns/:id', () => {
  it('should delete column and its cards', async () => {
    const app = createApp();
    const res = await request(app).delete('/api/board/columns/col1');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.deleted).toBe(true);
    expect(BoardCard.deleteMany).toHaveBeenCalledWith({ column_id: 'col1' });
  });
});

describe('GET /api/board/cards', () => {
  it('should list all cards', async () => {
    const app = createApp();
    const res = await request(app).get('/api/board/cards');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].title).toBe('test card');
  });
});

describe('POST /api/board/cards', () => {
  it('should create a new card', async () => {
    const app = createApp();
    const res = await request(app)
      .post('/api/board/cards')
      .send({ column_id: 'col1', title: 'new task' });

    expect(res.status).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.data.title).toBe('new task');
    expect(res.body.data.column_id).toBe('col1');
  });

  it('should return 400 if column_id or title missing', async () => {
    const app = createApp();
    const res = await request(app).post('/api/board/cards').send({ title: 'no column' });

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toMatch(/column_id and title/);
  });
});

describe('PUT /api/board/cards/:id', () => {
  it('should update a card', async () => {
    const app = createApp();
    const res = await request(app)
      .put('/api/board/cards/card1')
      .send({ title: 'updated', priority: 'high', labels: ['feature'] });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.title).toBe('updated');
    expect(res.body.data.priority).toBe('high');
  });

  it('should return 404 if card not found', async () => {
    BoardCard.findByIdAndUpdate.mockResolvedValueOnce(null);
    const app = createApp();
    const res = await request(app)
      .put('/api/board/cards/nonexistent')
      .send({ title: 'test' });

    expect(res.status).toBe(404);
    expect(res.body.success).toBe(false);
  });
});

describe('DELETE /api/board/cards/:id', () => {
  it('should delete a card', async () => {
    const app = createApp();
    const res = await request(app).delete('/api/board/cards/card1');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.deleted).toBe(true);
  });
});

describe('PUT /api/board/cards/:id/move', () => {
  it('should move card to a different column', async () => {
    const app = createApp();
    const res = await request(app)
      .put('/api/board/cards/card1/move')
      .send({ column_id: 'col2', position: 0 });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.column_id).toBe('col2');
    expect(res.body.data.position).toBe(0);
  });

  it('should return 400 if column_id or position missing', async () => {
    const app = createApp();
    const res = await request(app)
      .put('/api/board/cards/card1/move')
      .send({ column_id: 'col2' });

    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toMatch(/column_id and position/);
  });
});
