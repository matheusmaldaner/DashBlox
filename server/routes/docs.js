// docs routes - read/write markdown files from project directories

const express = require('express');
const router = express.Router();

// GET /api/docs/projects - list available projects
router.get('/projects', (_req, res) => {
  res.json({ success: false, error: 'not implemented' });
});

// GET /api/docs/read - read a markdown file
router.get('/read', (_req, res) => {
  res.json({ success: false, error: 'not implemented' });
});

// PUT /api/docs/write - write/update a markdown file
router.put('/write', (_req, res) => {
  res.json({ success: false, error: 'not implemented' });
});

module.exports = router;
