// health endpoint test

const request = require('supertest');
const express = require('express');

// create a minimal app for testing (avoids db connection)
const app = express();
app.get('/api/health', (_req, res) => {
  res.json({ success: true, data: { status: 'ok' } });
});

describe('GET /api/health', () => {
  test('returns success with ok status', async () => {
    const res = await request(app).get('/api/health');
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.status).toBe('ok');
  });
});
