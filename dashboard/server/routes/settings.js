// settings routes - api key configuration

const express = require('express');
const router = express.Router();
const { getMaskedSettings, updateSettings } = require('../settings');

// GET /api/settings - get current settings (masked)
router.get('/', (_req, res, next) => {
  try {
    const settings = getMaskedSettings();
    res.json({ success: true, data: settings });
  } catch (err) {
    next(err);
  }
});

// PUT /api/settings - update settings
router.put('/', (req, res, next) => {
  try {
    const updates = req.body;
    if (!updates || typeof updates !== 'object' || Array.isArray(updates)) {
      return res.status(400).json({ success: false, error: 'request body must be an object' });
    }
    const result = updateSettings(updates);
    res.json({ success: true, data: result });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
