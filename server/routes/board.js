// board routes - kanban columns and cards CRUD

const express = require('express');
const router = express.Router();

// GET /api/board/columns - list all columns
router.get('/columns', (_req, res) => {
  res.json({ success: false, error: 'not implemented' });
});

// POST /api/board/columns - create column
router.post('/columns', (_req, res) => {
  res.json({ success: false, error: 'not implemented' });
});

// PUT /api/board/columns/:id - update column
router.put('/columns/:id', (_req, res) => {
  res.json({ success: false, error: 'not implemented' });
});

// DELETE /api/board/columns/:id - delete column
router.delete('/columns/:id', (_req, res) => {
  res.json({ success: false, error: 'not implemented' });
});

// GET /api/board/cards - list all cards
router.get('/cards', (_req, res) => {
  res.json({ success: false, error: 'not implemented' });
});

// POST /api/board/cards - create card
router.post('/cards', (_req, res) => {
  res.json({ success: false, error: 'not implemented' });
});

// PUT /api/board/cards/:id - update card
router.put('/cards/:id', (_req, res) => {
  res.json({ success: false, error: 'not implemented' });
});

// DELETE /api/board/cards/:id - delete card
router.delete('/cards/:id', (_req, res) => {
  res.json({ success: false, error: 'not implemented' });
});

// PUT /api/board/cards/:id/move - move card between columns
router.put('/cards/:id/move', (_req, res) => {
  res.json({ success: false, error: 'not implemented' });
});

module.exports = router;
