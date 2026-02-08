// mongodb schema for 3d assets

const mongoose = require('mongoose');

const asset3DSchema = new mongoose.Schema({
  project_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Project' },
  name: { type: String, required: true },
  tags: [String],
  prompt: { type: String, required: true },
  enhanced_prompt: { type: String, default: '' },
  provider: {
    type: String,
    enum: ['meshy', 'tripo', 'rodin', 'replicate', 'roblox-cube'],
    required: true,
  },
  provider_task_id: { type: String, default: '' },
  status: {
    type: String,
    enum: ['pending', 'generating', 'ready', 'error'],
    default: 'pending',
  },
  format: {
    type: String,
    enum: ['fbx', 'glb', 'obj'],
    default: 'glb',
  },
  file_path: { type: String, default: '' },
  thumbnail_path: { type: String, default: '' },
  polycount: { type: Number, default: 0 },
  roblox_asset_id: { type: Number, default: null },
  solana_mint: { type: String, default: null },
  created_at: { type: Date, default: Date.now },
});

module.exports = mongoose.model('Asset3D', asset3DSchema);
