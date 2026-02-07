// settings file management - reads/writes settings.json for api key persistence

const fs = require('fs');
const path = require('path');
const config = require('./config');

const SETTINGS_PATH = path.join(__dirname, '..', 'settings.json');

// snapshot original .env values so we can restore on clear
const envDefaults = {};

// keys that can be configured via settings ui
const CONFIGURABLE_KEYS = [
  { key: 'openrouterApiKey', label: 'openrouter' },
  { key: 'elevenlabsApiKey', label: 'elevenlabs' },
  { key: 'meshyApiKey', label: 'meshy' },
  { key: 'tripoApiKey', label: 'tripo3d' },
  { key: 'rodinApiKey', label: 'rodin' },
  { key: 'replicateApiKey', label: 'replicate' },
  { key: 'robloxApiKey', label: 'roblox open cloud' },
  { key: 'mongoUri', label: 'mongodb uri' },
];

// read settings.json if it exists
function readSettings() {
  try {
    if (fs.existsSync(SETTINGS_PATH)) {
      const raw = fs.readFileSync(SETTINGS_PATH, 'utf-8');
      return JSON.parse(raw);
    }
  } catch (err) {
    console.error('failed to read settings.json:', err.message);
  }
  return {};
}

// write settings to settings.json
function writeSettings(settings) {
  try {
    fs.writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2), 'utf-8');
  } catch (err) {
    console.error('failed to write settings.json:', err.message);
    throw Object.assign(new Error('failed to save settings'), { status: 500 });
  }
}

// apply settings.json values to in-memory config
// resets to .env defaults first, then applies overrides
function applySettings() {
  // snapshot .env defaults on first call
  if (Object.keys(envDefaults).length === 0) {
    for (const { key } of CONFIGURABLE_KEYS) {
      envDefaults[key] = config[key] || '';
    }
  }

  // reset to .env defaults
  for (const { key } of CONFIGURABLE_KEYS) {
    config[key] = envDefaults[key];
  }

  // apply settings.json overrides
  const saved = readSettings();
  for (const { key } of CONFIGURABLE_KEYS) {
    if (saved[key] && saved[key].trim()) {
      config[key] = saved[key].trim();
    }
  }
}

// mask a key value for display (show last 4 chars)
function maskValue(value) {
  if (!value || value.length <= 4) return value ? '****' : '';
  return '****' + value.slice(-4);
}

// check if a value is a real key (not a placeholder)
function isConfigured(value) {
  if (!value || !value.trim()) return false;
  if (value.includes('your_') && value.includes('_here')) return false;
  if (value.includes('username:password@')) return false;
  return true;
}

// get masked settings for frontend display
function getMaskedSettings() {
  const result = {};
  for (const { key, label } of CONFIGURABLE_KEYS) {
    result[key] = {
      label,
      value: maskValue(config[key]),
      configured: isConfigured(config[key]),
    };
  }
  return result;
}

// update settings from user input
function updateSettings(updates) {
  const saved = readSettings();
  const validKeys = CONFIGURABLE_KEYS.map((k) => k.key);

  for (const key of Object.keys(updates)) {
    if (!validKeys.includes(key)) continue;
    const value = updates[key];
    if (value === null || value === undefined) continue;

    // empty string removes the override (fall back to .env)
    if (typeof value === 'string' && value.trim() === '') {
      delete saved[key];
    } else {
      saved[key] = String(value).trim();
    }
  }

  writeSettings(saved);
  // re-apply to in-memory config
  applySettings();
  return getMaskedSettings();
}

module.exports = {
  CONFIGURABLE_KEYS,
  applySettings,
  getMaskedSettings,
  updateSettings,
};
