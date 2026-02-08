// mongodb schema for audio assets

const mongoose = require('mongoose');

const assetAudioSchema = new mongoose.Schema({
  project_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Project' },
  name: { type: String, required: true },
  type: {
    type: String,
    enum: ['sfx', 'tts', 'voice-clone'],
    required: true,
  },
  tags: [String],
  prompt: { type: String, default: '' },
  voice_id: { type: String, default: null },
  voice_name: { type: String, default: null },
  model: { type: String, default: '' },
  duration_seconds: { type: Number, default: 0 },
  format: { type: String, default: 'mp3' },
  file_path: { type: String, default: '' },
  variation_files: { type: [String], default: [] },
  params: { type: mongoose.Schema.Types.Mixed, default: {} },
  roblox_asset_id: { type: Number, default: null },
  created_at: { type: Date, default: Date.now },
});

module.exports = mongoose.model('AssetAudio', assetAudioSchema);
